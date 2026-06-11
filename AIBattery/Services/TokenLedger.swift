import Foundation

/// Persistent high-water-mark storage for per-model token totals.
///
/// Claude Code's `stats-cache.json` can be rebuilt with fewer historical logs,
/// causing token totals to drop. The ledger preserves the highest-ever-seen
/// value for each token type per model, ensuring totals never decrease.
///
/// - Read: once at init (cached in memory)
/// - Write: only when values increase (background I/O, atomic)
/// - File: `~/Library/Application Support/AIBattery/token-ledger.json`
final class TokenLedger: @unchecked Sendable {
    static let shared = TokenLedger()

    private let fileURL: URL
    private var ledger: LedgerData
    /// Tracks whether `ledger` has unflushed changes since the last write.
    /// `flushForTesting()` checks this so a no-op merge doesn't touch the file.
    private var isDirty = false
    /// Guards all reads/writes to `ledger` — prevents concurrent Task.detached calls
    /// from racing on dictionary mutation (EXC_BAD_ACCESS in Dictionary.subscript.setter).
    private let lock = NSLock()
    /// Serial queue for encode-then-write. Two rapid merges used to be able to race:
    /// flush A would encode, release the lock, merge B would mutate, flush B would
    /// encode and write, then flush A's later write would overwrite with its stale
    /// snapshot. Running every flush on one serial queue makes encoding order ==
    /// write order, so the latest encoded state always lands last on disk.
    private let writeQueue = DispatchQueue(label: "com.KyleNesium.AIBattery.TokenLedger.write", qos: .utility)

    init(fileURL: URL? = nil) {
        let url = fileURL ?? Self.defaultFileURL
        self.fileURL = url
        self.ledger = Self.load(from: url)
    }

    // MARK: - Merge

    /// Merge current model tokens with stored high-water marks.
    /// Returns an array with the maximum of current vs stored values for each token type.
    /// Includes historical models no longer in current stats-cache/JSONL data.
    /// Writes to disk only when values increase.
    func merge(_ tokens: [ModelTokenSummary], accountId: String) -> [ModelTokenSummary] {
        lock.lock()
        defer { lock.unlock() }

        var accountData = ledger.accounts[accountId] ?? [:]
        var changed = false
        var result: [ModelTokenSummary] = []
        var seenModels = Set<String>()

        for model in tokens {
            seenModels.insert(model.id)
            let stored = accountData[model.id]
            let merged = ModelTokenRecord(
                input: max(model.inputTokens, stored?.input ?? 0),
                output: max(model.outputTokens, stored?.output ?? 0),
                cacheRead: max(model.cacheReadTokens, stored?.cacheRead ?? 0),
                cacheWrite: max(model.cacheWriteTokens, stored?.cacheWrite ?? 0)
            )

            if merged != stored {
                accountData[model.id] = merged
                changed = true
            }

            let cost = ModelPricing.pricing(for: model.id)?.cost(
                input: merged.input, output: merged.output,
                cacheRead: merged.cacheRead, cacheWrite: merged.cacheWrite
            ) ?? 0
            result.append(ModelTokenSummary(
                id: model.id,
                displayName: model.displayName,
                inputTokens: merged.input,
                outputTokens: merged.output,
                cacheReadTokens: merged.cacheRead,
                cacheWriteTokens: merged.cacheWrite,
                estimatedCost: cost
            ))
        }

        // Restore historical models no longer in current stats-cache/JSONL
        for (modelId, record) in accountData where !seenModels.contains(modelId) {
            let cost = ModelPricing.pricing(for: modelId)?.cost(
                input: record.input, output: record.output,
                cacheRead: record.cacheRead, cacheWrite: record.cacheWrite
            ) ?? 0
            result.append(ModelTokenSummary(
                id: modelId,
                displayName: ModelNameMapper.displayName(for: modelId),
                inputTokens: record.input,
                outputTokens: record.output,
                cacheReadTokens: record.cacheRead,
                cacheWriteTokens: record.cacheWrite,
                estimatedCost: cost
            ))
        }

        if changed {
            ledger.accounts[accountId] = accountData
            isDirty = true
            save()
        }

        return result.sorted { $0.totalTokens > $1.totalTokens }
    }

    // MARK: - Account lifecycle

    /// Move a pending account's high-water marks into its resolved real-org-id entry,
    /// then drop the pending entry. Called from `OAuthManager.resolveAccountIdentity`
    /// when a `pending-<uuid>` account's identity resolves, so its accumulated token
    /// history follows the account instead of orphaning in the ledger forever.
    /// High-water semantics are preserved: the target keeps the max of both entries.
    func migrate(from oldId: String, to newId: String) {
        lock.lock()
        defer { lock.unlock() }
        guard oldId != newId, let oldData = ledger.accounts[oldId] else { return }

        var target = ledger.accounts[newId] ?? [:]
        for (modelId, record) in oldData {
            let existing = target[modelId]
            target[modelId] = ModelTokenRecord(
                input: max(record.input, existing?.input ?? 0),
                output: max(record.output, existing?.output ?? 0),
                cacheRead: max(record.cacheRead, existing?.cacheRead ?? 0),
                cacheWrite: max(record.cacheWrite, existing?.cacheWrite ?? 0)
            )
        }
        ledger.accounts[newId] = target
        ledger.accounts.removeValue(forKey: oldId)
        isDirty = true
        save()
    }

    /// Drop ledger entries for accounts the user no longer has — orphaned `pending-<uuid>`
    /// ids left by pre-migration identity resolutions, removed accounts, and any stray
    /// test-account ids that leaked into the file. Called once on launch with the live
    /// account ids.
    ///
    /// No-op when `liveAccountIds` is empty so a logged-out / fresh-launch transient
    /// state can never wipe legitimately-held high-water history.
    func pruneAccounts(keeping liveAccountIds: Set<String>) {
        guard !liveAccountIds.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        let before = ledger.accounts.count
        ledger.accounts = ledger.accounts.filter { liveAccountIds.contains($0.key) }
        if ledger.accounts.count != before {
            isDirty = true
            save()
        }
    }

    // MARK: - Storage

    private static var defaultFileURL: URL {
        AppPaths.applicationSupport().appendingPathComponent("token-ledger.json")
    }

    private static func load(from url: URL) -> LedgerData {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int,
              size <= 1_000_000,
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(LedgerData.self, from: data) else {
            return LedgerData()
        }
        return decoded
    }

    private func save() {
        writeQueue.async { [weak self] in
            self?.flushIfDirty()
        }
    }

    /// Synchronous write for testing — ensures data is on disk before returning.
    /// Runs on `writeQueue` so any pending async flushes drain first, matching
    /// the production ordering guarantee.
    func flushForTesting() {
        writeQueue.sync {
            self.flushIfDirty()
        }
    }

    /// Shared flush path for both async `save()` and sync `flushForTesting()`.
    /// **Must only be called from `writeQueue`** — running on the serial queue is
    /// what guarantees encoding order == write order across rapid successive merges.
    /// No-op when no merge has mutated the ledger since the last flush — prevents
    /// duplicate writes from racing `save` Tasks and test flushes.
    private func flushIfDirty() {
        lock.lock()
        guard isDirty else { lock.unlock(); return }
        let encoded = try? JSONEncoder().encode(ledger)
        isDirty = false
        lock.unlock()
        guard let encoded else { return }
        do {
            try encoded.write(to: fileURL, options: .atomic)
        } catch {
            // Write failed (disk full, permissions, transient FS error). Re-mark dirty so
            // the next flush retries — without this, every subsequent `save()` becomes a
            // no-op until a new merge mutates state, silently losing high-water marks.
            lock.lock()
            isDirty = true
            lock.unlock()
            AppLogger.general.warning("TokenLedger save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - Data types

extension TokenLedger {
    struct LedgerData: Codable {
        var accounts: [String: [String: ModelTokenRecord]] = [:]
    }

    struct ModelTokenRecord: Codable, Equatable {
        let input: Int
        let output: Int
        let cacheRead: Int
        let cacheWrite: Int
    }
}

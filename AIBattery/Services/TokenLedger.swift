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

    // MARK: - Storage

    private static var defaultFileURL: URL {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Application Support directory unavailable")
        }
        let dir = appSupport.appendingPathComponent("AIBattery")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("token-ledger.json")
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
        Task.detached(priority: .utility) { [weak self] in
            self?.flushIfDirty()
        }
    }

    /// Synchronous write for testing — ensures data is on disk before returning.
    func flushForTesting() {
        flushIfDirty()
    }

    /// Shared flush path for both async `save()` and sync `flushForTesting()`.
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

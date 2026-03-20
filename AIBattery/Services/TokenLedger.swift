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
            save()
        }

        return result.sorted { $0.totalTokens > $1.totalTokens }
    }

    // MARK: - Storage

    private static var defaultFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
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
        guard let encoded = try? JSONEncoder().encode(ledger) else { return }
        let url = fileURL
        Task.detached(priority: .utility) {
            do {
                try encoded.write(to: url, options: .atomic)
            } catch {
                AppLogger.general.warning("TokenLedger save failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Synchronous write for testing — ensures data is on disk before returning.
    func flushForTesting() {
        guard let encoded = try? JSONEncoder().encode(ledger) else { return }
        try? encoded.write(to: fileURL, options: .atomic)
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

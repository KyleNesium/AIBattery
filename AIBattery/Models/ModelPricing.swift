import Foundation

/// Per-model pricing for API cost equivalence.
/// Prices are per million tokens from Anthropic's published API rates.
/// Shows what the same token usage would cost on the pay-per-token API —
/// Pro/Max/Teams subscribers aren't billed per-token.
struct ModelPricing {
    let inputPerMillion: Double
    let outputPerMillion: Double
    let cacheWritePerMillion: Double
    let cacheReadPerMillion: Double

    /// Calculate cost in dollars for a given token breakdown.
    func cost(input: Int, output: Int, cacheRead: Int, cacheWrite: Int) -> Double {
        (Double(input) * inputPerMillion
            + Double(output) * outputPerMillion
            + Double(cacheRead) * cacheReadPerMillion
            + Double(cacheWrite) * cacheWritePerMillion) / 1_000_000.0
    }

    /// Format a dollar amount for display.
    static func formatCost(_ cost: Double) -> String {
        if cost == 0 {
            return "$0.00"
        }
        if cost < 0.01 {
            return "<$0.01"
        }
        return String(format: "$%.2f", cost)
    }

    /// Compact cost format — drops cents for >= $1 (e.g. "$18"), keeps precision for small amounts.
    static func formatCompactCost(_ cost: Double) -> String {
        if cost == 0 {
            return "$0"
        }
        if cost < 0.01 {
            return "<$0.01"
        }
        if cost < 1 {
            return String(format: "$%.2f", cost)
        }
        if cost < 1_000 {
            return String(format: "$%.0f", cost)
        }
        let k = cost / 1_000
        return k == k.rounded() ? "$\(Int(k))K" : String(format: "$%.1fK", k)
    }

    /// Lookup cache — avoids repeated displayName + linear scan per model ID.
    /// Lock-protected for thread safety (Swift Testing runs tests concurrently).
    /// Uses `Optional<ModelPricing>` values; key presence means "already looked up",
    /// nil value means "looked up but no match found".
    /// `nonisolated(unsafe)` is the right call here: every read/write is guarded by
    /// `cacheLock` below, so the data is concurrency-safe even though Swift can't see it.
    nonisolated(unsafe) private static var pricingCache: [String: ModelPricing?] = [:]
    private static let cacheLock = NSLock()

    /// Look up pricing by model ID. Uses `ModelNameMapper.displayName` for matching.
    /// Results are cached per model ID since the pricing table is static.
    static func pricing(for modelId: String) -> ModelPricing? {
        // Check cache first (fast path) — key presence means we've already looked up
        let hit: (found: Bool, value: ModelPricing?) = cacheLock.withLock {
            if let entry = pricingCache.index(forKey: modelId) {
                return (true, pricingCache[entry].value)
            }
            return (false, nil)
        }
        if hit.found { return hit.value }

        // Compute outside the lock — avoids nested lock with ModelNameMapper.
        // Linear scan over 6 entries is fine — result is cached per modelId above.
        let display = ModelNameMapper.displayName(for: modelId).lowercased()
        var result: ModelPricing?
        for (key, pricing) in pricingTable {
            if display.contains(key) {
                result = pricing
                break
            }
        }

        // Store in cache (including nil for unknown models)
        cacheLock.withLock { pricingCache[modelId] = result }
        return result
    }

    /// Total cost across all model summaries (uses pre-computed estimatedCost).
    static func totalCost(for models: [ModelTokenSummary]) -> Double {
        models.reduce(0) { $0 + $1.estimatedCost }
    }

    // MARK: - Pricing Table

    // Cache write = 1.25× input price, cache read = 0.1× input price (Anthropic published rates)
    private static let pricingTable: [(String, ModelPricing)] = [
        ("opus 4", ModelPricing(inputPerMillion: 15, outputPerMillion: 75, cacheWritePerMillion: 18.75, cacheReadPerMillion: 1.50)),
        ("sonnet 4", ModelPricing(inputPerMillion: 3, outputPerMillion: 15, cacheWritePerMillion: 3.75, cacheReadPerMillion: 0.30)),
        ("haiku 4", ModelPricing(inputPerMillion: 0.80, outputPerMillion: 4, cacheWritePerMillion: 1.00, cacheReadPerMillion: 0.08)),
        ("sonnet 3.5", ModelPricing(inputPerMillion: 3, outputPerMillion: 15, cacheWritePerMillion: 3.75, cacheReadPerMillion: 0.30)),
        ("haiku 3.5", ModelPricing(inputPerMillion: 0.80, outputPerMillion: 4, cacheWritePerMillion: 1.00, cacheReadPerMillion: 0.08)),
        ("opus 3", ModelPricing(inputPerMillion: 15, outputPerMillion: 75, cacheWritePerMillion: 18.75, cacheReadPerMillion: 1.50)),
    ]
}

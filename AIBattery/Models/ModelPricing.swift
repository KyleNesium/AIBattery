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
        if hit.found {
            return hit.value
        }

        // Compute outside the lock — avoids nested lock with ModelNameMapper.
        var result: ModelPricing?
        if modelId.lowercased().hasPrefix("gpt-") {
            // Codex / OpenAI models — matched on the raw ID (see OpenAIModelPricing).
            result = OpenAIModelPricing.pricing(for: modelId)
        } else {
            // Linear scan over 6 entries is fine — result is cached per modelId above.
            let display = ModelNameMapper.displayName(for: modelId).lowercased()
            for (key, pricing) in pricingTable where display.contains(key) {
                result = pricing
                break
            }
            if result == nil {
                // Unknown minor version of a known family — bill at the family rate rather
                // than returning nil, which costs the model's whole usage at $0.
                for (family, pricing) in familyFallback where display.contains(family) {
                    result = pricing
                    break
                }
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

    // Anthropic's published per-million API rates
    // (platform.claude.com/docs/en/about-claude/pricing, checked 2026-10-10).
    //
    // Matching is `displayName(for:).lowercased().contains(key)` and the FIRST hit wins, so
    // every entry must precede any shorter key that would otherwise swallow it — "opus 5.5"
    // before "opus 5", "fable 5.1" before "fable 5", the "opus 4.5"…"4.8" rows before the
    // retired-generation "opus 4".
    //
    // Cache write is the 5-minute rate; cache read is the "cache hits and refreshes" rate.
    // These stopped being a fixed multiple of input with the 5 family — Fable 5.1 reads at
    // $0.25/MTok while Fable 5 reads at $1.00 on the same $10 input — so copy the published
    // figures, never re-derive them as 1.25x / 0.1x input.
    private static let pricingTable: [(String, ModelPricing)] = [
        ("fable 5.1", ModelPricing(inputPerMillion: 10, outputPerMillion: 50, cacheWritePerMillion: 12.50, cacheReadPerMillion: 0.25)),
        ("mythos 5.1", ModelPricing(inputPerMillion: 10, outputPerMillion: 50, cacheWritePerMillion: 12.50, cacheReadPerMillion: 0.25)),
        ("fable 5", ModelPricing(inputPerMillion: 10, outputPerMillion: 50, cacheWritePerMillion: 12.50, cacheReadPerMillion: 1.00)),
        ("mythos 5", ModelPricing(inputPerMillion: 10, outputPerMillion: 50, cacheWritePerMillion: 12.50, cacheReadPerMillion: 1.00)),
        ("opus 5.5", ModelPricing(inputPerMillion: 4, outputPerMillion: 20, cacheWritePerMillion: 5, cacheReadPerMillion: 0.20)),
        ("opus 5", ModelPricing(inputPerMillion: 5, outputPerMillion: 25, cacheWritePerMillion: 6.25, cacheReadPerMillion: 0.50)),
        ("opus 4.8", ModelPricing(inputPerMillion: 5, outputPerMillion: 25, cacheWritePerMillion: 6.25, cacheReadPerMillion: 0.50)),
        ("opus 4.7", ModelPricing(inputPerMillion: 5, outputPerMillion: 25, cacheWritePerMillion: 6.25, cacheReadPerMillion: 0.50)),
        ("opus 4.6", ModelPricing(inputPerMillion: 5, outputPerMillion: 25, cacheWritePerMillion: 6.25, cacheReadPerMillion: 0.50)),
        ("opus 4.5", ModelPricing(inputPerMillion: 5, outputPerMillion: 25, cacheWritePerMillion: 6.25, cacheReadPerMillion: 0.50)),
        // Opus 4 / 4.1 are retired but still appear in old local history.
        ("opus 4", ModelPricing(inputPerMillion: 15, outputPerMillion: 75, cacheWritePerMillion: 18.75, cacheReadPerMillion: 1.50)),
        ("opus 3", ModelPricing(inputPerMillion: 15, outputPerMillion: 75, cacheWritePerMillion: 18.75, cacheReadPerMillion: 1.50)),
        ("sonnet 5.5", ModelPricing(inputPerMillion: 2, outputPerMillion: 10, cacheWritePerMillion: 2.50, cacheReadPerMillion: 0.10)),
        ("sonnet 5", ModelPricing(inputPerMillion: 2, outputPerMillion: 10, cacheWritePerMillion: 2.50, cacheReadPerMillion: 0.20)),
        ("sonnet 4", ModelPricing(inputPerMillion: 3, outputPerMillion: 15, cacheWritePerMillion: 3.75, cacheReadPerMillion: 0.30)),
        ("sonnet 3.5", ModelPricing(inputPerMillion: 3, outputPerMillion: 15, cacheWritePerMillion: 3.75, cacheReadPerMillion: 0.30)),
        // Catches Sonnet 3 and 3.7 (both retired, both still present in old local JSONL).
        // Every published Sonnet from 3 through 4.6 billed at $3/$15; without this row
        // they fell through to the family fallback and were billed at the Sonnet 5 rate.
        // Must stay AFTER "sonnet 3.5" — "Sonnet 3.5" contains "sonnet 3".
        ("sonnet 3", ModelPricing(inputPerMillion: 3, outputPerMillion: 15, cacheWritePerMillion: 3.75, cacheReadPerMillion: 0.30)),
        // Haiku 5.5 bills at a higher tier above 100K prompt tokens; the base tier is used
        // here because the local JSONL carries no per-request prompt size to branch on.
        ("haiku 5.5", ModelPricing(inputPerMillion: 0.10, outputPerMillion: 0.50, cacheWritePerMillion: 0.125, cacheReadPerMillion: 0.01)),
        // 4.5 is the only Haiku in the 4 generation.
        ("haiku 4", ModelPricing(inputPerMillion: 1, outputPerMillion: 5, cacheWritePerMillion: 1.25, cacheReadPerMillion: 0.10)),
        ("haiku 3.5", ModelPricing(inputPerMillion: 0.80, outputPerMillion: 4, cacheWritePerMillion: 1.00, cacheReadPerMillion: 0.08)),
    ]

    /// Match keys in table order — the `contains` scan is order-dependent, so the ordering
    /// invariant is asserted in tests rather than left to review.
    static var tableKeys: [String] { pricingTable.map(\.0) }

    /// Family-level rates for a Claude model whose exact version is not in `pricingTable`.
    ///
    /// Without this, a model released after the table was last updated matches nothing,
    /// `pricing(for:)` returns nil, and every token it used is costed at **$0** — silently
    /// dropping it out of the Insights cost, the per-project cost and the all-time total.
    /// That is exactly what happened to the whole Claude 5 family. An approximate rate from
    /// the right family beats a confidently wrong zero, so an unknown minor version now bills
    /// at its family's current-generation rate.
    private static let familyFallback: [(String, ModelPricing)] = [
        ("fable", ModelPricing(inputPerMillion: 10, outputPerMillion: 50, cacheWritePerMillion: 12.50, cacheReadPerMillion: 0.25)),
        ("mythos", ModelPricing(inputPerMillion: 10, outputPerMillion: 50, cacheWritePerMillion: 12.50, cacheReadPerMillion: 0.25)),
        ("opus", ModelPricing(inputPerMillion: 5, outputPerMillion: 25, cacheWritePerMillion: 6.25, cacheReadPerMillion: 0.50)),
        ("sonnet", ModelPricing(inputPerMillion: 2, outputPerMillion: 10, cacheWritePerMillion: 2.50, cacheReadPerMillion: 0.20)),
        ("haiku", ModelPricing(inputPerMillion: 1, outputPerMillion: 5, cacheWritePerMillion: 1.25, cacheReadPerMillion: 0.10)),
    ]
}

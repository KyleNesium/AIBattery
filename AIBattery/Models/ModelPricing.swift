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
        if cost < 0.01 {
            return "<$0.01"
        }
        return String(format: "$%.2f", cost)
    }

    /// Look up pricing by model ID. Uses `ModelNameMapper.displayName` for matching.
    static func pricing(for modelId: String) -> ModelPricing? {
        let display = ModelNameMapper.displayName(for: modelId).lowercased()
        for (key, pricing) in pricingTable {
            if display.contains(key) {
                return pricing
            }
        }
        return nil
    }

    /// Total cost across all model summaries.
    static func totalCost(for models: [ModelTokenSummary]) -> Double {
        models.reduce(0) { total, model in
            guard let pricing = pricing(for: model.id) else { return total }
            return total + pricing.cost(
                input: model.inputTokens,
                output: model.outputTokens,
                cacheRead: model.cacheReadTokens,
                cacheWrite: model.cacheWriteTokens
            )
        }
    }

    // MARK: - Pricing Table

    private static let pricingTable: [(String, ModelPricing)] = [
        ("opus 4", ModelPricing(inputPerMillion: 15, outputPerMillion: 75, cacheWritePerMillion: 1.875, cacheReadPerMillion: 1.50)),
        ("sonnet 4", ModelPricing(inputPerMillion: 3, outputPerMillion: 15, cacheWritePerMillion: 0.375, cacheReadPerMillion: 0.30)),
        ("haiku 4", ModelPricing(inputPerMillion: 0.80, outputPerMillion: 4, cacheWritePerMillion: 0.10, cacheReadPerMillion: 0.08)),
        ("sonnet 3.5", ModelPricing(inputPerMillion: 3, outputPerMillion: 15, cacheWritePerMillion: 0.375, cacheReadPerMillion: 0.30)),
        ("haiku 3.5", ModelPricing(inputPerMillion: 0.80, outputPerMillion: 4, cacheWritePerMillion: 0.10, cacheReadPerMillion: 0.08)),
        ("opus 3", ModelPricing(inputPerMillion: 15, outputPerMillion: 75, cacheWritePerMillion: 1.875, cacheReadPerMillion: 1.50)),
    ]
}

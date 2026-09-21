import Foundation

/// OpenAI per-model pricing for Codex API-equivalent cost (USD per 1M tokens).
/// Source: developers.openai.com/api/docs/pricing, read 2026-09-21. Shows what the
/// same tokens would cost on the pay-per-token API — ChatGPT-plan Codex users aren't
/// billed per token, so this is subscription value, never a bill.
///
/// OpenAI has no separate cache-write price, so `cacheWritePerMillion` = input rate;
/// `cacheReadPerMillion` = the published cached-input rate.
enum OpenAIModelPricing {
    /// Ordered longest-prefix-first so `gpt-5.6-sol` matches before `gpt-5`, and
    /// `gpt-5-mini` never falls through to the `gpt-5` row.
    static let table: [(prefix: String, pricing: ModelPricing)] = [
        ("gpt-5.6-terra", rate(input: 2.00, output: 12.00, cached: 0.20)),
        ("gpt-5.6-luna", rate(input: 0.20, output: 1.20, cached: 0.02)),
        ("gpt-5.6-sol", rate(input: 4.00, output: 20.00, cached: 0.40)),
        ("gpt-5.3-codex", rate(input: 1.75, output: 14.00, cached: 0.175)),
        ("gpt-5.2-pro", rate(input: 21.00, output: 168.00, cached: 21.00)),
        ("gpt-5-codex", rate(input: 1.25, output: 10.00, cached: 0.125)),
        ("gpt-5-mini", rate(input: 0.25, output: 2.00, cached: 0.025)),
        ("gpt-5-nano", rate(input: 0.05, output: 0.40, cached: 0.005)),
        ("gpt-5-pro", rate(input: 15.00, output: 120.00, cached: 15.00)),
        ("gpt-5.5", rate(input: 5.00, output: 30.00, cached: 0.50)),
        ("gpt-5.4", rate(input: 2.50, output: 15.00, cached: 0.25)),
        ("gpt-5.2", rate(input: 1.75, output: 14.00, cached: 0.175)),
        ("gpt-5.1", rate(input: 1.25, output: 10.00, cached: 0.125)),
        ("gpt-5", rate(input: 1.25, output: 10.00, cached: 0.125)),
    ]

    /// Longest-prefix match on the lowercased model ID; nil for unknown `gpt-*` IDs
    /// (e.g. `gpt-4o`) so they show no cost rather than a wrong one.
    static func pricing(for modelId: String) -> ModelPricing? {
        let id = modelId.lowercased()
        return table.first { id == $0.prefix || id.hasPrefix($0.prefix + "-") || id.hasPrefix($0.prefix + ".") }?.pricing
    }

    private static func rate(input: Double, output: Double, cached: Double) -> ModelPricing {
        ModelPricing(inputPerMillion: input, outputPerMillion: output, cacheWritePerMillion: input, cacheReadPerMillion: cached)
    }
}

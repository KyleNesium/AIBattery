import Testing
@testable import AIBatteryCore

@Suite("ModelPricing")
struct ModelPricingTests {

    // MARK: - Lookup

    @Test func pricing_opus4() {
        let pricing = ModelPricing.pricing(for: "claude-opus-4-6-20250929")
        #expect(pricing != nil)
        #expect(pricing?.inputPerMillion == 15)
        #expect(pricing?.outputPerMillion == 75)
    }

    @Test func pricing_sonnet4() {
        let pricing = ModelPricing.pricing(for: "claude-sonnet-4-5-20250929")
        #expect(pricing != nil)
        #expect(pricing?.inputPerMillion == 3)
    }

    @Test func pricing_haiku4() {
        let pricing = ModelPricing.pricing(for: "claude-haiku-4-5-20251001")
        #expect(pricing != nil)
        #expect(pricing?.inputPerMillion == 0.80)
    }

    @Test func pricing_sonnet35() {
        let pricing = ModelPricing.pricing(for: "claude-3-5-sonnet-20241022")
        #expect(pricing != nil)
        #expect(pricing?.inputPerMillion == 3)
    }

    @Test func pricing_haiku35() {
        let pricing = ModelPricing.pricing(for: "claude-3-5-haiku-20241022")
        #expect(pricing != nil)
    }

    @Test func pricing_opus3() {
        let pricing = ModelPricing.pricing(for: "claude-3-opus-20240229")
        #expect(pricing != nil)
        #expect(pricing?.inputPerMillion == 15)
    }

    @Test func pricing_unknownModel() {
        let pricing = ModelPricing.pricing(for: "unknown-model")
        #expect(pricing == nil)
    }

    // MARK: - Cost calculation

    @Test func cost_zeroTokens() {
        let pricing = ModelPricing(inputPerMillion: 3, outputPerMillion: 15, cacheWritePerMillion: 0.375, cacheReadPerMillion: 0.30)
        let cost = pricing.cost(input: 0, output: 0, cacheRead: 0, cacheWrite: 0)
        #expect(cost == 0)
    }

    @Test func cost_onlyInput() {
        let pricing = ModelPricing(inputPerMillion: 3, outputPerMillion: 15, cacheWritePerMillion: 0.375, cacheReadPerMillion: 0.30)
        let cost = pricing.cost(input: 1_000_000, output: 0, cacheRead: 0, cacheWrite: 0)
        #expect(cost == 3.0)
    }

    @Test func cost_allTypes() {
        let pricing = ModelPricing(inputPerMillion: 3, outputPerMillion: 15, cacheWritePerMillion: 0.375, cacheReadPerMillion: 0.30)
        let cost = pricing.cost(input: 1_000_000, output: 1_000_000, cacheRead: 1_000_000, cacheWrite: 1_000_000)
        #expect(abs(cost - 18.675) < 0.001)
    }

    // MARK: - Format

    @Test func formatCost_zero() {
        #expect(ModelPricing.formatCost(0) == "$0.00")
    }

    @Test func formatCost_small() {
        #expect(ModelPricing.formatCost(0.005) == "<$0.01")
    }

    @Test func formatCost_penny() {
        #expect(ModelPricing.formatCost(0.01) == "$0.01")
    }

    @Test func formatCost_dollars() {
        #expect(ModelPricing.formatCost(12.345) == "$12.35")
    }

    @Test func formatCost_large() {
        #expect(ModelPricing.formatCost(100.0) == "$100.00")
    }

    // MARK: - Total cost

    @Test func totalCost_empty() {
        #expect(ModelPricing.totalCost(for: []) == 0)
    }

    @Test func totalCost_unknownModel() {
        let model = ModelTokenSummary(id: "unknown", displayName: "Unknown", inputTokens: 1000, outputTokens: 1000, cacheReadTokens: 0, cacheWriteTokens: 0)
        #expect(ModelPricing.totalCost(for: [model]) == 0)
    }

    @Test func totalCost_mixedKnownAndUnknown() {
        let known = ModelTokenSummary(id: "claude-sonnet-4-5-20250929", displayName: "Sonnet 4.5", inputTokens: 1_000_000, outputTokens: 0, cacheReadTokens: 0, cacheWriteTokens: 0)
        let unknown = ModelTokenSummary(id: "unknown", displayName: "Unknown", inputTokens: 1_000_000, outputTokens: 1_000_000, cacheReadTokens: 0, cacheWriteTokens: 0)
        let total = ModelPricing.totalCost(for: [known, unknown])
        // Only Sonnet input: $3/M × 1M = $3
        #expect(abs(total - 3.0) < 0.001)
    }

    @Test func totalCost_multipleKnownModels() {
        let opus = ModelTokenSummary(id: "claude-opus-4-6-20250929", displayName: "Opus 4.6", inputTokens: 1_000_000, outputTokens: 0, cacheReadTokens: 0, cacheWriteTokens: 0)
        let sonnet = ModelTokenSummary(id: "claude-sonnet-4-5-20250929", displayName: "Sonnet 4.5", inputTokens: 1_000_000, outputTokens: 0, cacheReadTokens: 0, cacheWriteTokens: 0)
        let total = ModelPricing.totalCost(for: [opus, sonnet])
        // Opus input: $15 + Sonnet input: $3 = $18
        #expect(abs(total - 18.0) < 0.001)
    }

    // MARK: - Cost calculation edge cases

    @Test func cost_cacheOnlyTokens() {
        let pricing = ModelPricing(inputPerMillion: 3, outputPerMillion: 15, cacheWritePerMillion: 0.375, cacheReadPerMillion: 0.30)
        let cost = pricing.cost(input: 0, output: 0, cacheRead: 2_000_000, cacheWrite: 1_000_000)
        // cacheRead: 0.30 × 2 = 0.60, cacheWrite: 0.375 × 1 = 0.375
        #expect(abs(cost - 0.975) < 0.001)
    }

    @Test func cost_largeTokenCounts() {
        let pricing = ModelPricing(inputPerMillion: 15, outputPerMillion: 75, cacheWritePerMillion: 1.875, cacheReadPerMillion: 1.50)
        let cost = pricing.cost(input: 100_000_000, output: 10_000_000, cacheRead: 50_000_000, cacheWrite: 5_000_000)
        // input: 15 × 100 = 1500, output: 75 × 10 = 750, cacheRead: 1.50 × 50 = 75, cacheWrite: 1.875 × 5 = 9.375
        #expect(abs(cost - 2334.375) < 0.01)
    }

    // MARK: - Format edge cases

    @Test func formatCost_negative() {
        // Negative values shouldn't happen but shouldn't crash
        let result = ModelPricing.formatCost(-5.0)
        #expect(result == "<$0.01")
    }

    @Test func formatCost_exactDollar() {
        #expect(ModelPricing.formatCost(1.0) == "$1.00")
    }
}

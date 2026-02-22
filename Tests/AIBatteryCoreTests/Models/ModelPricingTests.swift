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
        #expect(ModelPricing.formatCost(0) == "<$0.01")
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
}

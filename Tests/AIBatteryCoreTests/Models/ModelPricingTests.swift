import Testing
@testable import AIBatteryCore

@Suite("ModelPricing")
struct ModelPricingTests {
    // MARK: - Lookup

    /// Opus 4.6 is $5/$25. This previously asserted $15/$75 — the retired Opus 4/4.1 rate,
    /// which the old single "opus 4" row applied to the whole 4.x generation.
    @Test func pricing_opus4() {
        let pricing = ModelPricing.pricing(for: "claude-opus-4-6-20250929")
        #expect(pricing != nil)
        #expect(pricing?.inputPerMillion == 5)
        #expect(pricing?.outputPerMillion == 25)
    }

    @Test func pricing_sonnet4() {
        let pricing = ModelPricing.pricing(for: "claude-sonnet-4-5-20250929")
        #expect(pricing != nil)
        #expect(pricing?.inputPerMillion == 3)
    }

    /// Haiku 4.5 is $1/MTok. This previously asserted $0.80 — the Haiku 3.5 rate.
    @Test func pricing_haiku4() {
        let pricing = ModelPricing.pricing(for: "claude-haiku-4-5-20251001")
        #expect(pricing != nil)
        #expect(pricing?.inputPerMillion == 1)
        #expect(pricing?.outputPerMillion == 5)
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
        let model = ModelTokenSummary(id: "unknown", displayName: "Unknown", inputTokens: 1_000, outputTokens: 1_000, cacheReadTokens: 0, cacheWriteTokens: 0, estimatedCost: 0)
        #expect(ModelPricing.totalCost(for: [model]) == 0)
    }

    @Test func totalCost_mixedKnownAndUnknown() {
        let known = ModelTokenSummary(id: "claude-sonnet-4-5-20250929", displayName: "Sonnet 4.5", inputTokens: 1_000_000, outputTokens: 0, cacheReadTokens: 0, cacheWriteTokens: 0, estimatedCost: 3.0)
        let unknown = ModelTokenSummary(id: "unknown", displayName: "Unknown", inputTokens: 1_000_000, outputTokens: 1_000_000, cacheReadTokens: 0, cacheWriteTokens: 0, estimatedCost: 0)
        let total = ModelPricing.totalCost(for: [known, unknown])
        // Only Sonnet input: $3/M × 1M = $3
        #expect(abs(total - 3.0) < 0.001)
    }

    @Test func totalCost_multipleKnownModels() {
        let opus = ModelTokenSummary(id: "claude-opus-4-6-20250929", displayName: "Opus 4.6", inputTokens: 1_000_000, outputTokens: 0, cacheReadTokens: 0, cacheWriteTokens: 0, estimatedCost: 15.0)
        let sonnet = ModelTokenSummary(id: "claude-sonnet-4-5-20250929", displayName: "Sonnet 4.5", inputTokens: 1_000_000, outputTokens: 0, cacheReadTokens: 0, cacheWriteTokens: 0, estimatedCost: 3.0)
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
        #expect(abs(cost - 2_334.375) < 0.01)
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

    // MARK: - Compact cost format

    @Test func formatCompactCost_zero() {
        #expect(ModelPricing.formatCompactCost(0) == "$0")
    }

    @Test func formatCompactCost_subPenny() {
        #expect(ModelPricing.formatCompactCost(0.005) == "<$0.01")
    }

    @Test func formatCompactCost_cents() {
        #expect(ModelPricing.formatCompactCost(0.75) == "$0.75")
    }

    @Test func formatCompactCost_dollarDropsCents() {
        #expect(ModelPricing.formatCompactCost(12.34) == "$12")
    }

    @Test func formatCompactCost_largeDollar() {
        #expect(ModelPricing.formatCompactCost(150.99) == "$151")
    }

    // MARK: - Cache correctness

    @Test func pricing_unknownModel_cachedOnSecondCall() {
        // First call computes and caches nil
        let first = ModelPricing.pricing(for: "totally-fake-model-xyz-12345")
        #expect(first == nil)

        // Second call should hit the cache (not recompute) — still nil
        let second = ModelPricing.pricing(for: "totally-fake-model-xyz-12345")
        #expect(second == nil)
    }

    // MARK: - OpenAI (Codex) models

    @Test func pricing_gpt54() {
        let pricing = ModelPricing.pricing(for: "gpt-5.4")
        #expect(pricing?.inputPerMillion == 2.50)
        #expect(pricing?.outputPerMillion == 15.00)
        #expect(pricing?.cacheReadPerMillion == 0.25)
        #expect(pricing?.cacheWritePerMillion == 2.50) // no separate cache-write price → input rate
    }

    @Test func pricing_gpt56Sol_longestPrefixWins() {
        let pricing = ModelPricing.pricing(for: "gpt-5.6-sol")
        #expect(pricing?.inputPerMillion == 4.00)
        #expect(pricing?.outputPerMillion == 20.00)
    }

    @Test func pricing_gpt5Mini_notMatchedAsGpt5() {
        let pricing = ModelPricing.pricing(for: "gpt-5-mini")
        #expect(pricing?.inputPerMillion == 0.25)
        #expect(pricing?.outputPerMillion == 2.00)
    }

    @Test func pricing_gpt5Base() {
        let pricing = ModelPricing.pricing(for: "gpt-5")
        #expect(pricing?.inputPerMillion == 1.25)
        #expect(pricing?.outputPerMillion == 10.00)
    }

    @Test func pricing_gpt6Astra() {
        // Seen in real ~/.codex/sessions logs (1.5k turns); rates from the OpenAI pricing page 2026-09-21.
        let pricing = ModelPricing.pricing(for: "gpt-6-astra")
        #expect(pricing?.inputPerMillion == 10.00)
        #expect(pricing?.outputPerMillion == 50.00)
        #expect(pricing?.cacheReadPerMillion == 1.00)
    }

    @Test func pricing_unknownGPT_isNil() {
        #expect(ModelPricing.pricing(for: "gpt-3.5-turbo") == nil)
    }

    /// Verified against developers.openai.com/api/docs/pricing on 2026-09-29: the
    /// mini/nano variants of 5.4 must not fall through to the full 5.4 row, and the
    /// families an API key can reach (gpt-6 sol/luna, 4.1, 4o) are priced.
    @Test func openAITable_variantsAndOlderFamilies() throws {
        #expect(try #require(OpenAIModelPricing.pricing(for: "gpt-5.4-mini")).inputPerMillion == 0.75)
        #expect(try #require(OpenAIModelPricing.pricing(for: "gpt-5.4-nano-2026-08-01")).outputPerMillion == 1.25)
        #expect(try #require(OpenAIModelPricing.pricing(for: "gpt-5.4")).inputPerMillion == 2.50)
        #expect(try #require(OpenAIModelPricing.pricing(for: "gpt-6-sol")).inputPerMillion == 2.00)
        // gpt-6.1-sol has its own row: cached input is $0.10, not the gpt-6 family's $0.20.
        #expect(try #require(OpenAIModelPricing.pricing(for: "gpt-6.1-sol")).cacheReadPerMillion == 0.10)
        #expect(try #require(OpenAIModelPricing.pricing(for: "gpt-6-luna")).cacheReadPerMillion == 0.01)
        #expect(try #require(OpenAIModelPricing.pricing(for: "gpt-4.1-mini")).inputPerMillion == 0.40)
        #expect(try #require(OpenAIModelPricing.pricing(for: "gpt-4.1")).outputPerMillion == 8.00)
        #expect(try #require(OpenAIModelPricing.pricing(for: "gpt-4o-mini")).inputPerMillion == 0.15)
        #expect(try #require(OpenAIModelPricing.pricing(for: "gpt-4o-2024-11-20")).inputPerMillion == 2.50)
        #expect(OpenAIModelPricing.pricing(for: "gpt-3.5-turbo") == nil)
    }

    @Test func openAITable_isOrderedLongestPrefixFirst() {
        let prefixes = OpenAIModelPricing.table.map(\.prefix)
        for (i, prefix) in prefixes.enumerated() {
            for later in prefixes[(i + 1)...] {
                // An earlier, shorter prefix must never be a prefix of a later entry —
                // it would shadow the more specific row.
                #expect(!later.hasPrefix(prefix), "\(prefix) would shadow \(later)")
            }
        }
    }

    // MARK: - Claude 5 family

    /// Regression: the table stopped at the 4.x generation, so every Claude 5 model
    /// matched no row, `pricing(for:)` returned nil and its entire cost was reported as
    /// $0.00 — silently dropping the bulk of real usage out of Insights, per-project cost
    /// and the all-time total.
    @Test func claudeFive_familyIsPriced() throws {
        #expect(try #require(ModelPricing.pricing(for: "claude-opus-5")).inputPerMillion == 5)
        #expect(try #require(ModelPricing.pricing(for: "claude-opus-5")).outputPerMillion == 25)
        #expect(try #require(ModelPricing.pricing(for: "claude-sonnet-5")).inputPerMillion == 2)
        #expect(try #require(ModelPricing.pricing(for: "claude-sonnet-5")).outputPerMillion == 10)
        #expect(try #require(ModelPricing.pricing(for: "claude-fable-5-1")).inputPerMillion == 10)
        #expect(try #require(ModelPricing.pricing(for: "claude-fable-5-1")).outputPerMillion == 50)
        #expect(try #require(ModelPricing.pricing(for: "claude-haiku-4-5")).inputPerMillion == 1)
        #expect(try #require(ModelPricing.pricing(for: "claude-haiku-4-5")).outputPerMillion == 5)
    }

    /// `contains` matching means a shorter key would swallow a more specific one, and the
    /// two differ in price: Opus 5.5 is $4/$20 against Opus 5's $5/$25, and Fable 5.1 reads
    /// cache at $0.25 against Fable 5's $1.00.
    @Test func claudeTable_minorVersionsAreNotShadowed() throws {
        #expect(try #require(ModelPricing.pricing(for: "claude-opus-5-5")).inputPerMillion == 4)
        #expect(try #require(ModelPricing.pricing(for: "claude-opus-5-5")).outputPerMillion == 20)
        #expect(try #require(ModelPricing.pricing(for: "claude-fable-5")).cacheReadPerMillion == 1.00)
        #expect(try #require(ModelPricing.pricing(for: "claude-fable-5-1")).cacheReadPerMillion == 0.25)
        #expect(try #require(ModelPricing.pricing(for: "claude-sonnet-5")).cacheReadPerMillion == 0.20)
        #expect(try #require(ModelPricing.pricing(for: "claude-sonnet-5-5")).cacheReadPerMillion == 0.10)
    }

    /// Opus 4.5-4.8 are $5/$25, not the retired Opus 4/4.1 rate of $15/$75. The old single
    /// "opus 4" row billed Opus 4.7 usage at 3x its real cost.
    @Test func opusFourPointX_usesCurrentRateNotRetiredRate() throws {
        for id in ["claude-opus-4-5", "claude-opus-4-6", "claude-opus-4-7", "claude-opus-4-8"] {
            let pricing = try #require(ModelPricing.pricing(for: id))
            #expect(pricing.inputPerMillion == 5, "\(id) input")
            #expect(pricing.outputPerMillion == 25, "\(id) output")
        }
        // The retired generation keeps its own (higher) published rate.
        #expect(try #require(ModelPricing.pricing(for: "claude-3-opus-20240229")).inputPerMillion == 15)
    }

    /// The ordering test compares table keys only, so it cannot catch a key that swallows a
    /// display name with no row of its own. Drive real model ids through `pricing(for:)` for
    /// the two families the Opus test does not cover.
    @Test func sonnetAndHaikuMinors_resolveToTheirOwnPublishedRates() throws {
        let expected: [(id: String, input: Double, output: Double)] = [
            ("claude-sonnet-3-20240229", 3, 15),
            ("claude-3-5-sonnet-20241022", 3, 15),
            ("claude-sonnet-3-7-20250219", 3, 15),
            ("claude-sonnet-4-20250514", 3, 15),
            ("claude-sonnet-4-5-20250929", 3, 15),
            ("claude-sonnet-5", 2, 10),
            ("claude-sonnet-5-5", 2, 10),
            ("claude-3-haiku-20240307", 0.25, 1.25),
            ("claude-3-5-haiku-20241022", 0.80, 4),
            ("claude-haiku-4-5-20251001", 1, 5),
            ("claude-haiku-5-5", 0.10, 0.50),
        ]
        for case let (id, input, output) in expected {
            let pricing = try #require(ModelPricing.pricing(for: id), "\(id) must have a price")
            #expect(pricing.inputPerMillion == input, "\(id) input")
            #expect(pricing.outputPerMillion == output, "\(id) output")
        }
    }

    /// Claude 3 Haiku is retired and billed at the Haiku family rate ($1/$5) until it got
    /// its own row — 4x its real cost on the oldest history anyone still has.
    @Test func claudeThreeHaiku_usesItsOwnRetiredRate() throws {
        let pricing = try #require(ModelPricing.pricing(for: "claude-3-haiku-20240307"))
        #expect(pricing.inputPerMillion == 0.25)
        #expect(pricing.outputPerMillion == 1.25)
        #expect(pricing.cacheWritePerMillion == 0.30)
        #expect(pricing.cacheReadPerMillion == 0.03)
        // Haiku 3.5 keeps its own, different rate — the two must not collapse together.
        #expect(try #require(ModelPricing.pricing(for: "claude-3-5-haiku-20241022")).inputPerMillion == 0.80)
    }

    /// A Claude model released after this table was last updated must still cost something —
    /// returning nil here is what produced the $0.00 bug in the first place.
    @Test func unknownMinorVersion_fallsBackToFamilyRate() throws {
        #expect(try #require(ModelPricing.pricing(for: "claude-opus-7-3")).inputPerMillion == 5)
        #expect(try #require(ModelPricing.pricing(for: "claude-sonnet-9")).inputPerMillion == 2)
        #expect(try #require(ModelPricing.pricing(for: "claude-haiku-9")).inputPerMillion == 1)
        // A genuinely unrecognisable id still has no price rather than a made-up one.
        #expect(ModelPricing.pricing(for: "some-other-vendor-model") == nil)
    }

    /// The ordering invariant the `contains` scan depends on, asserted structurally so a
    /// future row inserted in the wrong place fails here rather than silently mispricing.
    @Test func claudeTable_specificKeysPrecedeTheKeysThatWouldSwallowThem() {
        let keys = ModelPricing.tableKeys
        for (i, key) in keys.enumerated() {
            for later in keys[(i + 1)...] {
                #expect(!later.contains(key), "\(key) would shadow \(later)")
            }
        }
    }
}

import Testing
@testable import AIBatteryCore

@Suite("ModelTokenSummary")
struct ModelTokenSummaryTests {
    @Test func totalTokens_allComponents() {
        let summary = ModelTokenSummary(
            id: "claude-opus-4-6",
            displayName: "Opus 4.6",
            inputTokens: 1_000,
            outputTokens: 500,
            cacheReadTokens: 200,
            cacheWriteTokens: 100,
            estimatedCost: 0
        )
        #expect(summary.totalTokens == 1_800)
    }

    @Test func totalTokens_zeroAll() {
        let summary = ModelTokenSummary(
            id: "model",
            displayName: "Model",
            inputTokens: 0,
            outputTokens: 0,
            cacheReadTokens: 0,
            cacheWriteTokens: 0,
            estimatedCost: 0
        )
        #expect(summary.totalTokens == 0)
    }

    @Test func totalTokens_onlyInput() {
        let summary = ModelTokenSummary(
            id: "model",
            displayName: "Model",
            inputTokens: 5_000,
            outputTokens: 0,
            cacheReadTokens: 0,
            cacheWriteTokens: 0,
            estimatedCost: 0
        )
        #expect(summary.totalTokens == 5_000)
    }

    @Test func id_matchesModelId() {
        let summary = ModelTokenSummary(
            id: "claude-sonnet-4-5-20250929",
            displayName: "Sonnet 4.5",
            inputTokens: 0,
            outputTokens: 0,
            cacheReadTokens: 0,
            cacheWriteTokens: 0,
            estimatedCost: 0
        )
        #expect(summary.id == "claude-sonnet-4-5-20250929")
    }
}

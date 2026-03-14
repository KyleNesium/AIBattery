import Testing
@testable import AIBatteryCore

@Suite("ProjectTokenSummary")
struct ProjectTokenSummaryTests {

    @Test func totalTokens_sumsAllTypes() {
        let summary = ProjectTokenSummary(
            id: "test",
            projectName: "test",
            inputTokens: 100,
            outputTokens: 200,
            cacheReadTokens: 300,
            cacheWriteTokens: 400,
            estimatedCost: 0.50
        )
        #expect(summary.totalTokens == 1000)
    }
}

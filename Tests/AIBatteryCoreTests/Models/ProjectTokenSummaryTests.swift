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

    @Test func totalTokens_zeroWhenAllZero() {
        let summary = ProjectTokenSummary(
            id: "/workspace/empty",
            projectName: "empty",
            inputTokens: 0,
            outputTokens: 0,
            cacheReadTokens: 0,
            cacheWriteTokens: 0,
            estimatedCost: 0
        )
        #expect(summary.totalTokens == 0)
    }

    @Test func id_isUsedAsIdentifiable() {
        let summary = ProjectTokenSummary(
            id: "/Users/kyle/projects/myapp",
            projectName: "myapp",
            inputTokens: 500,
            outputTokens: 250,
            cacheReadTokens: 0,
            cacheWriteTokens: 0,
            estimatedCost: 1.50
        )
        #expect(summary.id == "/Users/kyle/projects/myapp")
    }

    @Test func projectName_displaysLastPathComponent() {
        // Simulates what UsageAggregator.buildProjectTokens does
        let cwd = "/Users/kyle/projects/my-app"
        let displayName = URL(fileURLWithPath: cwd).lastPathComponent
        let summary = ProjectTokenSummary(
            id: cwd,
            projectName: displayName,
            inputTokens: 100,
            outputTokens: 50,
            cacheReadTokens: 0,
            cacheWriteTokens: 0,
            estimatedCost: 0.30
        )
        #expect(summary.projectName == "my-app")
    }

    @Test func otherProject_usedForMissingCwd() {
        let summary = ProjectTokenSummary(
            id: "Other",
            projectName: "Other",
            inputTokens: 100,
            outputTokens: 50,
            cacheReadTokens: 0,
            cacheWriteTokens: 0,
            estimatedCost: 0.10
        )
        #expect(summary.id == "Other")
        #expect(summary.projectName == "Other")
        #expect(summary.totalTokens == 150)
    }

    @Test func estimatedCost_storedDirectly() {
        let summary = ProjectTokenSummary(
            id: "test",
            projectName: "test",
            inputTokens: 1_000_000,
            outputTokens: 500_000,
            cacheReadTokens: 2_000_000,
            cacheWriteTokens: 100_000,
            estimatedCost: 18.75
        )
        #expect(summary.estimatedCost == 18.75)
        #expect(summary.totalTokens == 3_600_000)
    }

    @Test func largeTokenCounts_noOverflow() {
        let summary = ProjectTokenSummary(
            id: "large",
            projectName: "large",
            inputTokens: 500_000_000,
            outputTokens: 200_000_000,
            cacheReadTokens: 800_000_000,
            cacheWriteTokens: 100_000_000,
            estimatedCost: 5000.0
        )
        #expect(summary.totalTokens == 1_600_000_000)
    }
}

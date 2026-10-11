import Testing
@testable import AIBatteryCore

@Suite("RateLimitSource codex")
struct RateLimitSourceCodexTests {
    @Test func codexCasesHaveLabels() {
        #expect(RateLimitSource.codexUsageEndpoint.shortLabel == "Via OpenAI API")
        #expect(RateLimitSource.codexSessionLog.shortLabel == "Via Codex CLI")
        #expect(!RateLimitSource.codexUsageEndpoint.explanation.isEmpty)
        #expect(!RateLimitSource.codexSessionLog.explanation.isEmpty)
    }
}

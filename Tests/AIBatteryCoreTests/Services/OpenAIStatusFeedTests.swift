import Foundation
import Testing
@testable import AIBatteryCore

@Suite("OpenAI status feed")
struct OpenAIStatusFeedTests {
    @Test func codexFeed_pointsAtOpenAIStatuspage() {
        let config = StatusFeedConfig.codex
        #expect(config.summaryURL.absoluteString == "https://status.openai.com/api/v2/summary.json")
        #expect(config.statusPageBaseURL == "https://status.openai.com")
    }

    @Test func codexFeed_tracksFiveCodexComponents_andFiltersToThem() throws {
        let config = StatusFeedConfig.codex
        #expect(config.knownComponents.count == 5)
        #expect(Set(config.knownComponents.map(\.id)).count == 5)
        #expect(Set(config.knownComponents.map(\.alertKey)).count == 5)
        #expect(config.knownComponents.allSatisfy { $0.alertKey.hasPrefix("codex") })
        let filter = try #require(config.componentFilter)
        #expect(filter == Set(config.knownComponents.map(\.id)))
    }

    @Test func codexFeed_alertKeys_doNotCollideWithClaude() {
        let claudeKeys = Set(StatusFeedConfig.claude.knownComponents.map(\.alertKey))
        let codexKeys = Set(StatusFeedConfig.codex.knownComponents.map(\.alertKey))
        #expect(claudeKeys.isDisjoint(with: codexKeys))
    }
}

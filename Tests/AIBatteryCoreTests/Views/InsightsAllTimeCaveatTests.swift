import Testing
@testable import AIBatteryCore

@Suite("InsightsView — All Time caveat")
struct InsightsAllTimeCaveatTests {
    @Test func claude_tooltipIsLifetime() {
        #expect(InsightsView.allTimeTooltip(for: .claude) == "Cumulative tokens across all sessions")
    }

    @Test func codex_tooltipStatesLogRetentionBound() {
        let text = InsightsView.allTimeTooltip(for: .codex)
        #expect(text.contains("session logs"))
        #expect(text.contains("retention"))
    }
}

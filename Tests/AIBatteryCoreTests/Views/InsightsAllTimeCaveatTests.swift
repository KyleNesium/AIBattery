import Testing
@testable import AIBatteryCore

@Suite("InsightsView — All Time caveat")
struct InsightsAllTimeCaveatTests {
    @Test func claude_tooltipIsLifetime() {
        #expect(InsightsView.allTimeTooltip(for: .claude) == "Cumulative tokens across all sessions")
    }

    /// Codex totals come from scanned session logs kept as a ledger high-water mark —
    /// nothing before the first scan, nothing lost to rotation after it. The copy must
    /// say both halves (it used to claim "bounded by log retention", which the ledger
    /// contradicted).
    @Test func codex_tooltipStatesFirstScanBoundAndRotationSafety() {
        let text = InsightsView.allTimeTooltip(for: .codex)
        #expect(text.contains("session logs"))
        #expect(text.contains("first scanned"))
        #expect(text.contains("log rotation"))
        #expect(!text.contains("bounded by log retention"))
    }
}

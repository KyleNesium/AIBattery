import Testing
import Foundation
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

    @Test func codex_withSince_appendsDate() {
        let since = Date(timeIntervalSince1970: 1_789_000_000)
        let text = InsightsView.allTimeTooltip(for: .codex, since: since)
        #expect(text.hasPrefix("Cumulative tokens from Codex session logs"))
        #expect(text.contains("since "))
    }

    @Test func claude_ignoresSince() {
        #expect(InsightsView.allTimeTooltip(for: .claude, since: Date()) == "Cumulative tokens across all sessions")
    }

    @Test func chartCaption_onlyForCodexWithinTwelveMonths() {
        let now = Date(timeIntervalSince1970: 1_789_000_000)
        #expect(InsightsView.sinceCaption(provider: .codex, since: now.addingTimeInterval(-30 * 86_400), unattributed: 0, now: now)?.hasPrefix("since ") == true)
        #expect(InsightsView.sinceCaption(provider: .codex, since: now.addingTimeInterval(-400 * 86_400), unattributed: 0, now: now) == nil)
        #expect(InsightsView.sinceCaption(provider: .claude, since: now, unattributed: 0, now: now) == nil)
        #expect(InsightsView.sinceCaption(provider: .codex, since: nil, unattributed: 0, now: now) == nil)
    }

    @Test func codex_tooltipAppendsHiddenTurnCount() {
        let text = InsightsView.allTimeTooltip(for: .codex, since: nil, unattributed: 902)
        #expect(text.hasSuffix(" · 902 turns from older Codex CLI versions not shown"))
        #expect(!InsightsView.allTimeTooltip(for: .codex, since: nil, unattributed: 0).contains("not shown"))
        #expect(!InsightsView.allTimeTooltip(for: .claude, since: nil, unattributed: 5).contains("not shown"))
    }

    @Test func caption_combinesSinceAndHiddenCount_inEveryMode() {
        let now = Date(timeIntervalSince1970: 1_789_000_000)
        let since = now.addingTimeInterval(-30 * 86_400)
        let both = InsightsView.sinceCaption(provider: .codex, since: since, unattributed: 3, now: now)
        #expect(both?.hasPrefix("since ") == true)
        #expect(both?.hasSuffix(" · 3 turns from older Codex CLI versions not shown") == true)
        #expect(InsightsView.sinceCaption(provider: .codex, since: nil, unattributed: 1, now: now) == "1 turn from older Codex CLI versions not shown")
        #expect(InsightsView.sinceCaption(provider: .codex, since: nil, unattributed: 0, now: now) == nil)
        #expect(InsightsView.sinceCaption(provider: .claude, since: since, unattributed: 9, now: now) == nil)
    }
}

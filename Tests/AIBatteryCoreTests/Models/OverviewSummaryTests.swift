import Foundation
import Testing
@testable import AIBatteryCore

@Suite("OverviewSummary")
struct OverviewSummaryTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func card(
        _ id: String, _ provider: AIProvider, identity: String,
        state: AccountCard.State = .none, reset: Date? = nil
    ) -> AccountCard {
        AccountCard(
            id: id, provider: provider, identity: identity, plan: nil, isActive: false,
            status: nil, worstPercent: 10, bars: [], state: state, reset: reset, tokensToday: nil
        )
    }

    @Test func text_leadsWithTroubleOverVolume() {
        let cards = [
            card("c1", .claude, identity: "Claude Team", state: .throttled),
            card("x1", .codex, identity: "Work"),
        ]
        let summary = OverviewSummary.make(cards: cards, snapshots: [
            .claude: UsageSnapshotFactory.make(todayTokens: 100),
        ])
        #expect(summary.isAlarm)
        #expect(summary.text(now: now) == "Claude Team needs attention")
    }

    @Test func text_countsSeveralTroubledAccounts() {
        let cards = [
            card("c1", .claude, identity: "A", state: .throttled),
            card("c2", .claude, identity: "B", state: .limitReached),
        ]
        #expect(OverviewSummary.make(cards: cards, snapshots: [:]).text(now: now) == "2 accounts need attention")
    }

    @Test func text_sumsTodayPerProvider_notPerCard() {
        // Two Claude accounts share one set of session logs: counting per card would
        // report the same tokens twice.
        let cards = [
            card("c1", .claude, identity: "A"),
            card("c2", .claude, identity: "B"),
            card("x1", .codex, identity: "C"),
        ]
        let summary = OverviewSummary.make(cards: cards, snapshots: [
            .claude: UsageSnapshotFactory.make(todayTokens: 100, provider: .claude),
            .codex: UsageSnapshotFactory.make(todayTokens: 50, provider: .codex),
        ])
        #expect(summary.tokensToday == 150)
        #expect(summary.text(now: now)?.contains("150 today") == true)
    }

    @Test func text_includesTheSoonestReset() {
        let cards = [
            card("c1", .claude, identity: "A", reset: now.addingTimeInterval(7_200)),
            card("x1", .codex, identity: "B", reset: now.addingTimeInterval(600)),
        ]
        let summary = OverviewSummary.make(cards: cards, snapshots: [:])
        #expect(summary.nextReset == now.addingTimeInterval(600))
        #expect(summary.text(now: now)?.hasPrefix("next reset in") == true)
    }

    @Test func text_isNilWithNothingToSay() {
        let summary = OverviewSummary.make(cards: [card("c1", .claude, identity: "A")], snapshots: [:])
        #expect(summary.text(now: now) == nil)
        #expect(summary.isAlarm == false)
    }

    @Test func text_ignoresAProviderThatHasNotAggregatedYet() {
        let cards = [card("c1", .claude, identity: "A"), card("x1", .codex, identity: "B")]
        let summary = OverviewSummary.make(cards: cards, snapshots: [
            .claude: UsageSnapshotFactory.make(todayTokens: 100),
        ])
        #expect(summary.tokensToday == 100)
    }
}

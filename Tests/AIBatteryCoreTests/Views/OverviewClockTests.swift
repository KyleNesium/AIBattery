import Foundation
import Testing
@testable import AIBatteryCore

/// B10: the overview runs ONE clock (`OverviewContentView`'s `TimelineView`) and hands
/// its date to every card. Everything on a card that reads the clock must be a pure
/// function of that injected `now`, so one tick redraws exactly the two lines that
/// depend on it and nothing on a card reads `Date()` for itself.
@Suite("Overview cards share one clock")
struct OverviewClockTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func card(resetIn: TimeInterval) -> AccountCard {
        let rl = RateLimitUsage(
            representativeClaim: RateLimitUsage.fiveHourWindow,
            fiveHourUtilization: 0.4, fiveHourReset: now.addingTimeInterval(resetIn),
            fiveHourStatus: "allowed",
            sevenDayUtilization: 0.1, sevenDayReset: now.addingTimeInterval(resetIn * 24),
            sevenDayStatus: "allowed",
            overallStatus: "allowed",
            provider: .claude
        )
        let reading = AccountReading(windows: rl, apiLimits: nil, fetchedAt: now, isCached: false, source: nil)
        let account = AccountRecord(id: "c1", displayName: nil, billingType: nil, addedAt: now, provider: .claude, codexAccessMode: nil)
        return AccountCard.rows(
            accounts: [account],
            readings: ["c1": reading], statuses: [:],
            isAuthenticated: { _ in true }, maskEmail: true
        )[0]
    }

    @Test("one ticker, every 10 seconds")
    func clockInterval() {
        #expect(OverviewContentView.clockInterval == 10)
    }

    @Test("the state line is a function of the injected clock, not of Date()")
    func stateLineFollowsInjectedNow() {
        let card = card(resetIn: 2 * 3_600)
        let atStart = AccountCard.stateLine(card, now: now)
        let anHourLater = AccountCard.stateLine(card, now: now.addingTimeInterval(3_600))
        #expect(atStart?.hasPrefix("Resets in") == true)
        #expect(atStart != anHourLater)
        #expect(anHourLater?.contains("1h") == true)
    }

    @Test("the live dot follows the injected clock: live now, gone once the window passes")
    func liveDotFollowsInjectedNow() {
        let activity = now.addingTimeInterval(-60)
        #expect(AccountCard.isLive(lastActivity: activity, now: now))
        #expect(!AccountCard.isLive(lastActivity: activity, now: now.addingTimeInterval(AccountCard.liveActivityWindow)))
    }
}

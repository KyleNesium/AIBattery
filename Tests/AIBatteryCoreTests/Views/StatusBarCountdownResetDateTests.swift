import Testing
import Foundation
@testable import AIBatteryCore

/// Pre-landing-review regression coverage for `StatusBarManager.countdownResetDate` —
/// specifically the bug where two exhausted windows had their earliest reset chosen
/// via `min()` *before* past dates were filtered, so once the 5-hour reset fired the
/// still-valid 7-day countdown was dropped in favour of a stuck `"100%"`.
@Suite("StatusBarManager.countdownResetDate")
struct StatusBarCountdownResetDateTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeRateLimits(
        fiveHourUtilization: Double,
        fiveHourReset: Date?,
        fiveHourStatus: String = "allowed",
        sevenDayUtilization: Double,
        sevenDayReset: Date?,
        sevenDayStatus: String = "allowed",
        overallStatus: String = "allowed",
        representativeClaim: String = "five_hour"
    ) -> RateLimitUsage {
        RateLimitUsage(
            representativeClaim: representativeClaim,
            fiveHourUtilization: fiveHourUtilization,
            fiveHourReset: fiveHourReset,
            fiveHourStatus: fiveHourStatus,
            sevenDayUtilization: sevenDayUtilization,
            sevenDayReset: sevenDayReset,
            sevenDayStatus: sevenDayStatus,
            overallStatus: overallStatus
        )
    }

    // MARK: - Neither window exhausted

    @Test func neitherExhausted_returnsNil() {
        let rl = makeRateLimits(
            fiveHourUtilization: 0.5, fiveHourReset: now.addingTimeInterval(3_600),
            sevenDayUtilization: 0.2, sevenDayReset: now.addingTimeInterval(86_400)
        )
        #expect(StatusBarManager.countdownResetDate(for: rl, now: now) == nil)
    }

    // MARK: - Single-window exhaustion

    @Test func fiveHourExhausted_returnsFiveHourReset() {
        let reset = now.addingTimeInterval(1_800)
        let rl = makeRateLimits(
            fiveHourUtilization: 1.0, fiveHourReset: reset,
            sevenDayUtilization: 0.2, sevenDayReset: now.addingTimeInterval(86_400)
        )
        #expect(StatusBarManager.countdownResetDate(for: rl, now: now) == reset)
    }

    @Test func sevenDayExhausted_returnsSevenDayReset() {
        let reset = now.addingTimeInterval(86_400)
        let rl = makeRateLimits(
            fiveHourUtilization: 0.5, fiveHourReset: now.addingTimeInterval(1_800),
            sevenDayUtilization: 1.0, sevenDayReset: reset
        )
        #expect(StatusBarManager.countdownResetDate(for: rl, now: now) == reset)
    }

    @Test func fiveHourExhausted_pastReset_returnsNil() {
        let rl = makeRateLimits(
            fiveHourUtilization: 1.0, fiveHourReset: now.addingTimeInterval(-60),
            sevenDayUtilization: 0.2, sevenDayReset: now.addingTimeInterval(86_400)
        )
        #expect(StatusBarManager.countdownResetDate(for: rl, now: now) == nil)
    }

    // MARK: - Dual exhaustion (the regression)

    @Test func bothExhausted_fiveHourPast_sevenDayFuture_handsOffToSevenDay() {
        // The regression: once the 5-hour reset fires, the old code picked `min(past5h, future7d)`
        // which was the past date, then filtered it out to nil and dropped to "100%" —
        // instead of continuing with the still-valid 7-day countdown.
        let sevenDay = now.addingTimeInterval(86_400)
        let rl = makeRateLimits(
            fiveHourUtilization: 1.0, fiveHourReset: now.addingTimeInterval(-60),
            sevenDayUtilization: 1.0, sevenDayReset: sevenDay
        )
        #expect(StatusBarManager.countdownResetDate(for: rl, now: now) == sevenDay)
    }

    @Test func bothExhausted_bothFuture_returnsEarlierReset() {
        let five = now.addingTimeInterval(1_800)
        let seven = now.addingTimeInterval(86_400)
        let rl = makeRateLimits(
            fiveHourUtilization: 1.0, fiveHourReset: five,
            sevenDayUtilization: 1.0, sevenDayReset: seven
        )
        #expect(StatusBarManager.countdownResetDate(for: rl, now: now) == five)
    }

    @Test func bothExhausted_bothPast_returnsNil() {
        let rl = makeRateLimits(
            fiveHourUtilization: 1.0, fiveHourReset: now.addingTimeInterval(-60),
            sevenDayUtilization: 1.0, sevenDayReset: now.addingTimeInterval(-120)
        )
        #expect(StatusBarManager.countdownResetDate(for: rl, now: now) == nil)
    }

    @Test func bothExhausted_bothNil_returnsNil() {
        let rl = makeRateLimits(
            fiveHourUtilization: 1.0, fiveHourReset: nil,
            sevenDayUtilization: 1.0, sevenDayReset: nil
        )
        #expect(StatusBarManager.countdownResetDate(for: rl, now: now) == nil)
    }

    // MARK: - Throttled

    @Test func throttled_futureBindingReset_returnsBindingReset() {
        let reset = now.addingTimeInterval(1_800)
        let rl = makeRateLimits(
            fiveHourUtilization: 1.0, fiveHourReset: reset, fiveHourStatus: "throttled",
            sevenDayUtilization: 0.5, sevenDayReset: now.addingTimeInterval(86_400),
            overallStatus: "throttled",
            representativeClaim: "five_hour"
        )
        #expect(StatusBarManager.countdownResetDate(for: rl, now: now) == reset)
    }

    @Test func throttled_pastBindingReset_returnsNil() {
        // The binding reset has already fired but the throttled flag is still set — don't
        // show a stuck countdown to a past date.
        let rl = makeRateLimits(
            fiveHourUtilization: 1.0, fiveHourReset: now.addingTimeInterval(-60), fiveHourStatus: "throttled",
            sevenDayUtilization: 0.5, sevenDayReset: now.addingTimeInterval(86_400),
            overallStatus: "throttled",
            representativeClaim: "five_hour"
        )
        #expect(StatusBarManager.countdownResetDate(for: rl, now: now) == nil)
    }

    @Test func throttled_nilBindingReset_returnsNil() {
        let rl = makeRateLimits(
            fiveHourUtilization: 1.0, fiveHourReset: nil, fiveHourStatus: "throttled",
            sevenDayUtilization: 0.5, sevenDayReset: now.addingTimeInterval(86_400),
            overallStatus: "throttled",
            representativeClaim: "five_hour"
        )
        #expect(StatusBarManager.countdownResetDate(for: rl, now: now) == nil)
    }
}

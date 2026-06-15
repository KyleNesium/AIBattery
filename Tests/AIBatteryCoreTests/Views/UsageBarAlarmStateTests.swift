import Testing
@testable import AIBatteryCore

/// `UsageBar.AlarmState` gates the throttle / "Limit reached" alarm on confirmed
/// (fresh) data. A stale percentage is fine to show; a stale alarm is a false alarm —
/// the same guarantee the menu bar already enforces via `confirmed`. These pin the
/// fix for the v2.5.0 popover bug where cached data rendered "7-Day 100% Limit reached".
@Suite("UsageBar.AlarmState")
@MainActor
struct UsageBarAlarmStateTests {
    // MARK: - Confirmed data behaves exactly as before

    @Test func confirmedThrottle_clampsTo100AndShowsAlarm() {
        let s = UsageBar.AlarmState(percent: 90, isThrottled: true, confirmed: true)
        #expect(s.throttled == true)
        #expect(s.displayPercent == 100) // clamped so UI never shows "90% Throttled"
        #expect(s.limitReached == false) // "Throttled" wins over "Limit reached"
        #expect(s.wasExhausted == true)
    }

    @Test func confirmedAt100_notThrottled_showsLimitReached() {
        let s = UsageBar.AlarmState(percent: 100, isThrottled: false, confirmed: true)
        #expect(s.throttled == false)
        #expect(s.limitReached == true)
        #expect(s.displayPercent == 100)
        #expect(s.wasExhausted == true)
    }

    @Test func confirmedHealthy_noAlarm() {
        let s = UsageBar.AlarmState(percent: 9, isThrottled: false, confirmed: true)
        #expect(s.throttled == false)
        #expect(s.limitReached == false)
        #expect(s.displayPercent == 9)
        #expect(s.wasExhausted == false)
    }

    // MARK: - Unconfirmed (cached) data suppresses the alarm — the bug fix

    @Test func unconfirmedThrottle_suppressesAlarm_showsRealPercent() {
        // The reported bug: cached 7-day reading at 100% + throttled rendered
        // "Limit reached". Unconfirmed → no alarm, no fabricated 100%.
        let s = UsageBar.AlarmState(percent: 100, isThrottled: true, confirmed: false)
        #expect(s.throttled == false)
        #expect(s.limitReached == false)
        #expect(s.displayPercent == 100) // stale number is still shown — just no alarm
    }

    @Test func unconfirmedThrottleBelow100_noClampNoAlarm() {
        let s = UsageBar.AlarmState(percent: 73, isThrottled: true, confirmed: false)
        #expect(s.throttled == false)
        #expect(s.limitReached == false)
        #expect(s.displayPercent == 73) // not clamped to 100 on unconfirmed data
    }

    @Test func unconfirmedAt100_notThrottled_noLimitReached() {
        let s = UsageBar.AlarmState(percent: 100, isThrottled: false, confirmed: false)
        #expect(s.limitReached == false)
        #expect(s.throttled == false)
        #expect(s.displayPercent == 100)
    }
}

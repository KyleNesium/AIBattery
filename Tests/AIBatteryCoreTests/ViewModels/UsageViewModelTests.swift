import Testing
import Foundation
@testable import AIBatteryCore

@Suite("UsageViewModel")
@MainActor
struct UsageViewModelTests {

    // MARK: - clampedRefreshInterval

    @Test func clampedRefreshInterval_zero_returnsDefault() {
        #expect(UsageViewModel.clampedRefreshInterval(0) == 60)
    }

    @Test func clampedRefreshInterval_negative_returnsDefault() {
        #expect(UsageViewModel.clampedRefreshInterval(-10) == 60)
    }

    @Test func clampedRefreshInterval_belowMin_clampsToMin() {
        #expect(UsageViewModel.clampedRefreshInterval(5) == 10)
    }

    @Test func clampedRefreshInterval_aboveMax_clampsToMax() {
        #expect(UsageViewModel.clampedRefreshInterval(120) == 60)
    }

    @Test func clampedRefreshInterval_inRange_returnsAsIs() {
        #expect(UsageViewModel.clampedRefreshInterval(30) == 30)
    }

    @Test func clampedRefreshInterval_exactMin_returnsMin() {
        #expect(UsageViewModel.clampedRefreshInterval(10) == 10)
    }

    @Test func clampedRefreshInterval_exactMax_returnsMax() {
        #expect(UsageViewModel.clampedRefreshInterval(60) == 60)
    }

    // MARK: - refreshErrorMessage

    @Test func refreshErrorMessage_noDataNoMessages_returnsNoUsage() {
        let msg = UsageViewModel.refreshErrorMessage(
            hasRateLimits: false,
            hasProfile: false,
            hasStandardRateLimitHeaders: false,
            totalMessages: 0
        )
        #expect(msg == "No usage data yet. Start a Claude Code session to see your stats.")
    }

    @Test func refreshErrorMessage_noDataWithMessages_returnsAPIError() {
        let msg = UsageViewModel.refreshErrorMessage(
            hasRateLimits: false,
            hasProfile: false,
            hasStandardRateLimitHeaders: false,
            totalMessages: 50
        )
        #expect(msg == "Unable to reach Anthropic API. Check your internet connection and try again.")
    }

    @Test func refreshErrorMessage_hasRateLimits_returnsNil() {
        let msg = UsageViewModel.refreshErrorMessage(
            hasRateLimits: true,
            hasProfile: false,
            hasStandardRateLimitHeaders: false,
            totalMessages: 0
        )
        #expect(msg == nil)
    }

    @Test func refreshErrorMessage_hasProfileOnly_returnsHeadersUnavailable() {
        let msg = UsageViewModel.refreshErrorMessage(
            hasRateLimits: false,
            hasProfile: true,
            hasStandardRateLimitHeaders: false,
            totalMessages: 0
        )
        #expect(msg != nil)
        #expect(msg!.contains("Claude Code usage unavailable"))
    }

    @Test func refreshErrorMessage_publicAPIHeadersOnly_returnsSpecificMessage() {
        let msg = UsageViewModel.refreshErrorMessage(
            hasRateLimits: false,
            hasProfile: true,
            hasStandardRateLimitHeaders: true,
            totalMessages: 0
        )
        #expect(msg == "Public API rate-limit headers are available, but Claude Code 5-hour / 7-day usage is unavailable.")
    }

    @Test func refreshErrorMessage_hasBothData_returnsNil() {
        let msg = UsageViewModel.refreshErrorMessage(
            hasRateLimits: true,
            hasProfile: true,
            hasStandardRateLimitHeaders: true,
            totalMessages: 100
        )
        #expect(msg == nil)
    }

    @Test func refreshErrorMessage_profileAndMessages_stillReturnsClaudeCodeWarning() {
        let msg = UsageViewModel.refreshErrorMessage(
            hasRateLimits: false,
            hasProfile: true,
            hasStandardRateLimitHeaders: false,
            totalMessages: 100
        )
        #expect(msg == "Claude Code usage unavailable. Anthropic may have changed the API response format.")
    }

    // MARK: - hasDataChanged

    @Test func hasDataChanged_firstLoad_returnsTrue() {
        #expect(UsageViewModel.hasDataChanged(previousTotal: -1, previousToday: -1, newTotal: 0, newToday: 0))
    }

    @Test func hasDataChanged_totalChanged_returnsTrue() {
        #expect(UsageViewModel.hasDataChanged(previousTotal: 10, previousToday: 5, newTotal: 11, newToday: 5))
    }

    @Test func hasDataChanged_todayChanged_returnsTrue() {
        #expect(UsageViewModel.hasDataChanged(previousTotal: 10, previousToday: 5, newTotal: 10, newToday: 6))
    }

    @Test func hasDataChanged_unchanged_returnsFalse() {
        #expect(!UsageViewModel.hasDataChanged(previousTotal: 10, previousToday: 5, newTotal: 10, newToday: 5))
    }

    @Test func hasDataChanged_bothChanged_returnsTrue() {
        #expect(UsageViewModel.hasDataChanged(previousTotal: 10, previousToday: 5, newTotal: 20, newToday: 15))
    }

    // MARK: - recordThrottleEvent

    @Test func recordThrottleEvent_nilRateLimits_noOp() {
        let key = UserDefaultsKeys.throttleTimestamps
        UserDefaults.standard.removeObject(forKey: key)
        // Reset transition state
        UsageViewModel.recordThrottleEvent(nil)
        UsageViewModel.recordThrottleEvent(nil)
        let timestamps = UserDefaults.standard.array(forKey: key) as? [Double] ?? []
        #expect(timestamps.isEmpty)
    }

    @Test func recordThrottleEvent_notThrottled_noOp() {
        let key = UserDefaultsKeys.throttleTimestamps
        UserDefaults.standard.removeObject(forKey: key)
        let rl = RateLimitUsage(
            representativeClaim: "five_hour",
            fiveHourUtilization: 0.5,
            fiveHourReset: nil,
            fiveHourStatus: "allowed",
            sevenDayUtilization: 0.1,
            sevenDayReset: nil,
            sevenDayStatus: "allowed",
            overallStatus: "allowed"
        )
        // Reset transition state, then send allowed
        UsageViewModel.recordThrottleEvent(nil)
        UsageViewModel.recordThrottleEvent(rl)
        let timestamps = UserDefaults.standard.array(forKey: key) as? [Double] ?? []
        #expect(timestamps.isEmpty)
    }

    @Test func recordThrottleEvent_throttled_recordsTimestamp() {
        let key = UserDefaultsKeys.throttleTimestamps
        UserDefaults.standard.removeObject(forKey: key)
        let rl = RateLimitUsage(
            representativeClaim: "five_hour",
            fiveHourUtilization: 1.0,
            fiveHourReset: nil,
            fiveHourStatus: "throttled",
            sevenDayUtilization: 0.1,
            sevenDayReset: nil,
            sevenDayStatus: "allowed",
            overallStatus: "throttled"
        )
        // Reset then transition to throttled
        UsageViewModel.recordThrottleEvent(nil)
        UsageViewModel.recordThrottleEvent(rl)
        let timestamps = UserDefaults.standard.array(forKey: key) as? [Double] ?? []
        #expect(timestamps.count == 1)
        UserDefaults.standard.removeObject(forKey: key)
    }

    @Test func recordThrottleEvent_repeatedThrottle_noDoubleCount() {
        let key = UserDefaultsKeys.throttleTimestamps
        UserDefaults.standard.removeObject(forKey: key)
        let rl = RateLimitUsage(
            representativeClaim: "five_hour",
            fiveHourUtilization: 1.0,
            fiveHourReset: nil,
            fiveHourStatus: "throttled",
            sevenDayUtilization: 0.1,
            sevenDayReset: nil,
            sevenDayStatus: "allowed",
            overallStatus: "throttled"
        )
        // Transition: not-throttled → throttled
        UsageViewModel.recordThrottleEvent(nil)
        UsageViewModel.recordThrottleEvent(rl)
        // Still throttled on next polls — should NOT record again
        UsageViewModel.recordThrottleEvent(rl)
        UsageViewModel.recordThrottleEvent(rl)
        let timestamps = UserDefaults.standard.array(forKey: key) as? [Double] ?? []
        #expect(timestamps.count == 1)
        UserDefaults.standard.removeObject(forKey: key)
    }

    @Test func recordThrottleEvent_exhaustedButNotThrottled_records() {
        let key = UserDefaultsKeys.throttleTimestamps
        UserDefaults.standard.removeObject(forKey: key)
        // 100% utilization but status still says "allowed" (polling caught it late)
        let rl = RateLimitUsage(
            representativeClaim: "five_hour",
            fiveHourUtilization: 1.0,
            fiveHourReset: nil,
            fiveHourStatus: "allowed",
            sevenDayUtilization: 0.3,
            sevenDayReset: nil,
            sevenDayStatus: "allowed",
            overallStatus: "allowed"
        )
        UsageViewModel.recordThrottleEvent(nil)
        UsageViewModel.recordThrottleEvent(rl)
        let timestamps = UserDefaults.standard.array(forKey: key) as? [Double] ?? []
        #expect(timestamps.count == 1)
        UserDefaults.standard.removeObject(forKey: key)
    }

    @Test func recordThrottleEvent_sevenDayExhausted_records() {
        let key = UserDefaultsKeys.throttleTimestamps
        UserDefaults.standard.removeObject(forKey: key)
        let rl = RateLimitUsage(
            representativeClaim: "seven_day",
            fiveHourUtilization: 0.2,
            fiveHourReset: nil,
            fiveHourStatus: "allowed",
            sevenDayUtilization: 1.0,
            sevenDayReset: nil,
            sevenDayStatus: "allowed",
            overallStatus: "allowed"
        )
        UsageViewModel.recordThrottleEvent(nil)
        UsageViewModel.recordThrottleEvent(rl)
        let timestamps = UserDefaults.standard.array(forKey: key) as? [Double] ?? []
        #expect(timestamps.count == 1)
        UserDefaults.standard.removeObject(forKey: key)
    }

    // MARK: - throttleCount

    @Test func throttleCount_noData_returnsZero() {
        let key = UserDefaultsKeys.throttleTimestamps
        UserDefaults.standard.removeObject(forKey: key)
        #expect(UsageViewModel.throttleCount(days: 7) == 0)
    }

    @Test func throttleCount_stringTimestamps_parsedCorrectly() {
        let key = UserDefaultsKeys.throttleTimestamps
        let now = Date().timeIntervalSince1970
        // Simulate legacy string-typed timestamps (the actual bug that caused 0 counts)
        UserDefaults.standard.set([String(now), String(now - 86400)], forKey: key)
        #expect(UsageViewModel.throttleCount(days: 7) == 2)
        UserDefaults.standard.removeObject(forKey: key)
    }

    @Test func throttleCount_filtersOldEvents() {
        let key = UserDefaultsKeys.throttleTimestamps
        let now = Date().timeIntervalSince1970
        let old = now - 8 * 86400 // 8 days ago
        UserDefaults.standard.set([old, now], forKey: key)
        #expect(UsageViewModel.throttleCount(days: 7) == 1)
        #expect(UsageViewModel.throttleCount(days: 30) == 2)
        UserDefaults.standard.removeObject(forKey: key)
    }
}

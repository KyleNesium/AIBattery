import Testing
import Foundation
@testable import AIBatteryCore

@Suite("UsageViewModel")
@MainActor
struct UsageViewModelTests {

    // MARK: - clampedRefreshInterval

    @Test func clampedRefreshInterval_zero_returnsDefault() {
        #expect(UsageViewModel.clampedRefreshInterval(0) == 120)
    }

    @Test func clampedRefreshInterval_negative_returnsDefault() {
        #expect(UsageViewModel.clampedRefreshInterval(-10) == 120)
    }

    @Test func clampedRefreshInterval_belowMin_clampsToMin() {
        #expect(UsageViewModel.clampedRefreshInterval(5) == 30)
    }

    @Test func clampedRefreshInterval_aboveMax_clampsToMax() {
        #expect(UsageViewModel.clampedRefreshInterval(500) == 300)
    }

    @Test func clampedRefreshInterval_inRange_returnsAsIs() {
        #expect(UsageViewModel.clampedRefreshInterval(120) == 120)
    }

    @Test func clampedRefreshInterval_exactMin_returnsMin() {
        #expect(UsageViewModel.clampedRefreshInterval(30) == 30)
    }

    @Test func clampedRefreshInterval_exactMax_returnsMax() {
        #expect(UsageViewModel.clampedRefreshInterval(300) == 300)
    }

    // MARK: - refreshErrorMessage

    @Test func refreshErrorMessage_noDataNoMessages_returnsNoUsage() {
        let msg = UsageViewModel.refreshErrorMessage(
            hasRateLimits: false,
            hasStandardLimits: false,
            hasProfile: false,
            hasStandardRateLimitHeaders: false,
            totalMessages: 0
        )
        #expect(msg == "No usage data yet. Start a Claude Code session to see your stats.")
    }

    @Test func refreshErrorMessage_noDataWithMessages_returnsAPIError() {
        let msg = UsageViewModel.refreshErrorMessage(
            hasRateLimits: false,
            hasStandardLimits: false,
            hasProfile: false,
            hasStandardRateLimitHeaders: false,
            totalMessages: 50
        )
        #expect(msg == "Unable to reach Anthropic API. Check your internet connection and try again.")
    }

    @Test func refreshErrorMessage_hasRateLimits_returnsNil() {
        let msg = UsageViewModel.refreshErrorMessage(
            hasRateLimits: true,
            hasStandardLimits: false,
            hasProfile: false,
            hasStandardRateLimitHeaders: false,
            totalMessages: 0
        )
        #expect(msg == nil)
    }

    @Test func refreshErrorMessage_hasStandardLimits_returnsNil() {
        let msg = UsageViewModel.refreshErrorMessage(
            hasRateLimits: false,
            hasStandardLimits: true,
            hasProfile: true,
            hasStandardRateLimitHeaders: true,
            totalMessages: 50
        )
        #expect(msg == nil)
    }

    @Test func refreshErrorMessage_hasProfileOnly_returnsNil() {
        let msg = UsageViewModel.refreshErrorMessage(
            hasRateLimits: false,
            hasStandardLimits: false,
            hasProfile: true,
            hasStandardRateLimitHeaders: false,
            totalMessages: 0
        )
        #expect(msg == nil)
    }

    @Test func refreshErrorMessage_publicAPIHeadersOnly_returnsNil() {
        let msg = UsageViewModel.refreshErrorMessage(
            hasRateLimits: false,
            hasStandardLimits: false,
            hasProfile: true,
            hasStandardRateLimitHeaders: true,
            totalMessages: 0
        )
        #expect(msg == nil)
    }

    @Test func refreshErrorMessage_hasBothData_returnsNil() {
        let msg = UsageViewModel.refreshErrorMessage(
            hasRateLimits: true,
            hasStandardLimits: false,
            hasProfile: true,
            hasStandardRateLimitHeaders: true,
            totalMessages: 100
        )
        #expect(msg == nil)
    }

    @Test func refreshErrorMessage_profileAndMessages_returnsNil() {
        let msg = UsageViewModel.refreshErrorMessage(
            hasRateLimits: false,
            hasStandardLimits: false,
            hasProfile: true,
            hasStandardRateLimitHeaders: false,
            totalMessages: 100
        )
        #expect(msg == nil)
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

    // MARK: - effectiveRateLimits (TTL-based stale fallback)

    @Test func effectiveRateLimits_freshData_returnsFresh() {
        let fresh = RateLimitUsage(
            representativeClaim: "five_hour",
            fiveHourUtilization: 0.6,
            fiveHourReset: nil,
            fiveHourStatus: "allowed",
            sevenDayUtilization: 0.2,
            sevenDayReset: nil,
            sevenDayStatus: "allowed",
            overallStatus: "allowed"
        )
        let stale = RateLimitUsage(
            representativeClaim: "five_hour",
            fiveHourUtilization: 0.1,
            fiveHourReset: nil,
            fiveHourStatus: "allowed",
            sevenDayUtilization: 0.05,
            sevenDayReset: nil,
            sevenDayStatus: "allowed",
            overallStatus: "allowed"
        )
        let result = UsageViewModel.effectiveRateLimits(
            fresh: fresh,
            stale: stale,
            lastFreshAt: Date(),
            ttl: 300
        )
        #expect(result?.fiveHourUtilization == 0.6)
    }

    @Test func effectiveRateLimits_noFresh_withinTTL_returnsStale() {
        let stale = RateLimitUsage(
            representativeClaim: "five_hour",
            fiveHourUtilization: 0.5,
            fiveHourReset: nil,
            fiveHourStatus: "allowed",
            sevenDayUtilization: 0.2,
            sevenDayReset: nil,
            sevenDayStatus: "allowed",
            overallStatus: "allowed"
        )
        let now = Date()
        let result = UsageViewModel.effectiveRateLimits(
            fresh: nil,
            stale: stale,
            lastFreshAt: now.addingTimeInterval(-120), // 2 min ago, within 5 min TTL
            ttl: 300,
            now: now
        )
        #expect(result?.fiveHourUtilization == 0.5)
    }

    @Test func effectiveRateLimits_noFresh_expiredTTL_returnsNil() {
        let stale = RateLimitUsage(
            representativeClaim: "five_hour",
            fiveHourUtilization: 0.5,
            fiveHourReset: nil,
            fiveHourStatus: "allowed",
            sevenDayUtilization: 0.2,
            sevenDayReset: nil,
            sevenDayStatus: "allowed",
            overallStatus: "allowed"
        )
        let now = Date()
        let result = UsageViewModel.effectiveRateLimits(
            fresh: nil,
            stale: stale,
            lastFreshAt: now.addingTimeInterval(-600), // 10 min ago, past 5 min TTL
            ttl: 300,
            now: now
        )
        #expect(result == nil)
    }

    @Test func effectiveRateLimits_noFresh_noLastFreshAt_returnsNil() {
        let stale = RateLimitUsage(
            representativeClaim: "five_hour",
            fiveHourUtilization: 0.5,
            fiveHourReset: nil,
            fiveHourStatus: "allowed",
            sevenDayUtilization: 0.2,
            sevenDayReset: nil,
            sevenDayStatus: "allowed",
            overallStatus: "allowed"
        )
        let result = UsageViewModel.effectiveRateLimits(
            fresh: nil,
            stale: stale,
            lastFreshAt: nil,
            ttl: 300
        )
        #expect(result == nil)
    }

    @Test func effectiveRateLimits_noFresh_noStale_returnsNil() {
        let result = UsageViewModel.effectiveRateLimits(
            fresh: nil,
            stale: nil,
            lastFreshAt: Date(),
            ttl: 300
        )
        #expect(result == nil)
    }

    @Test func effectiveRateLimits_exactlyAtTTL_returnsStale() {
        let stale = RateLimitUsage(
            representativeClaim: "five_hour",
            fiveHourUtilization: 0.5,
            fiveHourReset: nil,
            fiveHourStatus: "allowed",
            sevenDayUtilization: 0.2,
            sevenDayReset: nil,
            sevenDayStatus: "allowed",
            overallStatus: "allowed"
        )
        let now = Date()
        let result = UsageViewModel.effectiveRateLimits(
            fresh: nil,
            stale: stale,
            lastFreshAt: now.addingTimeInterval(-300), // exactly 5 min
            ttl: 300,
            now: now
        )
        #expect(result != nil) // boundary: <= ttl includes exact match
    }

    // MARK: - effectiveValue (generic TTL guard)

    @Test func effectiveValue_freshPresent_returnsFresh() {
        let result: RateLimitSource? = UsageViewModel.effectiveValue(
            fresh: .claudeCodeClientData,
            stale: .anthropicAPIHeaders,
            lastFreshAt: Date(),
            ttl: 300
        )
        #expect(result == .claudeCodeClientData)
    }

    @Test func effectiveValue_noFresh_withinTTL_returnsStale() {
        let now = Date()
        let result: RateLimitSource? = UsageViewModel.effectiveValue(
            fresh: nil,
            stale: .anthropicAPIHeaders,
            lastFreshAt: now.addingTimeInterval(-60),
            ttl: 300,
            now: now
        )
        #expect(result == .anthropicAPIHeaders)
    }

    @Test func effectiveValue_noFresh_expiredTTL_returnsNil() {
        let now = Date()
        let result: RateLimitSource? = UsageViewModel.effectiveValue(
            fresh: nil,
            stale: .anthropicAPIHeaders,
            lastFreshAt: now.addingTimeInterval(-600),
            ttl: 300,
            now: now
        )
        #expect(result == nil)
    }
}

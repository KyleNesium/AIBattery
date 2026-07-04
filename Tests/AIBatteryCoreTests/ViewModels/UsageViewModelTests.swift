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

    @Test func refreshErrorMessage_authError_returnsReconnectMessage() {
        let msg = UsageViewModel.refreshErrorMessage(
            hasRateLimits: true, // even with all data present,
            hasStandardLimits: true, // an authError must take precedence —
            hasProfile: true, // the data is stale and the user needs
            hasStandardRateLimitHeaders: true,
            totalMessages: 100,
            authError: true
        )
        #expect(msg == "Authentication failed — please log out and reconnect this account.")
    }

    @Test func refreshErrorMessage_noAuthError_unchangedFromBefore() {
        // Default authError: false should match the existing behavior.
        let msg = UsageViewModel.refreshErrorMessage(
            hasRateLimits: false,
            hasStandardLimits: false,
            hasProfile: false,
            hasStandardRateLimitHeaders: false,
            totalMessages: 0,
            authError: false
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

    @Test func recordThrottleEvent_at100ButAllowed_doesNotRecord() {
        let key = UserDefaultsKeys.throttleTimestamps
        UserDefaults.standard.removeObject(forKey: key)
        // 100% utilization with an "allowed" status is "at capacity", not throttled —
        // it must NOT record a throttle event.
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
        #expect(timestamps.isEmpty)
        UserDefaults.standard.removeObject(forKey: key)
    }

    @Test func recordThrottleEvent_sevenDayAt100ButAllowed_doesNotRecord() {
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
        #expect(timestamps.isEmpty)
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
        UserDefaults.standard.set([String(now), String(now - 86_400)], forKey: key)
        #expect(UsageViewModel.throttleCount(days: 7) == 2)
        UserDefaults.standard.removeObject(forKey: key)
    }

    @Test func throttleCount_filtersOldEvents() {
        let key = UserDefaultsKeys.throttleTimestamps
        let now = Date().timeIntervalSince1970
        let old = now - 8 * 86_400 // 8 days ago
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

    // MARK: - rateLimitsAreFresh / alarmConfirmed (wake false-alarm gate)

    //
    // `isShowingCachedData` only tracks whether the network fetch hit cache. The alarm /
    // displayed % must instead gate on whether the rate-limit VALUES are fresh: a fetch
    // can succeed (not cached) yet carry no unified headers (~90% of polls), reusing held
    // stale limits. These pin the gate that fixes the false "limit reached" on wake.

    @Test func rateLimitsAreFresh_freshHeaders_true() {
        let rl = RateLimitUsage(
            representativeClaim: "five_hour",
            fiveHourUtilization: 0.6, fiveHourReset: nil, fiveHourStatus: "allowed",
            sevenDayUtilization: 0.2, sevenDayReset: nil, sevenDayStatus: "allowed",
            overallStatus: "allowed"
        )
        #expect(UsageViewModel.rateLimitsAreFresh(freshRateLimits: rl, isCached: false) == true)
    }

    @Test func rateLimitsAreFresh_fetchSucceededNoHeaders_false() {
        // The exact bug condition: successful fetch (not cached) but no unified headers.
        #expect(UsageViewModel.rateLimitsAreFresh(freshRateLimits: nil, isCached: false) == false)
    }

    @Test func rateLimitsAreFresh_cachedFetch_false() {
        let rl = RateLimitUsage(
            representativeClaim: "five_hour",
            fiveHourUtilization: 0.6, fiveHourReset: nil, fiveHourStatus: "allowed",
            sevenDayUtilization: 0.2, sevenDayReset: nil, sevenDayStatus: "allowed",
            overallStatus: "allowed"
        )
        // Even cache-served data WITH headers is not "fresh".
        #expect(UsageViewModel.rateLimitsAreFresh(freshRateLimits: rl, isCached: true) == false)
    }

    @Test func alarmConfirmed_freshNotThrottled_true() {
        #expect(UsageViewModel.alarmConfirmed(rateLimitsFresh: true, displayedIsThrottled: false) == true)
    }

    @Test func alarmConfirmed_staleNotThrottled_false() {
        // Kills the false "Limit reached": held stale 100% with no throttle is suppressed.
        #expect(UsageViewModel.alarmConfirmed(rateLimitsFresh: false, displayedIsThrottled: false) == false)
    }

    @Test func alarmConfirmed_staleButThrottled_true() {
        // A genuine throttle (authoritative, self-expiring) must keep alarming across the
        // ~90% of polls that lack fresh headers — no flicker.
        #expect(UsageViewModel.alarmConfirmed(rateLimitsFresh: false, displayedIsThrottled: true) == true)
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

    /// Regression: with only ~10% of polls returning unified headers, a snapshot's
    /// 5h reset can pass while the same `rateLimits` value is still being reused
    /// as the stale fallback. The user-visible bug: menu bar shows "100%" + broken
    /// star for hours after the window has actually reset, until a fresh-headers
    /// fetch finally lands. Fix normalizes the stale value with
    /// `withClearedExpiredWindows(now:)` before returning.
    @Test func effectiveRateLimits_staleWithExpiredFiveHour_clearsToZero() {
        let now = Date()
        let stale = RateLimitUsage(
            representativeClaim: "five_hour",
            fiveHourUtilization: 1.0, // was at the cap
            fiveHourReset: now.addingTimeInterval(-300), // reset passed 5 min ago
            fiveHourStatus: "throttled",
            sevenDayUtilization: 0.4,
            sevenDayReset: now.addingTimeInterval(86_400), // 7d still active
            sevenDayStatus: "allowed",
            overallStatus: "throttled"
        )
        let result = UsageViewModel.effectiveRateLimits(
            fresh: nil,
            stale: stale,
            lastFreshAt: now.addingTimeInterval(-600), // 10 min ago, within 24h TTL
            ttl: 86_400,
            now: now
        )
        #expect(result?.fiveHourUtilization == 0)
        #expect(result?.fiveHourStatus == "allowed")
        #expect(result?.fiveHourReset == nil)
        #expect(result?.overallStatus == "allowed") // binding (5h) expired → overall clears
        #expect(result?.sevenDayUtilization == 0.4) // 7d untouched
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

    // MARK: - shouldApplyFetchResult (cross-account refresh race)

    @Test func shouldApplyFetchResult_sameAccount_applies() {
        #expect(UsageViewModel.shouldApplyFetchResult(fetchedAccountId: "org-a", activeAccountId: "org-a"))
    }

    @Test func shouldApplyFetchResult_switchedAccount_discards() {
        #expect(!UsageViewModel.shouldApplyFetchResult(fetchedAccountId: "org-a", activeAccountId: "org-b"))
    }

    @Test func shouldApplyFetchResult_accountRemovedMidFetch_discards() {
        #expect(!UsageViewModel.shouldApplyFetchResult(fetchedAccountId: "org-a", activeAccountId: nil))
    }

    @Test func shouldApplyFetchResult_accountAddedMidFetch_discards() {
        #expect(!UsageViewModel.shouldApplyFetchResult(fetchedAccountId: nil, activeAccountId: "org-a"))
    }

    @Test func shouldApplyFetchResult_bothNil_applies() {
        #expect(UsageViewModel.shouldApplyFetchResult(fetchedAccountId: nil, activeAccountId: nil))
    }

    // MARK: - alertableRateLimits (stale-data gate on notifications)

    private static func makeRateLimits(fiveHourUtil: Double = 0.85) -> RateLimitUsage {
        RateLimitUsage(
            representativeClaim: "five_hour",
            fiveHourUtilization: fiveHourUtil,
            fiveHourReset: Date().addingTimeInterval(3_600),
            fiveHourStatus: "allowed",
            sevenDayUtilization: 0.4,
            sevenDayReset: Date().addingTimeInterval(86_400),
            sevenDayStatus: "allowed",
            overallStatus: "allowed"
        )
    }

    @Test func alertableRateLimits_freshConfirmed_returnsLimits() {
        let rl = Self.makeRateLimits()
        #expect(UsageViewModel.alertableRateLimits(confirmed: rl, rateLimitsFresh: true) == rl)
    }

    @Test func alertableRateLimits_notFresh_neverAlerts() {
        // Cached / header-less / held-stale: notifications must never fire (mirrors the
        // menu bar alarm gate). Only a genuinely fresh reading may alert.
        #expect(UsageViewModel.alertableRateLimits(confirmed: Self.makeRateLimits(), rateLimitsFresh: false) == nil)
    }

    @Test func alertableRateLimits_freshWithoutLimits_returnsNil() {
        #expect(UsageViewModel.alertableRateLimits(confirmed: nil, rateLimitsFresh: true) == nil)
    }

    // MARK: - spikeConfirmedRateLimits (confirm-before-alarming on fresh readings)

    //
    // Pins the fix for the RECURRENCE of the false "5-Hour limit reached" on wake: the
    // server can return a transport-FRESH but wrong ~100% reading for a window right
    // after wake (eventual consistency), which the freshness gate trusted. This filter
    // holds an isolated near-full spike at the previous displayed value until a SECOND
    // consecutive fresh poll confirms it. "rather show stale than a false used value."

    /// Shared reference resets so memory entries and fresh readings refer to the same
    /// window instance unless a test deliberately shifts them.
    private static let fiveHourResetRef = Date().addingTimeInterval(17_700)
    private static let sevenDayResetRef = Date().addingTimeInterval(86_400)

    private static func makeWindows(
        fiveHourUtil: Double, fiveHourStatus: String = "allowed",
        sevenDayUtil: Double = 0.2, sevenDayStatus: String = "allowed",
        overallStatus: String = "allowed",
        representativeClaim: String = "five_hour",
        fiveHourReset: Date? = fiveHourResetRef,
        sevenDayReset: Date? = sevenDayResetRef
    ) -> RateLimitUsage {
        RateLimitUsage(
            representativeClaim: representativeClaim,
            fiveHourUtilization: fiveHourUtil,
            fiveHourReset: fiveHourReset,
            fiveHourStatus: fiveHourStatus,
            sevenDayUtilization: sevenDayUtil,
            sevenDayReset: sevenDayReset,
            sevenDayStatus: sevenDayStatus,
            overallStatus: overallStatus
        )
    }

    @Test func spikeConfirmed_isolatedSpike_heldAtPreviousValue() {
        // The exact wake bug: fresh 5h reads 100% but was 2% last poll and isn't yet
        // confirmed. Show the previous 2%, not the spike. Record it as near-full (keyed
        // by the window's reset) so a repeat next poll confirms.
        let fresh = Self.makeWindows(fiveHourUtil: 1.0)
        let previous = Self.makeWindows(fiveHourUtil: 0.02)
        let result = UsageViewModel.spikeConfirmedRateLimits(
            fresh: fresh, previousDisplayed: previous, previouslyNearFull: [:]
        )
        #expect(result.display.fiveHourUtilization == 0.02)
        #expect(result.heldWindows == [RateLimitUsage.fiveHourWindow])
        #expect(result.nearFullWindows == [RateLimitUsage.fiveHourWindow: Self.fiveHourResetRef])
    }

    @Test func spikeConfirmed_repeatedSpike_accepted() {
        // Second consecutive fresh near-full poll on the SAME window instance (memory
        // reset matches the fresh reset) — a genuine sustained limit. Trust it.
        let fresh = Self.makeWindows(fiveHourUtil: 1.0)
        let previous = Self.makeWindows(fiveHourUtil: 0.02)
        let result = UsageViewModel.spikeConfirmedRateLimits(
            fresh: fresh, previousDisplayed: previous,
            previouslyNearFull: [RateLimitUsage.fiveHourWindow: Self.fiveHourResetRef]
        )
        #expect(result.display.fiveHourUtilization == 1.0)
        #expect(result.heldWindows.isEmpty)
    }

    @Test func spikeConfirmed_staleMemoryFromPreviousWindowInstance_doesNotConfirm() {
        // The near-full memory predates a window rollover (e.g. an endpoint outage
        // spanning the reset with no wake/unlock to clear it): its stored reset belongs
        // to the OLD window instance. A post-rollover fresh glitch must NOT be treated
        // as a confirmed continuation — the old memory can't vouch for a new window.
        let fresh = Self.makeWindows(fiveHourUtil: 1.0)
        let previous = Self.makeWindows(fiveHourUtil: 0.04)
        let staleReset = Self.fiveHourResetRef.addingTimeInterval(-18_000) // previous window's reset
        let result = UsageViewModel.spikeConfirmedRateLimits(
            fresh: fresh, previousDisplayed: previous,
            previouslyNearFull: [RateLimitUsage.fiveHourWindow: staleReset]
        )
        #expect(result.display.fiveHourUtilization == 0.04) // held, not confirmed
        #expect(result.heldWindows == [RateLimitUsage.fiveHourWindow])
    }

    @Test func spikeConfirmed_resetlessReadings_matchViaSentinel() {
        // Some payloads carry no reset date. Two consecutive reset-less near-full
        // readings must still confirm each other (sentinel-to-sentinel match).
        let fresh = Self.makeWindows(fiveHourUtil: 1.0, fiveHourReset: nil)
        let previous = Self.makeWindows(fiveHourUtil: 0.02, fiveHourReset: nil)
        let first = UsageViewModel.spikeConfirmedRateLimits(
            fresh: fresh, previousDisplayed: previous, previouslyNearFull: [:]
        )
        #expect(first.heldWindows == [RateLimitUsage.fiveHourWindow])
        let second = UsageViewModel.spikeConfirmedRateLimits(
            fresh: fresh, previousDisplayed: previous, previouslyNearFull: first.nearFullWindows
        )
        #expect(second.display.fiveHourUtilization == 1.0)
        #expect(second.heldWindows.isEmpty)
    }

    @Test func spikeConfirmed_genuineThrottle_bypassesFilter() {
        // An authoritative throttle is never debounced — shown immediately. It IS
        // recorded as near-full, so the poll after the throttle clears (still high,
        // now "allowed") reads as a confirmed continuation, not an isolated spike.
        let fresh = Self.makeWindows(fiveHourUtil: 1.0, fiveHourStatus: "throttled", overallStatus: "throttled")
        let previous = Self.makeWindows(fiveHourUtil: 0.02)
        let result = UsageViewModel.spikeConfirmedRateLimits(
            fresh: fresh, previousDisplayed: previous, previouslyNearFull: [:]
        )
        #expect(result.display.fiveHourUtilization == 1.0)
        #expect(result.display.fiveHourStatus == "throttled")
        #expect(result.heldWindows.isEmpty)
        #expect(result.nearFullWindows == [RateLimitUsage.fiveHourWindow: Self.fiveHourResetRef])
    }

    @Test func spikeConfirmed_overallThrottleOnBindingWindow_bypassesHold() {
        // A payload can assert the throttle only via overallStatus while the per-window
        // status lags behind as "allowed" (isThrottled treats overall=="throttled" as a
        // real throttle). The binding window must not be held in that shape — holding
        // would hide an authoritative throttle behind a substituted low value.
        let fresh = Self.makeWindows(fiveHourUtil: 0.99, overallStatus: "throttled")
        let previous = Self.makeWindows(fiveHourUtil: 0.02)
        let result = UsageViewModel.spikeConfirmedRateLimits(
            fresh: fresh, previousDisplayed: previous, previouslyNearFull: [:]
        )
        #expect(result.display.fiveHourUtilization == 0.99)
        #expect(result.display.overallStatus == "throttled")
        #expect(result.heldWindows.isEmpty)
    }

    @Test func spikeConfirmed_throttleJustCleared_stillNearFull_accepted() {
        // Poll N was genuinely throttled at ~100% (recorded near-full). Poll N+1: the
        // server clears the throttle but the window is still 96% — a normal transition
        // near a quota boundary. Must be accepted (shown as 96%/allowed), NOT held as an
        // "isolated spike" that would re-display the just-cleared throttle.
        let fresh = Self.makeWindows(fiveHourUtil: 0.96)
        let previous = Self.makeWindows(fiveHourUtil: 0.99, fiveHourStatus: "throttled", overallStatus: "throttled")
        let result = UsageViewModel.spikeConfirmedRateLimits(
            fresh: fresh, previousDisplayed: previous,
            previouslyNearFull: [RateLimitUsage.fiveHourWindow: Self.fiveHourResetRef]
        )
        #expect(result.display.fiveHourUtilization == 0.96)
        #expect(result.display.fiveHourStatus == "allowed")
        #expect(result.heldWindows.isEmpty)
    }

    @Test func spikeConfirmed_heldWindow_neverInheritsPreviousThrottledStatus() {
        // Near-full memory was cleared (e.g. wake) and the previous displayed value was a
        // cached pre-sleep throttle. A fresh 100%/allowed reading is held — but the held
        // window must NOT inherit the previous "throttled" status: the fresh reading said
        // not-throttled, and a hold must never resurrect a throttle the server cleared.
        let fresh = Self.makeWindows(fiveHourUtil: 1.0)
        let previous = Self.makeWindows(fiveHourUtil: 1.0, fiveHourStatus: "throttled", overallStatus: "throttled")
        let result = UsageViewModel.spikeConfirmedRateLimits(
            fresh: fresh, previousDisplayed: previous, previouslyNearFull: [:]
        )
        #expect(result.heldWindows == [RateLimitUsage.fiveHourWindow])
        #expect(result.display.fiveHourUtilization == 1.0) // previous real value kept
        #expect(result.display.fiveHourStatus == "allowed") // status never inherited
        #expect(result.display.overallStatus == "allowed")
    }

    @Test func spikeConfirmed_bindingHeldWithOtherWindowThrottled_keepsOverallThrottled() {
        // The binding 5h window is held (isolated spike), but the 7d window is genuinely
        // throttled per its own status. Forcing overall to "allowed" because the binding
        // window was held would mask the real 7d throttle — the display's overall status
        // must stay consistent with its own windows.
        let fresh = Self.makeWindows(
            fiveHourUtil: 1.0,
            sevenDayUtil: 0.99, sevenDayStatus: "throttled"
        )
        let previous = Self.makeWindows(fiveHourUtil: 0.02, sevenDayUtil: 0.99, sevenDayStatus: "throttled")
        let result = UsageViewModel.spikeConfirmedRateLimits(
            fresh: fresh, previousDisplayed: previous,
            previouslyNearFull: [RateLimitUsage.sevenDayWindow: Self.sevenDayResetRef]
        )
        #expect(result.heldWindows == [RateLimitUsage.fiveHourWindow])
        #expect(result.display.fiveHourUtilization == 0.02) // held
        #expect(result.display.sevenDayStatus == "throttled") // genuine throttle kept
        #expect(result.display.overallStatus == "throttled") // not masked by the hold
    }

    @Test func spikeConfirmed_sustainedHighPrevious_staysHigh() {
        // Previous displayed was ALSO 100% (a genuine limit already shown). Even though
        // "held" (near-full memory was cleared, e.g. on wake), substituting the previous
        // value keeps it at 100% — a real sustained limit is never hidden.
        let fresh = Self.makeWindows(fiveHourUtil: 1.0)
        let previous = Self.makeWindows(fiveHourUtil: 1.0)
        let result = UsageViewModel.spikeConfirmedRateLimits(
            fresh: fresh, previousDisplayed: previous, previouslyNearFull: [:]
        )
        #expect(result.display.fiveHourUtilization == 1.0)
    }

    @Test func spikeConfirmed_noPreviousValue_acceptsFreshReading() {
        // True cold start, no cached previous. There is nothing to hold AT — the fresh
        // reading is the only real value, and fabricating a 0% would be a false LOW
        // (hiding a genuinely near-full account and poisoning the persisted cache via
        // the write-back). Show the real value; the alarm is gated separately.
        let fresh = Self.makeWindows(fiveHourUtil: 1.0)
        let result = UsageViewModel.spikeConfirmedRateLimits(
            fresh: fresh, previousDisplayed: nil, previouslyNearFull: [:]
        )
        #expect(result.display == fresh)
        #expect(result.heldWindows.isEmpty)
        #expect(result.nearFullWindows == [RateLimitUsage.fiveHourWindow: Self.fiveHourResetRef])
    }

    @Test func spikeConfirmed_perWindowIndependent() {
        // 5h glitches (jump from low, held); 7d is a genuine sustained limit (confirmed).
        // One window's hold must not affect the other.
        let fresh = Self.makeWindows(fiveHourUtil: 1.0, sevenDayUtil: 1.0)
        let previous = Self.makeWindows(fiveHourUtil: 0.02, sevenDayUtil: 0.99)
        let result = UsageViewModel.spikeConfirmedRateLimits(
            fresh: fresh, previousDisplayed: previous,
            previouslyNearFull: [RateLimitUsage.sevenDayWindow: Self.sevenDayResetRef]
        )
        #expect(result.display.fiveHourUtilization == 0.02) // held
        #expect(result.display.sevenDayUtilization == 1.0) // confirmed
        #expect(result.heldWindows == [RateLimitUsage.fiveHourWindow])
    }

    @Test func spikeConfirmed_lowReading_passesThrough() {
        let fresh = Self.makeWindows(fiveHourUtil: 0.30)
        let previous = Self.makeWindows(fiveHourUtil: 0.25)
        let result = UsageViewModel.spikeConfirmedRateLimits(
            fresh: fresh, previousDisplayed: previous, previouslyNearFull: [:]
        )
        #expect(result.display.fiveHourUtilization == 0.30)
        #expect(result.heldWindows.isEmpty)
        #expect(result.nearFullWindows.isEmpty)
    }
}

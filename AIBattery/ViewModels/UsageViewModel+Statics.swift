import Foundation

// MARK: - Pure helpers extracted from UsageViewModel

//
// Lives in an extension so it stays addressable as `UsageViewModel.foo`
// for both production callers and the existing test suite, while keeping
// the main view-model file focused on observable state and orchestration.
//
// Throttle bookkeeping (recordThrottleEvent / throttleCount) stays in the
// main file because it depends on a private static stored ThrottleTracker.

extension UsageViewModel {
    /// Default polling interval when no user preference is set (seconds).
    nonisolated static let defaultRefreshInterval: TimeInterval = 120
    /// Minimum allowed polling interval (seconds).
    nonisolated static let minRefreshInterval: TimeInterval = 30
    /// Maximum allowed polling interval (seconds).
    nonisolated static let maxRefreshInterval: TimeInterval = 300

    /// Clamp a stored refresh interval to the valid range [30, 300]. Zero/negative → 120 (default).
    nonisolated static func clampedRefreshInterval(_ stored: Double) -> TimeInterval {
        let interval = stored > 0 ? stored : defaultRefreshInterval
        return min(max(interval, minRefreshInterval), maxRefreshInterval)
    }

    /// Determine the error message to show after a refresh where the API returned no data.
    /// Returns nil when rate limits are present (no error to show).
    /// `authError` takes precedence — a persistent auth failure means stale data
    /// is misleading; tell the user to reconnect.
    nonisolated static func refreshErrorMessage(
        hasRateLimits: Bool,
        hasStandardLimits: Bool,
        hasProfile: Bool,
        hasStandardRateLimitHeaders: Bool,
        totalMessages: Int,
        authError: Bool = false
    ) -> String? {
        if authError {
            return "Authentication failed — please log out and reconnect this account."
        }
        if hasRateLimits { return nil }
        if hasStandardLimits { return nil }
        if hasStandardRateLimitHeaders { return nil }
        if !hasProfile && totalMessages == 0 {
            return "No usage data yet. Start a Claude Code session to see your stats."
        }
        if hasProfile { return nil }
        return "Unable to reach Anthropic API. Check your internet connection and try again."
    }

    /// Whether snapshot data has changed compared to previous values. Used by adaptive polling.
    /// Returns true on first load (previousTotal < 0) or when totals differ.
    nonisolated static func hasDataChanged(previousTotal: Int, previousToday: Int, newTotal: Int, newToday: Int) -> Bool {
        previousTotal < 0 || newTotal != previousTotal || newToday != previousToday
    }

    /// Whether the rate-limit *values* on display came from a genuinely fresh fetch this
    /// cycle — the API returned unified rate-limit headers AND the result was not served
    /// from cache. Distinct from `!isShowingCachedData`, which only reports whether the
    /// network *fetch* hit cache: a fetch can succeed (not cached) yet carry no unified
    /// headers (~90% of polls), in which case the held stale rate limits are reused and
    /// must NOT be treated as confirmed for alarm or percentage purposes.
    nonisolated static func rateLimitsAreFresh(freshRateLimits: RateLimitUsage?, isCached: Bool) -> Bool {
        freshRateLimits != nil && !isCached
    }

    /// The alarm / displayed-percentage confirmation gate. A bare "Limit reached" (≥100%
    /// with no throttle) must require genuinely fresh data, so a stale held reading can't
    /// fire a false alarm on wake. A genuine throttle (explicit API status, carries a
    /// reset) is authoritative and self-expires via `withClearedExpiredWindows`, so it
    /// may persist across the ~90% of polls that lack fresh headers without flickering.
    nonisolated static func alarmConfirmed(rateLimitsFresh: Bool, displayedIsThrottled: Bool) -> Bool {
        rateLimitsFresh || displayedIsThrottled
    }

    /// Return fresh rate limits, or stale ones if within the TTL window, or nil if expired.
    /// Pure function — injectable `now` for testing.
    ///
    /// The stale value is normalized with `withClearedExpiredWindows(now:)` before being
    /// returned: with only ~10% of polls returning unified headers, a snapshot's reset
    /// timestamp can pass while the same `rateLimits` value is still being reused as
    /// the fallback. Without this, the menu bar shows `100%` + broken star for hours
    /// after a window has actually reset, until a fresh-headers fetch finally lands.
    nonisolated static func effectiveRateLimits(
        fresh: RateLimitUsage?,
        stale: RateLimitUsage?,
        lastFreshAt: Date?,
        ttl: TimeInterval,
        now: Date = .now
    ) -> RateLimitUsage? {
        if let fresh { return fresh }
        guard let stale, let lastFreshAt else { return nil }
        let age = now.timeIntervalSince(lastFreshAt)
        if age <= ttl {
            return stale.withClearedExpiredWindows(now: now)
        }
        AppLogger.network.info("Rate limit stale fallback expired after \(Int(age))s (TTL=\(Int(ttl))s)")
        return nil
    }

    /// Whether results fetched for `fetchedAccountId` may be applied to published state.
    /// False when the user switched accounts mid-fetch — applying would show (and via
    /// downstream persistence paths, cache) one account's data under another's identity.
    nonisolated static func shouldApplyFetchResult(
        fetchedAccountId: String?,
        activeAccountId: String?
    ) -> Bool {
        fetchedAccountId == activeAccountId
    }

    /// Rate limits eligible for notification alerts, or nil when none may fire.
    /// Cached results are excluded: after wake/offline, a stale 85% reading must not
    /// fire a real macOS notification that the menu bar itself refuses to alarm on
    /// (it gates the broken star and countdown on `confirmed = !isShowingCachedData`).
    nonisolated static func alertableRateLimits(_ api: APIFetchResult) -> RateLimitUsage? {
        guard !api.isCached else { return nil }
        return api.rateLimits
    }

    /// Generic TTL guard for optional values that ride alongside rate limits.
    nonisolated static func effectiveValue<T>(
        fresh: T?,
        stale: T?,
        lastFreshAt: Date?,
        ttl: TimeInterval,
        now: Date = .now
    ) -> T? {
        if let fresh { return fresh }
        guard let stale, let lastFreshAt else { return nil }
        return now.timeIntervalSince(lastFreshAt) <= ttl ? stale : nil
    }
}

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
        if hasRateLimits {
            return nil
        }
        if hasStandardLimits {
            return nil
        }
        if hasStandardRateLimitHeaders {
            return nil
        }
        if !hasProfile && totalMessages == 0 {
            return "No usage data yet. Start a Claude Code session to see your stats."
        }
        if hasProfile {
            return nil
        }
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

    /// The alarm confirmation gate (alarm only — the displayed percentage is always the
    /// real API value). A bare "Limit reached" (≥100% with no throttle) must require
    /// genuinely fresh data, so a stale held reading can't fire a false alarm on wake.
    /// A genuine throttle (explicit API status, carries a reset) is authoritative and
    /// self-expires via `withClearedExpiredWindows`, so it may persist across the ~90%
    /// of polls that lack fresh headers without flickering.
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
        if let fresh {
            return fresh
        }
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
    /// Only a genuinely fresh reading may alert; cached / header-less / held-stale data
    /// never does (mirrors the menu bar alarm gate). Takes the **spike-confirmed** limits
    /// (`spikeConfirmedRateLimits`) rather than the raw fetch, so an unconfirmed near-full
    /// spike that is being held at its previous value can't fire a false macOS
    /// notification the bars themselves refuse to alarm on.
    nonisolated static func alertableRateLimits(
        confirmed: RateLimitUsage?,
        rateLimitsFresh: Bool
    ) -> RateLimitUsage? {
        guard rateLimitsFresh else { return nil }
        return confirmed
    }

    /// Result of `spikeConfirmedRateLimits`: the limits to display this cycle, the
    /// windows near-full in the *raw* fresh reading keyed by their reset instant
    /// (carried to the next poll), and the windows whose fresh spike was held (for logging).
    struct SpikeConfirmedRateLimits: Equatable {
        let display: RateLimitUsage
        let nearFullWindows: [String: Date]
        let heldWindows: Set<String>
    }

    /// Sentinel reset for a near-full window whose fresh reading carried no reset date.
    /// Two consecutive reset-less readings still match each other.
    nonisolated static let nearFullNoResetSentinel = Date.distantPast

    /// Tolerance when matching a remembered near-full window's reset against the next
    /// fresh reading's reset — absorbs server-side rounding jitter without letting a
    /// *different* window instance (post-rollover) inherit the confirmation.
    nonisolated static let nearFullResetMatchTolerance: TimeInterval = 60

    /// Confirm-before-alarming filter for a **fresh** rate-limit reading.
    ///
    /// Anthropic's usage endpoint can briefly return a stale ~100% for a window right
    /// after the machine wakes (server-side eventual consistency). Because that response
    /// is transport-fresh, the freshness gate (`rateLimitsFresh`) trusts it and paints a
    /// false "Limit reached" — the recurrence of the wake bug. This holds an *isolated*
    /// near-full spike: a window reading >= `rolloverArtifactUtilizationThreshold` with a
    /// non-throttled status, but that was NOT near-full on the previous fresh poll, keeps
    /// its previous displayed value until a SECOND consecutive fresh poll confirms it
    /// (two-poll confirmation). "Rather show stale than a false used value."
    ///
    /// Key properties:
    /// - A genuine `throttled` status is authoritative and never held (shown immediately).
    ///   Throttled windows ARE still recorded as near-full, so the poll right after a
    ///   throttle clears (still ~96%, now "allowed") reads as a confirmed continuation —
    ///   not an isolated spike to be held.
    /// - Substitution uses the previous *displayed* utilization, so a genuinely sustained
    ///   limit (previous was also near-full) still shows near-full — a real limit is never
    ///   hidden. The held status is always `"allowed"` (never inherited from the previous
    ///   poll — the fresh reading said not-throttled, and a hold must not re-display a
    ///   throttle the server just cleared).
    /// - With no previous value at all (true cold start, no cache) nothing is held — the
    ///   fresh reading is the only real value there is, and displaying a fabricated 0%
    ///   would be a false *low* (the alarm is separately gated per-window regardless).
    /// - The near-full memory is keyed by each window's reset instant, so a remembered
    ///   near-full from a *previous window instance* (e.g. a fresh-poll gap spanning a
    ///   rollover during an endpoint outage) can never auto-confirm a post-rollover glitch.
    /// - Per window: one window's hold never affects the other.
    ///
    /// Pure for testability. Callers persist `nearFullWindows` and pass it back next poll.
    nonisolated static func spikeConfirmedRateLimits(
        fresh: RateLimitUsage,
        previousDisplayed: RateLimitUsage?,
        previouslyNearFull: [String: Date]
    ) -> SpikeConfirmedRateLimits {
        let threshold = RateLimitUsage.rolloverArtifactUtilizationThreshold

        // A window is "near-full" (spike-tracked) whenever its utilization crosses the
        // threshold — INCLUDING an authoritative throttle. A throttled window is credibly
        // near-full, so recording it means the poll right after the throttle clears
        // (still ~96%, now "allowed") reads as a confirmed continuation, not an isolated
        // spike — without this, the filter would hold that reading and re-display the
        // just-cleared throttle for an extra poll.
        let fiveHourNearFull = fresh.fiveHourUtilization >= threshold
        let sevenDayNearFull = fresh.sevenDayUtilization >= threshold

        var nearFull: [String: Date] = [:]
        if fiveHourNearFull {
            nearFull[RateLimitUsage.fiveHourWindow] = fresh.fiveHourReset ?? Self.nearFullNoResetSentinel
        }
        if sevenDayNearFull {
            nearFull[RateLimitUsage.sevenDayWindow] = fresh.sevenDayReset ?? Self.nearFullNoResetSentinel
        }

        // A remembered near-full only confirms the SAME window instance: its stored
        // reset must match the fresh reading's reset (within jitter tolerance). A memory
        // from before a rollover carries the old reset and can't confirm the new window.
        func wasNearFull(_ window: String, freshReset: Date?) -> Bool {
            guard let remembered = previouslyNearFull[window] else { return false }
            let current = freshReset ?? Self.nearFullNoResetSentinel
            return abs(remembered.timeIntervalSince(current)) <= Self.nearFullResetMatchTolerance
        }

        // Hold a non-throttled window that is near-full now but wasn't near-full on the
        // previous fresh poll — an unconfirmed upward jump. An explicit throttle is
        // authoritative and never held; an overall "throttled" counts as a throttle on
        // the binding window (isThrottled treats it as real even when the per-window
        // status lags behind as "allowed"). With no previous displayed value there is
        // nothing to hold AT — show the fresh reading rather than fabricate a 0%.
        let bindingIsSevenDay = fresh.representativeClaim == RateLimitUsage.sevenDayWindow
        let overallThrottled = fresh.overallStatus == "throttled"
        let holdFiveHour = fiveHourNearFull && previousDisplayed != nil
            && fresh.fiveHourStatus != "throttled"
            && !(overallThrottled && !bindingIsSevenDay)
            && !wasNearFull(RateLimitUsage.fiveHourWindow, freshReset: fresh.fiveHourReset)
        let holdSevenDay = sevenDayNearFull && previousDisplayed != nil
            && fresh.sevenDayStatus != "throttled"
            && !(overallThrottled && bindingIsSevenDay)
            && !wasNearFull(RateLimitUsage.sevenDayWindow, freshReset: fresh.sevenDayReset)

        guard holdFiveHour || holdSevenDay else {
            return SpikeConfirmedRateLimits(display: fresh, nearFullWindows: nearFull, heldWindows: [])
        }

        var held: Set<String> = []
        if holdFiveHour {
            held.insert(RateLimitUsage.fiveHourWindow)
        }
        if holdSevenDay {
            held.insert(RateLimitUsage.sevenDayWindow)
        }

        // Substitute the previous displayed *utilization* for held windows. The held
        // status is always forced to "allowed" — a hold means "unconfirmed non-throttle
        // spike", and the fresh reading itself said not-throttled, so inheriting a
        // previous "throttled" here would re-display a throttle the server just cleared.
        // The display's overall status must stay consistent with its own windows: when
        // the binding window is held, a genuine throttle on the OTHER window still
        // surfaces as "throttled" instead of being masked by the hold.
        let bindingHeld = bindingIsSevenDay ? holdSevenDay : holdFiveHour
        let displayFiveHourStatus = holdFiveHour ? "allowed" : fresh.fiveHourStatus
        let displaySevenDayStatus = holdSevenDay ? "allowed" : fresh.sevenDayStatus
        let displayOverallStatus: String = bindingHeld
            ? ((displayFiveHourStatus == "throttled" || displaySevenDayStatus == "throttled") ? "throttled" : "allowed")
            : fresh.overallStatus
        let display = RateLimitUsage(
            representativeClaim: fresh.representativeClaim,
            fiveHourUtilization: holdFiveHour ? (previousDisplayed?.fiveHourUtilization ?? 0) : fresh.fiveHourUtilization,
            fiveHourReset: fresh.fiveHourReset,
            fiveHourStatus: displayFiveHourStatus,
            sevenDayUtilization: holdSevenDay ? (previousDisplayed?.sevenDayUtilization ?? 0) : fresh.sevenDayUtilization,
            sevenDayReset: fresh.sevenDayReset,
            sevenDayStatus: displaySevenDayStatus,
            overallStatus: displayOverallStatus
        )
        return SpikeConfirmedRateLimits(display: display, nearFullWindows: nearFull, heldWindows: held)
    }

    /// Generic TTL guard for optional values that ride alongside rate limits.
    nonisolated static func effectiveValue<T>(
        fresh: T?,
        stale: T?,
        lastFreshAt: Date?,
        ttl: TimeInterval,
        now: Date = .now
    ) -> T? {
        if let fresh {
            return fresh
        }
        guard let stale, let lastFreshAt else { return nil }
        return now.timeIntervalSince(lastFreshAt) <= ttl ? stale : nil
    }
}

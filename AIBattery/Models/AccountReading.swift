import Foundation

/// One account's latest quota reading from the multi-account fan-out. Windowed plans and
/// Codex credit budgets arrive as `windows`; Codex API keys as per-minute `apiLimits`.
/// Kept apart on purpose — nothing is coerced into the other shape.
struct AccountReading: Equatable, Sendable {
    var windows: RateLimitUsage?
    var apiLimits: StandardRateLimits?
    var fetchedAt: Date
    /// True when this reading did not come from a fresh fetch (served from cache or
    /// carried over after a failed fetch).
    var isCached: Bool
    var source: RateLimitSource?

    init(windows: RateLimitUsage?, apiLimits: StandardRateLimits?, fetchedAt: Date, isCached: Bool, source: RateLimitSource?) {
        self.windows = windows
        self.apiLimits = apiLimits
        self.fetchedAt = fetchedAt
        self.isCached = isCached
        self.source = source
    }

    /// Build from a fetch result; nil when the result carries neither shape.
    init?(api: APIFetchResult) {
        guard api.rateLimits != nil || api.standardLimits != nil else { return nil }
        windows = api.rateLimits
        apiLimits = api.rateLimits == nil ? api.standardLimits : nil
        fetchedAt = api.fetchedAt
        isCached = api.isCached
        source = api.rateLimitSource
    }

    /// The number a card or menu-bar slot leads with: the fuller window, the credit
    /// budget, or the busier per-minute limit. nil when nothing has been read yet or
    /// the plan has no cap to meter.
    var worstPercent: Double? {
        if let windows {
            // `isCreditBudget`, not a nil-check: a subscription plan with a purchased-
            // credit balance carries a `limit: 0` budget next to real windows and must
            // keep leading with the fuller window, not the budget's 0%.
            if windows.isCreditBudget, let budget = windows.creditBudget {
                return budget.isUncapped ? nil : budget.usedPercent
            }
            return max(windows.fiveHourPercent, windows.sevenDayPercent)
        }
        return apiLimits?.peakPercent
    }

    var isExhausted: Bool {
        if let windows {
            return windows.isThrottled || (worstPercent ?? 0) >= 100
        }
        if let apiLimits {
            return apiLimits.isRequestsExhausted || apiLimits.isTokensExhausted
        }
        return false
    }

    /// The same reading, normalised for display at `now` (expired windows cleared,
    /// rollover artifacts suppressed).
    func normalized(now: Date) -> AccountReading {
        var copy = self
        copy.windows = windows?.withClearedExpiredWindows(now: now).withClearedRolloverArtifacts(now: now)
        copy.apiLimits = apiLimits?.withClearedExpiredWindows(now: now)
        return copy
    }

    /// The reading to keep when a fetch fails: the previous one, marked cached.
    func carriedForward() -> AccountReading {
        var copy = self
        copy.isCached = true
        return copy
    }
}

/// When the per-account fan-out runs: for the menu bar (toggle) or for the overview
/// (two or more eligible accounts).
enum FanOutGate {
    static func enabled(menuBarToggle: Bool, eligibleAccountCount: Int) -> Bool {
        menuBarToggle || eligibleAccountCount >= 2
    }
}

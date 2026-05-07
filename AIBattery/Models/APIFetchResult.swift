import Foundation

/// Combined result from a single Messages API call.
struct APIFetchResult {
    let rateLimits: RateLimitUsage?
    let rateLimitSource: RateLimitSource?
    let standardLimits: StandardRateLimits?
    let profile: APIProfile?
    /// True when the response included standard public API ratelimit headers but not
    /// Claude Code's 5-hour / 7-day usage windows.
    let hasStandardRateLimitHeaders: Bool
    /// When this result was fetched (or when the cached result was originally fetched).
    let fetchedAt: Date
    /// Whether this result came from cache rather than a fresh API response.
    let isCached: Bool
    /// True when the Messages API persistently rejects the access token (≥3 consecutive
    /// 401/403 responses). Surface to the user so they can reconnect the account.
    let authError: Bool

    init(
        rateLimits: RateLimitUsage?,
        rateLimitSource: RateLimitSource? = nil,
        standardLimits: StandardRateLimits? = nil,
        profile: APIProfile?,
        hasStandardRateLimitHeaders: Bool = false,
        fetchedAt: Date = Date(),
        isCached: Bool = false,
        authError: Bool = false
    ) {
        self.rateLimits = rateLimits
        self.rateLimitSource = rateLimits == nil ? nil : (rateLimitSource ?? .anthropicAPIHeaders)
        self.standardLimits = standardLimits
        self.profile = profile
        self.hasStandardRateLimitHeaders = hasStandardRateLimitHeaders
        self.fetchedAt = fetchedAt
        self.isCached = isCached
        self.authError = authError
    }
}

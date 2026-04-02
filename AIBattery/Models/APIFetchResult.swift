import Foundation

/// Combined result from a single Messages API call.
struct APIFetchResult {
    let rateLimits: RateLimitUsage?
    let rateLimitSource: RateLimitSource?
    let profile: APIProfile?
    /// When this result was fetched (or when the cached result was originally fetched).
    let fetchedAt: Date
    /// Whether this result came from cache rather than a fresh API response.
    let isCached: Bool

    init(
        rateLimits: RateLimitUsage?,
        rateLimitSource: RateLimitSource? = nil,
        profile: APIProfile?,
        fetchedAt: Date = Date(),
        isCached: Bool = false
    ) {
        self.rateLimits = rateLimits
        self.rateLimitSource = rateLimits == nil ? nil : (rateLimitSource ?? .anthropicAPIHeaders)
        self.profile = profile
        self.fetchedAt = fetchedAt
        self.isCached = isCached
    }
}

import Foundation

/// Combined result from a single Messages API call.
struct APIFetchResult {
    let rateLimits: RateLimitUsage?
    let profile: APIProfile?
    /// When this result was fetched (or when the cached result was originally fetched).
    let fetchedAt: Date
    /// Whether this result came from cache rather than a fresh API response.
    let isCached: Bool

    init(rateLimits: RateLimitUsage?, profile: APIProfile?, fetchedAt: Date = Date(), isCached: Bool = false) {
        self.rateLimits = rateLimits
        self.profile = profile
        self.fetchedAt = fetchedAt
        self.isCached = isCached
    }
}

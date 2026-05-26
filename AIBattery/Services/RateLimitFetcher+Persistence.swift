import Foundation

// MARK: - Persistence extracted from RateLimitFetcher

//
// UserDefaults-backed cache of the most recent rate-limit snapshot per
// account, restored on launch so the menu bar fills in immediately
// instead of showing empty bars while the first poll runs.
//
// `cachedResults` and `persistKeyPrefix` live on the main type because
// they're touched by `fetch()` and `setCachedResult(...)` as well.

extension RateLimitFetcher {
    /// Wrapper for persisting rate limits + fetch timestamp.
    fileprivate struct PersistedRateLimits: Codable {
        let rateLimits: RateLimitUsage?
        let rateLimitSource: RateLimitSource?
        let standardLimits: StandardRateLimits?
        let fetchedAt: Date
    }

    /// Save rate limits to UserDefaults for instant display on next launch.
    func persistRateLimits(_ result: APIFetchResult, accountId: String) {
        guard result.rateLimits != nil || result.standardLimits != nil else { return }
        let key = Self.persistKeyPrefix + accountId
        let persisted = PersistedRateLimits(
            rateLimits: result.rateLimits,
            rateLimitSource: result.rateLimitSource,
            standardLimits: result.standardLimits,
            fetchedAt: result.fetchedAt
        )
        if let data = try? JSONEncoder().encode(persisted) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    /// Restore persisted rate limits into the in-memory cache on launch.
    /// Always restores — stale data is better than empty bars on wake from sleep.
    /// Fresh fetches replace stale data naturally on the first successful poll.
    func restorePersistedRateLimits() {
        let defaults = UserDefaults.standard
        let prefix = Self.persistKeyPrefix
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            let accountId = String(key.dropFirst(prefix.count))
            guard let data = defaults.data(forKey: key),
                  let persisted = try? JSONDecoder().decode(PersistedRateLimits.self, from: data) else {
                defaults.removeObject(forKey: key)
                continue
            }
            // Discard cache entries with future fetchedAt (system clock went backward)
            let fetchedAt = persisted.fetchedAt <= Date() ? persisted.fetchedAt : Date()
            // Clear expired windows so a stale "throttled" flag from before a long
            // absence (e.g. user returns from leave) doesn't display as if they
            // hit the limit. The window has rolled over; status must reset.
            let normalizedRateLimits = persisted.rateLimits?.withClearedExpiredWindows()
            cachedResults[accountId] = APIFetchResult(
                rateLimits: normalizedRateLimits,
                rateLimitSource: persisted.rateLimitSource,
                standardLimits: persisted.standardLimits,
                profile: nil,
                fetchedAt: fetchedAt,
                isCached: true
            )
        }
    }
}

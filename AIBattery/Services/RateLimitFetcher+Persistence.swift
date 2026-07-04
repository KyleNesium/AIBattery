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
    /// `defaults` is injectable for tests (precedent: `NotificationManager.migrateAlertKeys`).
    func persistRateLimits(_ result: APIFetchResult, accountId: String, defaults: UserDefaults = .standard) {
        guard result.rateLimits != nil || result.standardLimits != nil else { return }
        let key = Self.persistKeyPrefix + accountId
        let persisted = PersistedRateLimits(
            rateLimits: result.rateLimits,
            rateLimitSource: result.rateLimitSource,
            standardLimits: result.standardLimits,
            fetchedAt: result.fetchedAt
        )
        if let data = try? JSONEncoder().encode(persisted) {
            defaults.set(data, forKey: key)
        }
    }

    /// Replace the cached (and persisted) rate limits for an account with a corrected
    /// value, preserving every other field (profile, source, standard limits, fetchedAt).
    ///
    /// Called by `UsageViewModel.refresh()` when the spike filter HOLDS an unconfirmed
    /// near-full reading: `fetch()` already wrote the raw server value to the cache and
    /// disk before the filter ran, so without this write-back the glitch would survive
    /// as the "last known good" fallback — and a later instant-paint (wake, cold start,
    /// launch restore) would re-display it, or seed it as `previousDisplayed` where a
    /// repeat glitch could confirm it. "Rather show stale than a false used value"
    /// applies to what we persist, too.
    ///
    /// No-op when the account has no cached entry (nothing to correct).
    func overrideCachedRateLimits(_ rateLimits: RateLimitUsage, accountId: String, defaults: UserDefaults = .standard) {
        guard let cached = cachedResults[accountId] else { return }
        let corrected = APIFetchResult(
            rateLimits: rateLimits,
            rateLimitSource: cached.rateLimitSource,
            standardLimits: cached.standardLimits,
            profile: cached.profile,
            hasStandardRateLimitHeaders: cached.hasStandardRateLimitHeaders,
            fetchedAt: cached.fetchedAt,
            isCached: cached.isCached,
            authError: cached.authError
        )
        cachedResults[accountId] = corrected
        persistRateLimits(corrected, accountId: accountId, defaults: defaults)
    }

    /// Restore persisted rate limits into the in-memory cache on launch.
    /// Always restores — stale data is better than empty bars on wake from sleep.
    /// Fresh fetches replace stale data naturally on the first successful poll.
    /// Self-heals: a blob that fails to decode is removed so it cannot wedge
    /// every subsequent launch; other accounts' entries still restore.
    func restorePersistedRateLimits(defaults: UserDefaults = .standard) {
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
            // Also clear rollover artifacts so a near-full reading on a just-reset window
            // isn't seeded into the snapshot as the stale fallback (the value the 24h TTL
            // then holds and re-displays as "Limit reached" on the next header-less poll).
            let normalizedRateLimits = persisted.rateLimits?
                .withClearedExpiredWindows()
                .withClearedRolloverArtifacts()
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

    /// Move a pending account's cached + persisted rate limits to its resolved org id,
    /// then drop the pending entry. Called from `OAuthManager.resolveAccountIdentity`
    /// alongside `TokenLedger.migrate`, so a `pending-<uuid>`'s first-fetch blob follows
    /// the account instead of orphaning under the dead pending key (where it would be
    /// reloaded every launch and could surface a stale "Limit reached" — the v2.5.0 bug).
    ///
    /// The resolved id wins if it already has data (a fresh fetch landed first); otherwise
    /// the pending blob carries over. The pending key is always removed.
    func migrate(from oldId: String, to newId: String, defaults: UserDefaults = .standard) {
        guard oldId != newId else { return }
        if cachedResults[newId] == nil, let old = cachedResults[oldId] {
            cachedResults[newId] = old
        }
        cachedResults.removeValue(forKey: oldId)

        let oldKey = Self.persistKeyPrefix + oldId
        let newKey = Self.persistKeyPrefix + newId
        if defaults.data(forKey: newKey) == nil, let blob = defaults.data(forKey: oldKey) {
            defaults.set(blob, forKey: newKey)
        }
        defaults.removeObject(forKey: oldKey)
    }

    /// Drop cached + persisted rate limits for accounts the user no longer has —
    /// orphaned `pending-<uuid>` ids left by pre-migration identity resolutions and
    /// removed accounts. Called once on launch with the live account ids (mirrors
    /// `TokenLedger.pruneAccounts`).
    ///
    /// No-op when `liveAccountIds` is empty so a logged-out / fresh-launch transient
    /// can never wipe a legitimately-cached account's bars.
    func pruneAccounts(keeping liveAccountIds: Set<String>, defaults: UserDefaults = .standard) {
        guard !liveAccountIds.isEmpty else { return }
        cachedResults = cachedResults.filter { liveAccountIds.contains($0.key) }
        let prefix = Self.persistKeyPrefix
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            let accountId = String(key.dropFirst(prefix.count))
            if !liveAccountIds.contains(accountId) {
                defaults.removeObject(forKey: key)
            }
        }
    }
}

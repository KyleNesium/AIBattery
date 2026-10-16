import Foundation

// MARK: - Multi-account fan-out: dependency seams + orchestration

//
// The "Show all accounts in menu bar" feature fetches every authenticated account's
// rate limits in parallel. That orchestration reaches two singletons —
// `RateLimitFetcher.shared` (network) and `OAuthManager.shared` (account list +
// per-account tokens). Hard singletons made the orchestration's decision logic
// (seed dedup, toggle-off clearing, non-pending+authenticated filtering) impossible
// to unit-test without real network + Keychain.
//
// `MultiAccountFanOut.resolve` is the orchestration, pulled out of `UsageViewModel`
// so it can be driven end-to-end (including the concurrent fetch) with mocks. It is
// deliberately NOT a method on `UsageViewModel`: that type's init starts a polling
// timer + file watchers, so constructing one in a test would race real network work.
//
// Both protocols are `@MainActor` (the conforming singletons are `@MainActor`) and
// `Sendable` so an existential can be captured by the `@Sendable` task-group closures
// inside `resolve`.

/// Network surface the fan-out needs: fetch one account's rate limits.
@MainActor
protocol RateLimitFetching: Sendable {
    func fetch(accessToken: String, accountId: String) async -> APIFetchResult
}

/// Account surface the fan-out needs: which accounts to display, and their tokens.
@MainActor
protocol MultiAccountTokenProviding: Sendable {
    /// Account IDs eligible for the multi-account fan-out (menu bar + overview), in
    /// display order: non-pending (identity resolved) AND currently authenticated.
    func multiAccountDisplayIDs() -> [String]
    /// Current access token for an account, refreshing if needed. `nil` if unavailable.
    func accessToken(for accountId: String) async -> String?
}

extension RateLimitFetcher: RateLimitFetching {}

extension OAuthManager: MultiAccountTokenProviding {
    func multiAccountDisplayIDs() -> [String] {
        AccountStore.multiAccountDisplayIDs(
            accounts: accountStore.accounts,
            isAuthenticated: { self.isAuthenticated(accountId: $0) }
        )
    }

    func accessToken(for accountId: String) async -> String? {
        await getAccessToken(for: accountId)
    }
}

extension AccountStore {
    /// Pure filter for the multi-account menu bar's eligible account IDs:
    /// non-pending (real org ID) AND authenticated, preserving store order.
    ///
    /// Pure given the auth predicate, so it's testable without OAuthManager/Keychain.
    /// Single source of truth shared by the fan-out candidate set and the menu-bar
    /// `order` (both via `OAuthManager.multiAccountDisplayIDs()`) so the two cannot
    /// drift — the menu bar must not render a "—" slot for an account the fan-out has
    /// already filtered out (e.g. an account that resolved to a real org ID but is now
    /// signed out).
    static func multiAccountDisplayIDs(
        accounts: [AccountRecord],
        isAuthenticated: (String) -> Bool
    ) -> [String] {
        displayOrdered(accounts)
            .filter { !$0.isPendingIdentity }
            // API-key accounts are eligible: the fan-out carries their per-minute limits
            // as `AccountReading.apiLimits` (menu-bar slot + overview card).
            .filter { isAuthenticated($0.id) }
            .map(\.id)
    }
}

/// Stateless orchestration for the multi-account fan-out. See file header.
@MainActor
enum MultiAccountFanOut {
    /// Providers (other than the active one) that have an eligible account, so the
    /// overview can show a status dot on every card. Each `StatusChecker` instance
    /// keeps its own cache + exponential backoff, so polling both per cycle is safe.
    nonisolated static func otherProviders(eligible: [AccountRecord], active: AIProvider) -> [AIProvider] {
        let providers = Set(eligible.map(\.provider)).subtracting([active])
        return AIProvider.allCases.filter { providers.contains($0) }
    }

    /// Resolve the per-account readings for the multi-account menu bar and the overview.
    ///
    /// Net cost is **N requests for N accounts, not N+1**: `RateLimitFetcher.fetch`
    /// does not short-circuit on cache, so the active account that `refresh()` just
    /// fetched is passed back via `seed` and excluded from the fan-out rather than
    /// re-fetched.
    ///
    /// - Parameters:
    ///   - enabled: `FanOutGate.enabled(...)` — the menu-bar toggle OR ≥ 2 eligible accounts.
    ///   - seed: the active account's just-fetched reading, or `nil` when the active
    ///     fetch was cached/absent. Injected into the result without a network call.
    ///     Carries either shape, so an API-key account (whose probe reports per-minute
    ///     `apiLimits` and never `windows`) seeds just like a windowed one.
    ///   - excluding: the active account's id. ALWAYS dropped from the fan-out, seed or
    ///     no seed: re-fetching it would issue a second request on the same cycle — a
    ///     billed `/v1/responses` probe for an API key, or a retry against the very
    ///     endpoint that just served the active fetch from cache. With no seed, its
    ///     `previous` reading is carried forward instead.
    ///   - previous: the caller's current map. An account whose fetch fails keeps its
    ///     previous reading, marked cached, so a card never blanks out between polls.
    ///   - provider: account list + per-account tokens.
    ///   - fetcher: per-account rate-limit network fetch.
    ///   - now: injected clock for rollover-artifact normalization (testability).
    /// - Returns: `nil` when disabled OR there is nothing to fetch and no seed (caller
    ///   clears its map); otherwise the normalized per-account map.
    static func resolve(
        enabled: Bool,
        seed: (accountId: String, reading: AccountReading)?,
        excluding activeAccountId: String? = nil,
        previous: [String: AccountReading] = [:],
        provider: MultiAccountTokenProviding,
        fetcher: RateLimitFetching,
        now: Date = .now
    ) async -> [String: AccountReading]? {
        guard enabled else { return nil }

        let skipped = Set([seed?.accountId, activeAccountId].compactMap { $0 })
        let idsToFetch = provider.multiAccountDisplayIDs().filter { !skipped.contains($0) }

        var collected: [String: AccountReading] = [:]
        if let seed {
            collected[seed.accountId] = seed.reading
        } else if let activeAccountId, let old = previous[activeAccountId] {
            // Excluded but unseeded (the active fetch was cached): keep showing the last
            // reading rather than spending a second request to re-learn it.
            collected[activeAccountId] = old.carriedForward()
        }

        if idsToFetch.isEmpty, collected.isEmpty {
            return nil
        }

        if !idsToFetch.isEmpty {
            let fetched = await withTaskGroup(of: (String, AccountReading?).self) { group -> [String: AccountReading] in
                for id in idsToFetch {
                    group.addTask {
                        // A skipped account renders as "—" in the menu bar; without
                        // these lines there is zero diagnostic for WHY.
                        guard let token = await provider.accessToken(for: id) else {
                            AppLogger.network.info("Fan-out skipped \(id, privacy: .public): no access token")
                            return (id, nil)
                        }
                        let api = await fetcher.fetch(accessToken: token, accountId: id)
                        let reading = AccountReading(api: api)
                        if reading == nil {
                            AppLogger.network.info("Fan-out skipped \(id, privacy: .public): fetch returned no limits")
                        }
                        return (id, reading)
                    }
                }
                var inner: [String: AccountReading] = [:]
                for await (id, reading) in group {
                    if let reading {
                        inner[id] = reading
                    }
                }
                return inner
            }
            for id in idsToFetch {
                if let reading = fetched[id] {
                    collected[id] = reading
                } else if let old = previous[id] {
                    // Keep the last reading rather than dropping the slot: a transient
                    // failure must not blank a card or a menu-bar slot between polls.
                    collected[id] = old.carriedForward()
                }
            }
        }

        // Normalize per-account results (mirrors the active-account path in refresh()):
        // clear expired windows first — a failed fetch falls back to cache, and a cached
        // throttle whose reset passed during an absence must not keep counting as a live
        // throttle in the menu bar — then suppress rollover artifacts so a just-reset
        // window doesn't show a stale near-full reading.
        return collected.mapValues { $0.normalized(now: now) }
    }
}

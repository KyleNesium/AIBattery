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
    /// Account IDs eligible for the multi-account menu bar, in display order:
    /// non-pending (identity resolved) AND currently authenticated.
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
        accounts
            .filter { !$0.isPendingIdentity }
            .filter { isAuthenticated($0.id) }
            .map(\.id)
    }
}

/// Stateless orchestration for the multi-account fan-out. See file header.
@MainActor
enum MultiAccountFanOut {
    /// Resolve the per-account rate-limit map for the multi-account menu bar.
    ///
    /// Net cost is **N requests for N accounts, not N+1**: `RateLimitFetcher.fetch`
    /// does not short-circuit on cache, so the active account that `refresh()` just
    /// fetched is passed back via `seed` and excluded from the fan-out rather than
    /// re-fetched.
    ///
    /// - Parameters:
    ///   - enabled: the `aibattery_showAllAccountsInMenuBar` toggle.
    ///   - seed: the active account's just-fetched `(id, rateLimits)`, or `nil` when
    ///     the active fetch was cached/absent. Injected into the result without a
    ///     network call; that account is dropped from the fan-out.
    ///   - provider: account list + per-account tokens.
    ///   - fetcher: per-account rate-limit network fetch.
    ///   - now: injected clock for rollover-artifact normalization (testability).
    /// - Returns: `nil` when the toggle is off OR there is nothing to fetch and no
    ///   seed (caller clears its map); otherwise the normalized per-account map.
    static func resolve(
        enabled: Bool,
        seed: (accountId: String, rateLimits: RateLimitUsage)?,
        provider: MultiAccountTokenProviding,
        fetcher: RateLimitFetching,
        now: Date = .now
    ) async -> [String: RateLimitUsage]? {
        guard enabled else { return nil }

        let idsToFetch = provider.multiAccountDisplayIDs().filter { $0 != seed?.accountId }
        if idsToFetch.isEmpty, seed == nil { return nil }

        var collected: [String: RateLimitUsage] = [:]
        if let seed { collected[seed.accountId] = seed.rateLimits }

        if !idsToFetch.isEmpty {
            let fetched = await withTaskGroup(of: (String, RateLimitUsage?).self) { group -> [String: RateLimitUsage] in
                for id in idsToFetch {
                    group.addTask {
                        guard let token = await provider.accessToken(for: id) else {
                            return (id, nil)
                        }
                        let api = await fetcher.fetch(accessToken: token, accountId: id)
                        return (id, api.rateLimits)
                    }
                }
                var inner: [String: RateLimitUsage] = [:]
                for await (id, limits) in group {
                    if let limits { inner[id] = limits }
                }
                return inner
            }
            for (id, limits) in fetched {
                collected[id] = limits
            }
        }

        // Suppress per-account rollover artifacts so a just-reset window doesn't show a
        // stale near-full reading (mirrors the active-account path in refresh()).
        return collected.mapValues { $0.withClearedRolloverArtifacts(now: now) }
    }
}

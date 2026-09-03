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
        displayOrdered(accounts)
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
        if idsToFetch.isEmpty, seed == nil {
            return nil
        }

        var collected: [String: RateLimitUsage] = [:]
        if let seed {
            collected[seed.accountId] = seed.rateLimits
        }

        if !idsToFetch.isEmpty {
            let fetched = await withTaskGroup(of: (String, RateLimitUsage?).self) { group -> [String: RateLimitUsage] in
                for id in idsToFetch {
                    group.addTask {
                        // A skipped account renders as "—" in the menu bar; without
                        // these lines there is zero diagnostic for WHY.
                        guard let token = await provider.accessToken(for: id) else {
                            AppLogger.network.info("Fan-out skipped \(id, privacy: .public): no access token")
                            return (id, nil)
                        }
                        let api = await fetcher.fetch(accessToken: token, accountId: id)
                        if api.rateLimits == nil {
                            AppLogger.network.info("Fan-out skipped \(id, privacy: .public): fetch returned no rate limits")
                        }
                        return (id, api.rateLimits)
                    }
                }
                var inner: [String: RateLimitUsage] = [:]
                for await (id, limits) in group {
                    if let limits {
                        inner[id] = limits
                    }
                }
                return inner
            }
            for (id, limits) in fetched {
                collected[id] = limits
            }
        }

        // Normalize per-account results (mirrors the active-account path in refresh()):
        // clear expired windows first — a failed fetch falls back to cache, and a cached
        // throttle whose reset passed during an absence must not keep counting as a live
        // throttle in the menu bar — then suppress rollover artifacts so a just-reset
        // window doesn't show a stale near-full reading.
        return collected.mapValues {
            $0.withClearedExpiredWindows(now: now).withClearedRolloverArtifacts(now: now)
        }
    }
}

// MARK: - Provider dispatch

extension CodexRateLimitFetcher: RateLimitFetching {}

/// Routes a per-account rate-limit fetch to the provider's fetcher.
/// The seams stay protocol-typed so MultiAccountFanOut tests keep working
/// with pure mocks.
@MainActor
struct ProviderDispatchingFetcher: RateLimitFetching {
    let providerForAccount: (String) -> AIProvider
    let claude: any RateLimitFetching
    let codex: any RateLimitFetching

    func fetch(accessToken: String, accountId: String) async -> APIFetchResult {
        switch providerForAccount(accountId) {
        case .claude: await claude.fetch(accessToken: accessToken, accountId: accountId)
        case .codex: await codex.fetch(accessToken: accessToken, accountId: accountId)
        }
    }

    /// Production wiring: unknown ids default to .claude (pre-provider behavior).
    static func live(accountStore: AccountStore) -> ProviderDispatchingFetcher {
        ProviderDispatchingFetcher(
            providerForAccount: { id in accountStore.accounts.first { $0.id == id }?.provider ?? .claude },
            claude: RateLimitFetcher.shared,
            codex: CodexRateLimitFetcher.shared
        )
    }
}

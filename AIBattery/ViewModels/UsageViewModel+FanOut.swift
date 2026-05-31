import Foundation

// MARK: - Multi-account fan-out extracted from UsageViewModel

//
// Triggered by the "Show all accounts in menu bar" preference. The toggle
// observer in `init` debounces `UserDefaults.didChangeNotification` and
// then calls `scheduleFanOut()`. The single in-flight task is tracked via
// `pendingFanOut` (declared on the main type) so back-to-back triggers
// coalesce instead of stacking N concurrent fan-outs.

extension UsageViewModel {
    /// Coalesce repeated fan-out triggers — caller may fire many close together
    /// (e.g. when settings open and several @AppStorage writes flush).
    func scheduleFanOut() {
        pendingFanOut?.cancel()
        pendingFanOut = Task { [weak self] in
            await self?.fetchAllAccounts()
        }
    }

    /// Fan-out: fetch rate limits for every authenticated, identity-resolved account.
    /// Runs only when the "show all accounts" toggle is on. Idempotent: clears state if off.
    ///
    /// - Parameter seed: optional `(accountId, rateLimits)` pair to inject into the
    ///   result map without re-fetching. Used by `refresh()` to reuse the active
    ///   account's just-fetched data — `RateLimitFetcher.fetch` does NOT short-circuit
    ///   on cache, so without seeding we'd issue an extra network call for the active
    ///   account every refresh cycle (N+1 total instead of N).
    func fetchAllAccounts(seed: (accountId: String, rateLimits: RateLimitUsage)? = nil) async {
        let showAll = UserDefaults.standard.bool(forKey: UserDefaultsKeys.showAllAccountsInMenuBar)
        guard showAll else {
            if !perAccountRateLimits.isEmpty {
                perAccountRateLimits = [:]
            }
            return
        }
        let oauth = OAuthManager.shared
        let candidates = oauth.accountStore.accounts
            .filter { !$0.isPendingIdentity }
            .filter { oauth.isAuthenticated(accountId: $0.id) }
        // Skip any account already provided by seed — we already have fresh data
        // for it and re-fetching would cost an extra API call per cycle.
        let recordsToFetch = candidates.filter { $0.id != seed?.accountId }

        // If nothing to fetch and nothing to seed, treat as empty.
        if recordsToFetch.isEmpty && seed == nil {
            if !perAccountRateLimits.isEmpty { perAccountRateLimits = [:] }
            return
        }

        var collected: [String: RateLimitUsage] = [:]
        if let seed { collected[seed.accountId] = seed.rateLimits }

        if !recordsToFetch.isEmpty {
            // Extract just the IDs (Sendable Strings) before crossing into the
            // task group — capturing a MainActor-isolated `oauth` or
            // `AccountRecord` in @Sendable closures would race against the
            // actor that owns them.
            let idsToFetch = recordsToFetch.map(\.id)
            let fetched = await withTaskGroup(of: (String, RateLimitUsage?).self) { group -> [String: RateLimitUsage] in
                for id in idsToFetch {
                    group.addTask {
                        guard let token = await OAuthManager.shared.getAccessToken(for: id) else {
                            return (id, nil)
                        }
                        let api = await RateLimitFetcher.shared.fetch(accessToken: token, accountId: id)
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

        // Suppress per-account rollover artifacts so a just-reset window doesn't show
        // a stale near-full reading in the multi-account menu bar (mirrors the active
        // account path in refresh()).
        perAccountRateLimits = collected.mapValues { $0.withClearedRolloverArtifacts() }
    }
}

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
    /// Thin wrapper over `MultiAccountFanOut.resolve` — the orchestration lives there
    /// (not here) so it can be unit-tested end-to-end with mock dependencies without
    /// constructing a `UsageViewModel` (whose init starts timers + watchers).
    ///
    /// - Parameter seed: optional `(accountId, rateLimits)` pair to inject into the
    ///   result map without re-fetching. Used by `refresh()` to reuse the active
    ///   account's just-fetched data — `RateLimitFetcher.fetch` does NOT short-circuit
    ///   on cache, so without seeding we'd issue an extra network call for the active
    ///   account every refresh cycle (N+1 total instead of N).
    func fetchAllAccounts(seed: (accountId: String, rateLimits: RateLimitUsage)? = nil) async {
        let enabled = UserDefaults.standard.bool(forKey: UserDefaultsKeys.showAllAccountsInMenuBar)
        let resolved = await MultiAccountFanOut.resolve(
            enabled: enabled,
            seed: seed,
            provider: OAuthManager.shared,
            fetcher: RateLimitFetcher.shared
        )
        if let resolved {
            perAccountRateLimits = resolved
        } else if !perAccountRateLimits.isEmpty {
            // Toggle off, or nothing to fetch and no seed — clear stale data.
            perAccountRateLimits = [:]
        }
    }
}

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
    /// Runs when the "show all accounts" toggle is on OR there are ≥ 2 eligible accounts
    /// (`FanOutGate`) — the overview needs every account's reading. Idempotent: clears
    /// state when disabled.
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
    func fetchAllAccounts(
        seed: (accountId: String, reading: AccountReading)? = nil,
        excluding activeAccountId: String? = nil
    ) async {
        // Single-writer rule: whoever started last owns `perAccountReadings`. Anything
        // that finishes after a newer call began is dropped — mirrors
        // `shouldApplyFetchResult` on the refresh path.
        fanOutGeneration &+= 1
        let generation = fanOutGeneration
        let toggle = UserDefaults.standard.bool(forKey: UserDefaultsKeys.showAllAccountsInMenuBar)
        let eligible = OAuthManager.shared.multiAccountDisplayIDs().count
        let resolved = await MultiAccountFanOut.resolve(
            enabled: FanOutGate.enabled(menuBarToggle: toggle, eligibleAccountCount: eligible),
            seed: seed,
            excluding: activeAccountId,
            previous: perAccountReadings,
            provider: OAuthManager.shared,
            fetcher: ProviderDispatchingFetcher.live(accountStore: OAuthManager.shared.accountStore)
        )
        guard generation == fanOutGeneration else { return } // a newer call owns the map
        if let resolved {
            perAccountReadings = resolved
        } else if !perAccountReadings.isEmpty {
            // Disabled, or nothing to fetch and no seed — clear stale data.
            perAccountReadings = [:]
        }
        await fetchOtherProviderStatuses()
        await aggregateOtherProviders()
    }

    /// Aggregate the local session logs of every provider that has an eligible account
    /// but isn't the active one, so the overview's cards all show their window token
    /// totals — not just the active provider's. Each provider has its own aggregator
    /// with a reader cache and a redundant-aggregation fingerprint, so a cycle where
    /// nothing changed costs almost nothing.
    private func aggregateOtherProviders() async {
        let store = OAuthManager.shared.accountStore
        let eligible = OAuthManager.shared.multiAccountDisplayIDs().compactMap { store.account(id: $0) }
        let active = store.activeAccount?.provider ?? .claude
        for provider in MultiAccountFanOut.otherProviders(eligible: eligible, active: active) {
            // Attribute to that provider's first eligible account: it decides whether
            // the cost rows read as a bill (API-key) or as subscription value.
            let accountId = eligible.first { $0.provider == provider }?.id
            // Provider-wide by construction: cards show the provider's total, never one
            // account's share.
            _ = await aggregateOffMain(
                rateLimits: nil,
                accountId: accountId,
                provider: provider,
                rateLimitsFresh: false,
                applySideEffects: false, // never touch the active account's probe state
                providerWide: true
            )
        }
    }

    /// Poll the status feed of every provider that has an eligible account but isn't the
    /// active one, so the overview's cards all carry a status dot. `refresh()` already
    /// stores the active provider's status. Each `StatusChecker` instance keeps its own
    /// cache and exponential backoff, so this adds no pressure on a failing feed.
    private func fetchOtherProviderStatuses() async {
        let store = OAuthManager.shared.accountStore
        let eligible = OAuthManager.shared.multiAccountDisplayIDs().compactMap { store.account(id: $0) }
        let active = store.activeAccount?.provider ?? .claude
        for provider in MultiAccountFanOut.otherProviders(eligible: eligible, active: active) {
            providerStatuses[provider] = await StatusChecker.shared(for: provider).fetchStatus()
        }
    }
}

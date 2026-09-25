import Foundation

// MARK: - Provider routing extracted from UsageViewModel

//
// Every place the view model has to choose between the Claude and Codex
// machinery lives here: which aggregator, which fetcher cache, which fetch
// (ChatGPT OAuth vs API-key probe), which status feed, and the Codex-only
// plan-name sync. `refresh()` itself stays provider-blind apart from resolving
// the active account's provider once and passing it through.

extension UsageViewModel {
    func aggregator(for provider: AIProvider) -> UsageAggregator {
        provider == .codex ? codexAggregator : aggregator
    }

    /// Provider of an account in the store (Claude when unknown — legacy records).
    func provider(ofAccount accountId: String?) -> AIProvider {
        OAuthManager.shared.accountStore.provider(of: accountId)
    }

    /// Write a spike-corrected reading back to the provider's fetcher cache.
    static func overrideCachedRateLimits(_ rateLimits: RateLimitUsage, for provider: AIProvider, accountId: String) {
        if provider == .codex {
            CodexRateLimitFetcher.shared.overrideCachedRateLimits(rateLimits, accountId: accountId)
        } else {
            RateLimitFetcher.shared.overrideCachedRateLimits(rateLimits, accountId: accountId)
        }
    }

    /// The right fetcher's cached result for an account — each provider persists under
    /// its own key prefix, so asking the wrong fetcher yields empty bars.
    static func cachedResult(for provider: AIProvider, accountId: String) -> APIFetchResult {
        provider == .codex
            ? CodexRateLimitFetcher.shared.cachedOrEmpty(accountId: accountId)
            : RateLimitFetcher.shared.cachedOrEmpty(accountId: accountId)
    }

    func fetchAPIData(
        oauthManager: OAuthManager,
        accountId: String?
    ) async -> (APIFetchResult, ClaudeSystemStatus) {
        // Pin the token to the account this fetch was filed under. Resolving the
        // ACTIVE account's token at await-time would, after a mid-poll account
        // switch, send account B's token on a request cached and persisted under
        // account A's key.
        let accessToken: String? = if let id = accountId {
            await oauthManager.getAccessToken(for: id)
        } else {
            nil
        }

        let provider = provider(ofAccount: accountId)
        async let fetchedStatus = StatusChecker.shared(for: provider).fetchStatus()

        let isAPIKey = oauthManager.accountStore.account(id: accountId)?.isAPIKeyAccount ?? false
        let api: APIFetchResult = if let token = accessToken, let id = accountId {
            switch (provider, isAPIKey) {
            case (.codex, true): await CodexRateLimitFetcher.shared.fetchAPIKeyLimits(apiKey: token, accountId: id)
            case (.codex, false): await CodexRateLimitFetcher.shared.fetch(accessToken: token, accountId: id)
            case (.claude, _): await RateLimitFetcher.shared.fetch(accessToken: token, accountId: id)
            }
        } else {
            APIFetchResult(rateLimits: nil, profile: nil)
        }

        return await (api, fetchedStatus)
    }

    func resolveAccountIdentity(
        oauthManager: OAuthManager,
        accountId: String?,
        api: APIFetchResult
    ) {
        guard let id = accountId else { return }
        guard let account = oauthManager.accountStore.account(id: id) else { return }
        // Codex identities are resolved at auth time (real account id from the JWT) —
        // the Anthropic pending-identity machinery (temp-UUID -> org-ID migration)
        // must never touch them. Only the plan name is synced from the usage payload.
        guard account.provider == .claude else {
            if let plan = api.planType, !api.isCached, account.billingType != plan {
                oauthManager.updateAccountMetadata(accountId: id, billingType: plan)
            }
            return
        }

        if account.isPendingIdentity {
            if let orgId = api.profile?.organizationId {
                oauthManager.resolveAccountIdentity(tempId: id, realOrgId: orgId)
            } else if Date().timeIntervalSince(account.addedAt) > 3_600 {
                errorMessage = "Account identity could not be confirmed. Try removing and re-adding this account."
            }
        }
    }
}

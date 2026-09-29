import Foundation

extension CodexRateLimitFetcher: RateLimitFetching {}

/// Routes a per-account rate-limit fetch to the right fetcher for that account:
/// Claude → `RateLimitFetcher`; Codex ChatGPT → `CodexRateLimitFetcher.fetch`;
/// Codex API key → the OpenAI probe (`fetchAPIKeyLimits`) — an API key must never be
/// sent to the ChatGPT usage endpoint (guaranteed 401, wrong host). The seams stay
/// closure/protocol-typed so `MultiAccountFanOut` tests keep working with pure mocks.
@MainActor
struct ProviderDispatchingFetcher: RateLimitFetching {
    let providerForAccount: (String) -> AIProvider
    let isAPIKeyAccount: (String) -> Bool
    let claude: any RateLimitFetching
    let codex: any RateLimitFetching
    /// `(apiKey, accountId)` → result; production wiring is `fetchAPIKeyLimits`.
    let codexAPIKey: (String, String) async -> APIFetchResult

    func fetch(accessToken: String, accountId: String) async -> APIFetchResult {
        switch providerForAccount(accountId) {
        case .claude:
            return await claude.fetch(accessToken: accessToken, accountId: accountId)
        case .codex:
            if isAPIKeyAccount(accountId) {
                return await codexAPIKey(accessToken, accountId)
            }
            return await codex.fetch(accessToken: accessToken, accountId: accountId)
        }
    }

    /// Production wiring: unknown ids default to .claude (pre-provider behavior).
    static func live(accountStore: AccountStore) -> ProviderDispatchingFetcher {
        ProviderDispatchingFetcher(
            providerForAccount: { accountStore.provider(of: $0) },
            isAPIKeyAccount: { accountStore.account(id: $0)?.isAPIKeyAccount ?? false },
            claude: RateLimitFetcher.shared,
            codex: CodexRateLimitFetcher.shared,
            codexAPIKey: { key, id in await CodexRateLimitFetcher.shared.fetchAPIKeyLimits(apiKey: key, accountId: id) }
        )
    }
}

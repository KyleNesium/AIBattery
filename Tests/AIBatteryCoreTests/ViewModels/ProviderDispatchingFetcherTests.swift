import Foundation
import Testing
@testable import AIBatteryCore

// Coverage for `ProviderDispatchingFetcher` — the seam that routes a
// per-account rate-limit fetch to the Claude or Codex fetcher based on the
// account's `AIProvider`. Pure routing logic against protocol-typed mocks,
// so it doesn't touch the real network singletons.

@Suite("ProviderDispatchingFetcher")
@MainActor
struct ProviderDispatchingFetcherTests {
    /// Mock fetcher that records which account ids it served.
    @MainActor
    final class SpyFetcher: RateLimitFetching {
        var served: [String] = []
        let tag: RateLimitSource
        init(tag: RateLimitSource) {
            self.tag = tag
        }

        func fetch(accessToken: String, accountId: String) async -> APIFetchResult {
            served.append(accountId)
            return APIFetchResult(rateLimits: nil, rateLimitSource: tag, profile: nil)
        }
    }

    @Test func routesByProvider() async {
        let claude = SpyFetcher(tag: .oauthUsageEndpoint)
        let codex = SpyFetcher(tag: .codexUsageEndpoint)
        let dispatcher = ProviderDispatchingFetcher(
            providerForAccount: { $0.hasPrefix("x") ? .codex : .claude },
            isAPIKeyAccount: { _ in false },
            claude: claude, codex: codex,
            codexAPIKey: { _, _ in APIFetchResult(rateLimits: nil, profile: nil) }
        )
        _ = await dispatcher.fetch(accessToken: "t", accountId: "c1")
        _ = await dispatcher.fetch(accessToken: "t", accountId: "x1")
        _ = await dispatcher.fetch(accessToken: "t", accountId: "x2")
        #expect(claude.served == ["c1"])
        #expect(codex.served == ["x1", "x2"])
    }

    /// An API-key account's "token" IS the key — it must go to the OpenAI probe, never
    /// to the ChatGPT usage endpoint (guaranteed 401 + key sent to the wrong host).
    @Test func apiKeyAccounts_routeToTheProbe_notTheChatGPTFetcher() async {
        let claude = SpyFetcher(tag: .oauthUsageEndpoint)
        let codex = SpyFetcher(tag: .codexUsageEndpoint)
        let probed = ServedBox()
        let dispatcher = ProviderDispatchingFetcher(
            providerForAccount: { _ in .codex },
            isAPIKeyAccount: { $0.hasPrefix("openai-api-") },
            claude: claude, codex: codex,
            codexAPIKey: { key, id in
                probed.record("\(id):\(key)")
                return APIFetchResult(rateLimits: nil, profile: nil, planType: "api")
            }
        )
        let result = await dispatcher.fetch(accessToken: "sk-secret", accountId: "openai-api-abc")
        _ = await dispatcher.fetch(accessToken: "eyJ.jwt", accountId: "chatgpt-acct")
        #expect(probed.served == ["openai-api-abc:sk-secret"])
        #expect(codex.served == ["chatgpt-acct"])
        #expect(claude.served.isEmpty)
        #expect(result.planType == "api")
    }

    @MainActor
    final class ServedBox {
        var served: [String] = []
        func record(_ s: String) {
            served.append(s)
        }
    }
}

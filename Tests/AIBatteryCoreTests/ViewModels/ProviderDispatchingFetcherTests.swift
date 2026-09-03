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
            claude: claude, codex: codex
        )
        _ = await dispatcher.fetch(accessToken: "t", accountId: "c1")
        _ = await dispatcher.fetch(accessToken: "t", accountId: "x1")
        _ = await dispatcher.fetch(accessToken: "t", accountId: "x2")
        #expect(claude.served == ["c1"])
        #expect(codex.served == ["x1", "x2"])
    }
}

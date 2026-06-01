import Foundation
import Testing
@testable import AIBatteryCore

// End-to-end coverage for the multi-account menu bar fan-out orchestration
// (`MultiAccountFanOut.resolve`) and its shared eligible-account filter
// (`AccountStore.multiAccountDisplayIDs`). The orchestration runs the real
// concurrent `TaskGroup` against mock dependencies, so seed dedup, toggle-off
// clearing, and missing-token handling are exercised for real — not just the
// pure render path that `MenuBarMultiAccountTextTests` already covers.

@MainActor
@Suite("MultiAccountFanOut")
struct MultiAccountFanOutTests {
    // MARK: - Mocks

    /// Records every account ID it is asked to fetch, so tests can assert seed dedup.
    @MainActor
    final class MockRateLimitFetcher: RateLimitFetching {
        var resultsByID: [String: RateLimitUsage]
        private(set) var fetchedIDs: [String] = []

        init(resultsByID: [String: RateLimitUsage]) {
            self.resultsByID = resultsByID
        }

        func fetch(accessToken: String, accountId: String) async -> APIFetchResult {
            fetchedIDs.append(accountId)
            return APIFetchResult(rateLimits: resultsByID[accountId], profile: nil)
        }
    }

    @MainActor
    final class MockAccountProvider: MultiAccountTokenProviding {
        var displayIDs: [String]
        var tokensByID: [String: String]

        init(displayIDs: [String], tokensByID: [String: String]) {
            self.displayIDs = displayIDs
            self.tokensByID = tokensByID
        }

        func multiAccountDisplayIDs() -> [String] {
            displayIDs
        }

        func accessToken(for accountId: String) async -> String? {
            tokensByID[accountId]
        }
    }

    // MARK: - Helpers

    private static func usage(_ fiveHour: Double, overallStatus: String = "allowed") -> RateLimitUsage {
        RateLimitUsage(
            representativeClaim: RateLimitUsage.fiveHourWindow,
            fiveHourUtilization: fiveHour,
            fiveHourReset: nil,
            fiveHourStatus: "allowed",
            sevenDayUtilization: 0,
            sevenDayReset: nil,
            sevenDayStatus: "allowed",
            overallStatus: overallStatus
        )
    }

    private static func tokens(_ ids: [String]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: ids.map { ($0, "token-\($0)") })
    }

    // MARK: - Orchestration

    @Test("Toggle off returns nil (caller clears its map) and fetches nothing")
    func toggleOffReturnsNil() async {
        let fetcher = MockRateLimitFetcher(resultsByID: ["a": Self.usage(0.42)])
        let provider = MockAccountProvider(displayIDs: ["a", "b"], tokensByID: Self.tokens(["a", "b"]))

        let result = await MultiAccountFanOut.resolve(
            enabled: false, seed: nil, provider: provider, fetcher: fetcher
        )

        #expect(result == nil)
        #expect(fetcher.fetchedIDs.isEmpty)
    }

    @Test("Toggle on, two accounts: fetches both and populates both")
    func twoAccountsPopulated() async {
        let fetcher = MockRateLimitFetcher(resultsByID: ["a": Self.usage(0.42), "b": Self.usage(0.23)])
        let provider = MockAccountProvider(displayIDs: ["a", "b"], tokensByID: Self.tokens(["a", "b"]))

        let result = await MultiAccountFanOut.resolve(
            enabled: true, seed: nil, provider: provider, fetcher: fetcher
        )

        #expect(Set(result?.keys ?? [:].keys) == ["a", "b"])
        #expect(Set(fetcher.fetchedIDs) == ["a", "b"])
        #expect((result?["a"]?.fiveHourPercent ?? -1) == 42)
        #expect((result?["b"]?.fiveHourPercent ?? -1) == 23)
    }

    @Test("Seed dedup: the seeded active account is NOT re-fetched")
    func seedDedup() async {
        let fetcher = MockRateLimitFetcher(resultsByID: ["b": Self.usage(0.23), "c": Self.usage(0.99)])
        let provider = MockAccountProvider(displayIDs: ["a", "b", "c"], tokensByID: Self.tokens(["a", "b", "c"]))

        let result = await MultiAccountFanOut.resolve(
            enabled: true,
            seed: (accountId: "a", rateLimits: Self.usage(0.42)),
            provider: provider,
            fetcher: fetcher
        )

        // "a" comes from the seed, never the network.
        #expect(Set(fetcher.fetchedIDs) == ["b", "c"])
        #expect(fetcher.fetchedIDs.contains("a") == false)
        #expect(Set(result?.keys ?? [:].keys) == ["a", "b", "c"])
        #expect((result?["a"]?.fiveHourPercent ?? -1) == 42)
    }

    @Test("Seed only (no other eligible accounts): seeds without any fetch")
    func seedOnly() async {
        let fetcher = MockRateLimitFetcher(resultsByID: [:])
        let provider = MockAccountProvider(displayIDs: ["a"], tokensByID: Self.tokens(["a"]))

        let result = await MultiAccountFanOut.resolve(
            enabled: true,
            seed: (accountId: "a", rateLimits: Self.usage(0.42)),
            provider: provider,
            fetcher: fetcher
        )

        #expect(fetcher.fetchedIDs.isEmpty)
        #expect(Set(result?.keys ?? [:].keys) == ["a"])
    }

    @Test("Missing token: that account is skipped without crashing")
    func missingTokenSkipped() async {
        let fetcher = MockRateLimitFetcher(resultsByID: ["a": Self.usage(0.42), "b": Self.usage(0.23)])
        // Only "a" has a token; "b" has none.
        let provider = MockAccountProvider(displayIDs: ["a", "b"], tokensByID: Self.tokens(["a"]))

        let result = await MultiAccountFanOut.resolve(
            enabled: true, seed: nil, provider: provider, fetcher: fetcher
        )

        #expect(Set(result?.keys ?? [:].keys) == ["a"])
        #expect(fetcher.fetchedIDs == ["a"]) // "b" returned before reaching fetch (nil token)
    }

    @Test("No eligible accounts and no seed returns nil")
    func emptyReturnsNil() async {
        let fetcher = MockRateLimitFetcher(resultsByID: [:])
        let provider = MockAccountProvider(displayIDs: [], tokensByID: [:])

        let result = await MultiAccountFanOut.resolve(
            enabled: true, seed: nil, provider: provider, fetcher: fetcher
        )

        #expect(result == nil)
        #expect(fetcher.fetchedIDs.isEmpty)
    }

    // MARK: - Shared eligible-account filter (Finding 3)

    private static func record(_ id: String) -> AccountRecord {
        AccountRecord(id: id, displayName: nil, billingType: nil, addedAt: Date())
    }

    @Test("Display IDs exclude pending and unauthenticated accounts, preserve order")
    func displayIDsFilter() {
        let accounts = [Self.record("pending-x"), Self.record("org-a"), Self.record("org-b")]
        // org-a authenticated, org-b not.
        let ids = AccountStore.multiAccountDisplayIDs(
            accounts: accounts,
            isAuthenticated: { $0 == "org-a" }
        )
        #expect(ids == ["org-a"]) // pending-x excluded (pending), org-b excluded (unauthenticated)
    }

    @Test("Display IDs follow store order when all eligible")
    func displayIDsOrder() {
        let accounts = [Self.record("org-a"), Self.record("org-b"), Self.record("org-c")]
        let ids = AccountStore.multiAccountDisplayIDs(accounts: accounts, isAuthenticated: { _ in true })
        #expect(ids == ["org-a", "org-b", "org-c"])

        let reordered = [Self.record("org-c"), Self.record("org-a"), Self.record("org-b")]
        let ids2 = AccountStore.multiAccountDisplayIDs(accounts: reordered, isAuthenticated: { _ in true })
        #expect(ids2 == ["org-c", "org-a", "org-b"])
    }
}

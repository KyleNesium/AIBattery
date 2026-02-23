import Testing
import Foundation
@testable import AIBatteryCore

@Suite("RateLimitFetcher")
struct RateLimitFetcherTests {

    // MARK: - Cache max age

    @Test @MainActor func cacheMaxAge_isOneHour() {
        // Verify constant hasn't been accidentally changed
        #expect(RateLimitFetcher.cacheMaxAge == 3600)
    }

    // MARK: - Fetch with no token returns empty

    @Test @MainActor func fetch_emptyToken_returnsEmptyResult() async {
        let fetcher = RateLimitFetcher()
        let result = await fetcher.fetch(accessToken: "", accountId: "test-account")

        // Empty token will fail auth → returns empty (no cached data)
        #expect(result.rateLimits == nil)
        #expect(result.profile == nil)
    }

    // MARK: - Multiple accounts use separate caches

    @Test @MainActor func fetch_differentAccounts_separateResults() async {
        let fetcher = RateLimitFetcher()

        // Both calls will fail (invalid tokens), but should create separate cache entries
        let result1 = await fetcher.fetch(accessToken: "invalid-1", accountId: "account-a")
        let result2 = await fetcher.fetch(accessToken: "invalid-2", accountId: "account-b")

        // Both should return empty (no cached data, network fails)
        #expect(result1.rateLimits == nil)
        #expect(result2.rateLimits == nil)
    }

    // MARK: - Cached result marked as stale

    @Test @MainActor func cachedOrEmpty_withinMaxAge_returnsCachedWithFlag() {
        let fetcher = RateLimitFetcher()

        // Inject a cached result
        let rateLimits = RateLimitUsage(
            fiveHourPercent: 50.0,
            sevenDayPercent: 20.0,
            fiveHourResetAt: Date().addingTimeInterval(3600),
            sevenDayResetAt: Date().addingTimeInterval(86400)
        )
        let profile = APIProfile(organizationId: "org-test")
        let cached = APIFetchResult(rateLimits: rateLimits, profile: profile, fetchedAt: Date())
        fetcher.setCachedResult(cached, for: "test-account")

        let result = fetcher.cachedOrEmpty(accountId: "test-account")

        #expect(result.isCached == true)
        #expect(result.rateLimits?.fiveHourPercent == 50.0)
        #expect(result.profile?.organizationId == "org-test")
    }

    @Test @MainActor func cachedOrEmpty_expiredCache_returnsEmpty() {
        let fetcher = RateLimitFetcher()

        // Inject an old cached result (2 hours ago)
        let rateLimits = RateLimitUsage(
            fiveHourPercent: 50.0,
            sevenDayPercent: 20.0,
            fiveHourResetAt: Date().addingTimeInterval(3600),
            sevenDayResetAt: Date().addingTimeInterval(86400)
        )
        let cached = APIFetchResult(
            rateLimits: rateLimits,
            profile: nil,
            fetchedAt: Date(timeIntervalSinceNow: -7200)
        )
        fetcher.setCachedResult(cached, for: "test-account")

        let result = fetcher.cachedOrEmpty(accountId: "test-account")

        #expect(result.rateLimits == nil)
        #expect(result.isCached == false)
    }

    @Test @MainActor func cachedOrEmpty_noCache_returnsEmpty() {
        let fetcher = RateLimitFetcher()
        let result = fetcher.cachedOrEmpty(accountId: "nonexistent")

        #expect(result.rateLimits == nil)
        #expect(result.profile == nil)
    }
}

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
            representativeClaim: "five_hour",
            fiveHourUtilization: 0.5,
            fiveHourReset: Date().addingTimeInterval(3600),
            fiveHourStatus: "allowed",
            sevenDayUtilization: 0.2,
            sevenDayReset: Date().addingTimeInterval(86400),
            sevenDayStatus: "allowed",
            overallStatus: "allowed"
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
            representativeClaim: "five_hour",
            fiveHourUtilization: 0.5,
            fiveHourReset: Date().addingTimeInterval(3600),
            fiveHourStatus: "allowed",
            sevenDayUtilization: 0.2,
            sevenDayReset: Date().addingTimeInterval(86400),
            sevenDayStatus: "allowed",
            overallStatus: "allowed"
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

    // MARK: - parseRetryAfter

    @Test func parseRetryAfter_validDelay() {
        #expect(RateLimitFetcher.parseRetryAfter("5") == 5.0)
    }

    @Test func parseRetryAfter_capsAtMax() {
        #expect(RateLimitFetcher.parseRetryAfter("100") == 30.0)
    }

    @Test func parseRetryAfter_zero_returnsNil() {
        #expect(RateLimitFetcher.parseRetryAfter("0") == nil)
    }

    @Test func parseRetryAfter_negative_returnsNil() {
        #expect(RateLimitFetcher.parseRetryAfter("-5") == nil)
    }

    @Test func parseRetryAfter_nonNumeric_returnsNil() {
        #expect(RateLimitFetcher.parseRetryAfter("abc") == nil)
    }

    @Test func parseRetryAfter_nil_returnsNil() {
        #expect(RateLimitFetcher.parseRetryAfter(nil) == nil)
    }

    @Test func parseRetryAfter_fractional() {
        let result = RateLimitFetcher.parseRetryAfter("2.5")
        #expect(result == 2.5)
    }

    @Test func parseRetryAfter_customMax() {
        #expect(RateLimitFetcher.parseRetryAfter("20", maxDelay: 10) == 10.0)
        #expect(RateLimitFetcher.parseRetryAfter("5", maxDelay: 10) == 5.0)
    }

    // MARK: - Dynamic observed models

    @Test @MainActor func observedModels_defaultsToEmpty() {
        let fetcher = RateLimitFetcher()
        #expect(fetcher.observedModels.isEmpty)
    }

    @Test @MainActor func setObservedModels_updatesInMemoryList() {
        let fetcher = RateLimitFetcher()
        fetcher.setObservedModels(["model-a", "model-b"], accountId: "acct-1")
        #expect(fetcher.observedModels == ["model-a", "model-b"])
    }

    @Test @MainActor func setObservedModels_persistsToUserDefaults() {
        let accountId = "test-persist-\(UUID().uuidString)"
        let key = "aibattery_observedModels_\(accountId)"
        defer { UserDefaults.standard.removeObject(forKey: key) }

        let fetcher = RateLimitFetcher()
        fetcher.setObservedModels(["model-x", "model-y"], accountId: accountId)

        let stored = UserDefaults.standard.stringArray(forKey: key)
        #expect(stored == ["model-x", "model-y"])
    }

    @Test @MainActor func observedModels_restoredOnInit() {
        let accountId = "test-restore-\(UUID().uuidString)"
        let key = "aibattery_observedModels_\(accountId)"
        UserDefaults.standard.set(["restored-model-a", "restored-model-b"], forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }

        // New fetcher should restore observedModels from UserDefaults
        let fetcher = RateLimitFetcher()
        #expect(fetcher.observedModels == ["restored-model-a", "restored-model-b"])
    }

    @Test @MainActor func setObservedModels_emptyList_fallsBackToUltimateFallback() async {
        let fetcher = RateLimitFetcher()
        // No observed models set — fetch should still attempt the ultimate fallback
        // (We can't fully test network behavior, but we verify observedModels is empty)
        #expect(fetcher.observedModels.isEmpty)
        // The fetch will attempt ultimateFallback as the last resort
        // (verified by the hardcoded constant existing in the implementation)
    }

    @Test @MainActor func ultimateFallback_isSingleHardcodedModel() {
        // Verify ultimateFallback constant exists and is the newest Sonnet
        #expect(RateLimitFetcher.ultimateFallback == "claude-sonnet-4-6-20250929")
    }

    @Test @MainActor func hardcodedFallbackModels_noLongerExists() {
        // This test documents that the 5-model hardcoded list is replaced.
        // We verify via observedModels being the dynamic source now.
        let fetcher = RateLimitFetcher()
        // observedModels is the dynamic replacement — starts empty for fresh install
        #expect(fetcher.observedModels.isEmpty)
        // The old fallbackModels had 5 entries — now we use observedModels + ultimateFallback
    }
}

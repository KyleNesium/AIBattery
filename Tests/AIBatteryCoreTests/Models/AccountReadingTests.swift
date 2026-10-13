import Foundation
import Testing
@testable import AIBatteryCore

@Suite("AccountReading")
struct AccountReadingTests {
    private func windows(fiveHour: Double, sevenDay: Double, throttled: Bool = false) -> RateLimitUsage {
        RateLimitUsage(
            representativeClaim: RateLimitUsage.fiveHourWindow,
            fiveHourUtilization: fiveHour, fiveHourReset: nil, fiveHourStatus: throttled ? "throttled" : "allowed",
            sevenDayUtilization: sevenDay, sevenDayReset: nil, sevenDayStatus: "allowed",
            overallStatus: throttled ? "throttled" : "allowed"
        )
    }

    private func api(requestsRemaining: String, tokensRemaining: String) -> StandardRateLimits? {
        StandardRateLimits.parse(openAIHeaders: [
            "x-ratelimit-limit-requests": "100", "x-ratelimit-remaining-requests": requestsRemaining,
            "x-ratelimit-limit-tokens": "1000", "x-ratelimit-remaining-tokens": tokensRemaining,
        ], now: .now)
    }

    @Test func worstPercent_windows_isMaxOfBothWindows() {
        let r = AccountReading(windows: windows(fiveHour: 0.34, sevenDay: 0.26), apiLimits: nil, fetchedAt: .now, isCached: false, source: nil)
        #expect(r.worstPercent == 34)
        #expect(r.isExhausted == false)
    }

    @Test func worstPercent_api_isPeakPercent() throws {
        let std = try #require(api(requestsRemaining: "20", tokensRemaining: "900"))
        let r = AccountReading(windows: nil, apiLimits: std, fetchedAt: .now, isCached: false, source: nil)
        #expect(r.worstPercent == 80)
        #expect(r.isExhausted == false)
    }

    @Test func exhausted_whenThrottledOrApiExhausted() throws {
        let t = AccountReading(windows: windows(fiveHour: 0.5, sevenDay: 0.1, throttled: true), apiLimits: nil, fetchedAt: .now, isCached: false, source: nil)
        #expect(t.isExhausted)
        let std = try #require(api(requestsRemaining: "0", tokensRemaining: "900"))
        let a = AccountReading(windows: nil, apiLimits: std, fetchedAt: .now, isCached: false, source: nil)
        #expect(a.isExhausted)
    }

    @Test func noReading_hasNilPercent() {
        let r = AccountReading(windows: nil, apiLimits: nil, fetchedAt: .now, isCached: true, source: nil)
        #expect(r.worstPercent == nil)
        #expect(r.isExhausted == false)
    }

    @Test func initFromAPI_routesShapes_andRejectsEmpty() throws {
        let std = try #require(api(requestsRemaining: "20", tokensRemaining: "900"))
        let apiOnly = APIFetchResult(rateLimits: nil, standardLimits: std, profile: nil, isCached: true)
        let r = try #require(AccountReading(api: apiOnly))
        #expect(r.windows == nil)
        #expect(r.apiLimits?.peakPercent == 80)
        #expect(r.isCached)
        let both = APIFetchResult(rateLimits: windows(fiveHour: 0.1, sevenDay: 0.1), standardLimits: std, profile: nil)
        #expect(AccountReading(api: both)?.apiLimits == nil) // windows win when both are present
        #expect(AccountReading(api: APIFetchResult(rateLimits: nil, profile: nil)) == nil)
    }

    @Test func carriedForward_marksCached() {
        let r = AccountReading(windows: windows(fiveHour: 0.1, sevenDay: 0.1), apiLimits: nil, fetchedAt: .now, isCached: false, source: nil)
        #expect(r.carriedForward().isCached)
        #expect(r.carriedForward().windows == r.windows)
    }

    @Test func fanOutGate_toggleOrTwoAccounts() {
        #expect(FanOutGate.enabled(menuBarToggle: false, eligibleAccountCount: 1) == false)
        #expect(FanOutGate.enabled(menuBarToggle: true, eligibleAccountCount: 1) == true)
        #expect(FanOutGate.enabled(menuBarToggle: false, eligibleAccountCount: 2) == true)
        #expect(FanOutGate.enabled(menuBarToggle: false, eligibleAccountCount: 0) == false)
    }
}

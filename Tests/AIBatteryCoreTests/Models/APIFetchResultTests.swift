import Foundation
import Testing
@testable import AIBatteryCore

@Suite("APIFetchResult")
struct APIFetchResultTests {

    @Test func defaults_notCachedAndFetchedAtNow() {
        let result = APIFetchResult(rateLimits: nil, profile: nil)
        #expect(result.isCached == false)
        #expect(abs(result.fetchedAt.timeIntervalSinceNow) < 2)
    }

    @Test func explicit_isCachedTrue() {
        let result = APIFetchResult(
            rateLimits: nil,
            profile: nil,
            fetchedAt: Date(timeIntervalSince1970: 1000),
            isCached: true
        )
        #expect(result.isCached == true)
        #expect(result.fetchedAt == Date(timeIntervalSince1970: 1000))
    }

    @Test func preserves_rateLimitsAndProfile() {
        let profile = APIProfile(organizationId: "org-1", workspaceId: nil, workspaceName: nil)
        let result = APIFetchResult(rateLimits: nil, profile: profile)
        #expect(result.profile?.organizationId == "org-1")
        #expect(result.rateLimits == nil)
    }

    @Test func defaults_rateLimitSourceToAPIHeadersWhenRateLimitsPresent() {
        let result = APIFetchResult(
            rateLimits: RateLimitUsage(
                representativeClaim: "five_hour",
                fiveHourUtilization: 0.42,
                fiveHourReset: nil,
                fiveHourStatus: "allowed",
                sevenDayUtilization: 0.15,
                sevenDayReset: nil,
                sevenDayStatus: "allowed",
                overallStatus: "allowed"
            ),
            profile: nil
        )
        #expect(result.rateLimitSource == .anthropicAPIHeaders)
    }

    @Test func preserves_standardHeaderDetectionFlag() {
        let result = APIFetchResult(
            rateLimits: nil,
            profile: nil,
            hasStandardRateLimitHeaders: true
        )
        #expect(result.hasStandardRateLimitHeaders == true)
    }

    @Test func preserves_explicitRateLimitSource() {
        let result = APIFetchResult(
            rateLimits: RateLimitUsage(
                representativeClaim: "five_hour",
                fiveHourUtilization: 0.42,
                fiveHourReset: nil,
                fiveHourStatus: "allowed",
                sevenDayUtilization: 0.15,
                sevenDayReset: nil,
                sevenDayStatus: "allowed",
                overallStatus: "allowed"
            ),
            rateLimitSource: .claudeCodeClientData,
            profile: nil
        )
        #expect(result.rateLimitSource == .claudeCodeClientData)
    }

    @Test func preserves_standardLimits() {
        let stdLimits = StandardRateLimits(
            requestsLimit: 50,
            requestsRemaining: 45,
            requestsReset: nil,
            tokensLimit: 80000,
            tokensRemaining: 75000,
            tokensReset: nil
        )
        let result = APIFetchResult(
            rateLimits: nil,
            standardLimits: stdLimits,
            profile: nil
        )
        #expect(result.standardLimits?.requestsLimit == 50)
        #expect(result.standardLimits?.requestsRemaining == 45)
    }

    @Test func standardLimits_defaultsToNil() {
        let result = APIFetchResult(rateLimits: nil, profile: nil)
        #expect(result.standardLimits == nil)
    }
}

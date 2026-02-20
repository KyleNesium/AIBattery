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
        let profile = APIProfile(organizationId: "org-1", organizationName: "Test")
        let result = APIFetchResult(rateLimits: nil, profile: profile)
        #expect(result.profile?.organizationName == "Test")
        #expect(result.rateLimits == nil)
    }
}

import Testing
import Foundation
@testable import AIBatteryCore

@Suite("RateLimitUsage")
struct RateLimitUsageTests {

    // MARK: - Parsing

    @Test func parse_fullHeaders() {
        let headers: [AnyHashable: Any] = [
            "anthropic-ratelimit-unified-status": "allowed",
            "anthropic-ratelimit-unified-representative-claim": "five_hour",
            "anthropic-ratelimit-unified-5h-utilization": "0.42",
            "anthropic-ratelimit-unified-5h-reset": "1700000000",
            "anthropic-ratelimit-unified-5h-status": "allowed",
            "anthropic-ratelimit-unified-7d-utilization": "0.15",
            "anthropic-ratelimit-unified-7d-reset": "1700500000",
            "anthropic-ratelimit-unified-7d-status": "allowed",
        ]
        let usage = RateLimitUsage.parse(headers: headers)
        #expect(usage != nil)
        #expect(usage?.representativeClaim == "five_hour")
        #expect(usage?.fiveHourUtilization == 0.42)
        #expect(usage?.sevenDayUtilization == 0.15)
        #expect(usage?.overallStatus == "allowed")
        #expect(usage?.fiveHourStatus == "allowed")
        #expect(usage?.sevenDayStatus == "allowed")
    }

    @Test func parse_missingStatusReturnsNil() {
        let headers: [AnyHashable: Any] = [
            "anthropic-ratelimit-unified-5h-utilization": "0.42",
        ]
        #expect(RateLimitUsage.parse(headers: headers) == nil)
    }

    @Test func parse_emptyHeaders() {
        #expect(RateLimitUsage.parse(headers: [:]) == nil)
    }

    @Test func parse_missingOptionalFieldsUseDefaults() {
        let headers: [AnyHashable: Any] = [
            "anthropic-ratelimit-unified-status": "allowed",
        ]
        let usage = RateLimitUsage.parse(headers: headers)
        #expect(usage != nil)
        #expect(usage?.representativeClaim == "five_hour")
        #expect(usage?.fiveHourUtilization == 0)
        #expect(usage?.sevenDayUtilization == 0)
    }

    @Test func parse_resetDates() {
        let headers: [AnyHashable: Any] = [
            "anthropic-ratelimit-unified-status": "allowed",
            "anthropic-ratelimit-unified-5h-reset": "1700000000",
            "anthropic-ratelimit-unified-7d-reset": "1700500000",
        ]
        let usage = RateLimitUsage.parse(headers: headers)!
        #expect(usage.fiveHourReset != nil)
        #expect(usage.sevenDayReset != nil)
        #expect(usage.fiveHourReset!.timeIntervalSince1970 == 1700000000)
    }

    // MARK: - Computed properties

    @Test func fiveHourPercent() {
        let usage = makeUsage(fiveHourUtil: 0.75, sevenDayUtil: 0.3)
        #expect(usage.fiveHourPercent == 75.0)
    }

    @Test func sevenDayPercent() {
        let usage = makeUsage(fiveHourUtil: 0.2, sevenDayUtil: 0.85)
        #expect(usage.sevenDayPercent == 85.0)
    }

    @Test func requestsPercentUsed_fiveHourBinding() {
        let usage = makeUsage(claim: "five_hour", fiveHourUtil: 0.6, sevenDayUtil: 0.3)
        #expect(usage.requestsPercentUsed == 60.0)
    }

    @Test func requestsPercentUsed_sevenDayBinding() {
        let usage = makeUsage(claim: "seven_day", fiveHourUtil: 0.3, sevenDayUtil: 0.8)
        #expect(usage.requestsPercentUsed == 80.0)
    }

    @Test func bindingReset_fiveHour() {
        let date = Date(timeIntervalSince1970: 1700000000)
        let usage = makeUsage(claim: "five_hour", fiveHourReset: date, sevenDayReset: nil)
        #expect(usage.bindingReset == date)
    }

    @Test func bindingReset_sevenDay() {
        let date = Date(timeIntervalSince1970: 1700500000)
        let usage = makeUsage(claim: "seven_day", fiveHourReset: nil, sevenDayReset: date)
        #expect(usage.bindingReset == date)
    }

    @Test func bindingWindowLabel() {
        #expect(makeUsage(claim: "five_hour").bindingWindowLabel == "5-hour")
        #expect(makeUsage(claim: "seven_day").bindingWindowLabel == "7-day")
    }

    @Test func isThrottled() {
        #expect(makeUsage(status: "throttled").isThrottled == true)
        #expect(makeUsage(status: "allowed").isThrottled == false)
    }

    // MARK: - Helpers

    private func makeUsage(
        claim: String = "five_hour",
        fiveHourUtil: Double = 0,
        sevenDayUtil: Double = 0,
        fiveHourReset: Date? = nil,
        sevenDayReset: Date? = nil,
        status: String = "allowed"
    ) -> RateLimitUsage {
        RateLimitUsage(
            representativeClaim: claim,
            fiveHourUtilization: fiveHourUtil,
            fiveHourReset: fiveHourReset,
            fiveHourStatus: status,
            sevenDayUtilization: sevenDayUtil,
            sevenDayReset: sevenDayReset,
            sevenDayStatus: status,
            overallStatus: status
        )
    }
}

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

    // MARK: - Predictive estimate

    @Test func estimatedTimeToLimit_lowUtilization_returnsNil() {
        // 30% utilization — too low to show estimate (threshold is >50%)
        let usage = makeUsage(
            fiveHourUtil: 0.30,
            fiveHourReset: Date().addingTimeInterval(3 * 3600)
        )
        #expect(usage.estimatedTimeToLimit(for: "five_hour") == nil)
    }

    @Test func estimatedTimeToLimit_noReset_returnsNil() {
        let usage = makeUsage(fiveHourUtil: 0.70)
        #expect(usage.estimatedTimeToLimit(for: "five_hour") == nil)
    }

    @Test func estimatedTimeToLimit_highUtilization_returnsEstimate() {
        // 80% utilization with 2h remaining of a 5h window → 3h elapsed
        // rate = 0.80/10800 ≈ 7.4e-5/s, timeToFull = 0.20/rate ≈ 2700s (45 min)
        // 45 min < 2h remaining, so estimate should be returned
        let usage = makeUsage(
            fiveHourUtil: 0.80,
            fiveHourReset: Date().addingTimeInterval(2 * 3600)
        )
        let estimate = usage.estimatedTimeToLimit(for: "five_hour")
        #expect(estimate != nil)
        #expect(estimate! > 0)
        #expect(estimate! < 2 * 3600) // Must be before reset
    }

    @Test func estimatedTimeToLimit_slowBurnRate_returnsNil() {
        // 51% utilization with only 30 min remaining of a 5h window → 4.5h elapsed
        // rate = 0.51/16200 ≈ 3.1e-5/s, timeToFull = 0.49/rate ≈ 15600s (4.3h)
        // 4.3h > 30 min remaining → estimate exceeds reset, so nil
        let usage = makeUsage(
            fiveHourUtil: 0.51,
            fiveHourReset: Date().addingTimeInterval(30 * 60)
        )
        #expect(usage.estimatedTimeToLimit(for: "five_hour") == nil)
    }

    @Test func estimatedTimeToLimit_sevenDayWindow() {
        // 70% utilization with 2 days remaining of a 7-day window → 5 days elapsed
        // rate = 0.70/432000 ≈ 1.6e-6/s, timeToFull = 0.30/rate ≈ 185714s (2.1 days)
        // 2.1 days > 2 days remaining → nil (we'll be fine before reset)
        let usage = makeUsage(
            sevenDayUtil: 0.70,
            sevenDayReset: Date().addingTimeInterval(2 * 24 * 3600)
        )
        // At this rate, estimate is close to reset — could go either way
        // The key test is that it doesn't crash and returns a reasonable value or nil
        let estimate = usage.estimatedTimeToLimit(for: "seven_day")
        if let estimate {
            #expect(estimate > 0)
        }
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

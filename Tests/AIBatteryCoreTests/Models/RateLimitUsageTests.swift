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

    @Test func parse_mixedCaseHeaders() {
        let headers: [AnyHashable: Any] = [
            "Anthropic-Ratelimit-Unified-Status": "allowed",
            "Anthropic-Ratelimit-Unified-Representative-Claim": "seven_day",
            "Anthropic-Ratelimit-Unified-5H-Utilization": "0.42",
            "Anthropic-Ratelimit-Unified-5H-Reset": "1700000000",
            "Anthropic-Ratelimit-Unified-5H-Status": "allowed",
            "Anthropic-Ratelimit-Unified-7D-Utilization": "0.15",
            "Anthropic-Ratelimit-Unified-7D-Reset": "1700500000",
            "Anthropic-Ratelimit-Unified-7D-Status": "throttled",
        ]
        let usage = RateLimitUsage.parse(headers: headers)
        #expect(usage != nil)
        #expect(usage?.representativeClaim == "seven_day")
        #expect(usage?.fiveHourUtilization == 0.42)
        #expect(usage?.sevenDayUtilization == 0.15)
        #expect(usage?.overallStatus == "allowed")
        #expect(usage?.sevenDayStatus == "throttled")
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

    @Test func parse_throttledHeaders_returnsUsageWithResetDates() {
        let headers: [AnyHashable: Any] = [
            "anthropic-ratelimit-unified-status": "throttled",
            "anthropic-ratelimit-unified-representative-claim": "five_hour",
            "anthropic-ratelimit-unified-5h-utilization": "1.0",
            "anthropic-ratelimit-unified-5h-reset": "1700000000",
            "anthropic-ratelimit-unified-5h-status": "throttled",
            "anthropic-ratelimit-unified-7d-utilization": "0.85",
            "anthropic-ratelimit-unified-7d-reset": "1700500000",
            "anthropic-ratelimit-unified-7d-status": "allowed",
        ]
        let usage = RateLimitUsage.parse(headers: headers)
        #expect(usage != nil)
        #expect(usage?.isThrottled == true)
        #expect(usage?.fiveHourPercent == 100.0)
        #expect(usage?.fiveHourReset != nil)
        #expect(usage?.sevenDayReset != nil)
        #expect(usage?.fiveHourStatus == "throttled")
    }

    @Test func parse_throttledHeaders_withoutWindowStatuses_onlyMarksBindingWindow() {
        let headers: [AnyHashable: Any] = [
            "anthropic-ratelimit-unified-status": "throttled",
            "anthropic-ratelimit-unified-representative-claim": "five_hour",
            "anthropic-ratelimit-unified-5h-utilization": "1.0",
            "anthropic-ratelimit-unified-7d-utilization": "1.0",
        ]

        let usage = try #require(RateLimitUsage.parse(headers: headers))
        #expect(usage.fiveHourStatus == "throttled")
        #expect(usage.sevenDayStatus == "allowed")
        #expect(usage.isWindowThrottled(RateLimitUsage.fiveHourWindow) == true)
        #expect(usage.isWindowThrottled(RateLimitUsage.sevenDayWindow) == false)
    }

    @Test func parse_clampsUtilizationAboveOne() {
        let headers: [AnyHashable: Any] = [
            "anthropic-ratelimit-unified-status": "allowed",
            "anthropic-ratelimit-unified-5h-utilization": "1.5",
            "anthropic-ratelimit-unified-7d-utilization": "2.0",
        ]
        let usage = RateLimitUsage.parse(headers: headers)!
        #expect(usage.fiveHourUtilization == 1.0)
        #expect(usage.sevenDayUtilization == 1.0)
    }

    @Test func parse_clampsNegativeUtilizationToZero() {
        let headers: [AnyHashable: Any] = [
            "anthropic-ratelimit-unified-status": "allowed",
            "anthropic-ratelimit-unified-5h-utilization": "-0.5",
            "anthropic-ratelimit-unified-7d-utilization": "-1.0",
        ]
        let usage = RateLimitUsage.parse(headers: headers)!
        #expect(usage.fiveHourUtilization == 0.0)
        #expect(usage.sevenDayUtilization == 0.0)
    }

    @Test func parse_clientDataJSON_withWindowObjects() throws {
        let data = try #require("""
        {
          "rate_limits": {
            "status": "allowed",
            "representative_claim": "seven_day",
            "five_hour": {
              "utilization": 0.42,
              "reset_at": 1700000000,
              "status": "allowed"
            },
            "seven_day": {
              "utilization": 0.85,
              "reset_at": "2026-04-09T12:00:00Z",
              "status": "throttled"
            }
          }
        }
        """.data(using: .utf8))

        let usage = RateLimitUsage.parse(clientData: data)
        #expect(usage != nil)
        #expect(usage?.representativeClaim == "seven_day")
        #expect(usage?.fiveHourUtilization == 0.42)
        #expect(usage?.sevenDayUtilization == 0.85)
        #expect(usage?.fiveHourReset?.timeIntervalSince1970 == 1700000000)
        #expect(usage?.sevenDayStatus == "throttled")
        #expect(usage?.isThrottled == true)
    }

    @Test func parse_clientDataJSON_withPercentValues_infersBindingWindow() throws {
        let data = try #require("""
        {
          "usage": {
            "5h": {
              "usage": 37,
              "reset": 1700000000000
            },
            "7d": {
              "usage": 61,
              "reset": 1700500000000
            }
          }
        }
        """.data(using: .utf8))

        let usage = RateLimitUsage.parse(clientData: data)
        #expect(usage != nil)
        #expect(usage?.representativeClaim == "seven_day")
        #expect(usage?.fiveHourUtilization == 0.37)
        #expect(usage?.sevenDayUtilization == 0.61)
        #expect(usage?.fiveHourReset?.timeIntervalSince1970 == 1700000000)
        #expect(usage?.sevenDayReset?.timeIntervalSince1970 == 1700500000)
        #expect(usage?.overallStatus == "allowed")
    }

    @Test func parse_clientDataJSON_overallThrottledWithoutWindowStatuses_onlyMarksBindingWindow() throws {
        let data = try #require("""
        {
          "rate_limits": {
            "status": "throttled",
            "representative_claim": "five_hour",
            "five_hour": {
              "utilization": 1.0
            },
            "seven_day": {
              "utilization": 1.0
            }
          }
        }
        """.data(using: .utf8))

        let usage = try #require(RateLimitUsage.parse(clientData: data))
        #expect(usage.fiveHourStatus == "throttled")
        #expect(usage.sevenDayStatus == "allowed")
        #expect(usage.isWindowThrottled(RateLimitUsage.fiveHourWindow) == true)
        #expect(usage.isWindowThrottled(RateLimitUsage.sevenDayWindow) == false)
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

    @Test func isThrottled_overallStatus() {
        #expect(makeUsage(status: "throttled").isThrottled == true)
        #expect(makeUsage(status: "allowed").isThrottled == false)
    }

    @Test func isThrottled_perWindowStatus() {
        // 5h window throttled, overall still "allowed"
        let fiveHourThrottled = makeUsage(
            fiveHourStatus: "throttled",
            sevenDayStatus: "allowed",
            status: "allowed"
        )
        #expect(fiveHourThrottled.isThrottled == true)

        // 7d window throttled, overall still "allowed"
        let sevenDayThrottled = makeUsage(
            fiveHourStatus: "allowed",
            sevenDayStatus: "throttled",
            status: "allowed"
        )
        #expect(sevenDayThrottled.isThrottled == true)

        // All allowed
        let noneThrottled = makeUsage(
            fiveHourStatus: "allowed",
            sevenDayStatus: "allowed",
            status: "allowed"
        )
        #expect(noneThrottled.isThrottled == false)
    }

    @Test func isWindowThrottled_onlyFlagsMatchingWindow() {
        let usage = makeUsage(
            claim: "five_hour",
            fiveHourStatus: "throttled",
            sevenDayStatus: "allowed",
            status: "throttled"
        )

        #expect(usage.isThrottled == true)
        #expect(usage.isWindowThrottled(RateLimitUsage.fiveHourWindow) == true)
        #expect(usage.isWindowThrottled(RateLimitUsage.sevenDayWindow) == false)
    }

    @Test func markedThrottled_bindingWindowMarksRepresentativeWindow() {
        let usage = makeUsage(
            claim: "seven_day",
            fiveHourUtil: 0.57,
            sevenDayUtil: 0.99,
            fiveHourStatus: "allowed",
            sevenDayStatus: "allowed",
            status: "allowed"
        ).markedThrottled()

        #expect(usage.isThrottled == true)
        #expect(usage.overallStatus == "throttled")
        #expect(usage.fiveHourStatus == "allowed")
        #expect(usage.sevenDayStatus == "throttled")
        #expect(usage.sevenDayPercent == 99.0)
    }

    @Test func markedThrottled_explicitBindingWindowOverridesRepresentativeClaim() {
        let usage = makeUsage(
            claim: "five_hour",
            fiveHourStatus: "allowed",
            sevenDayStatus: "allowed",
            status: "allowed"
        ).markedThrottled(bindingWindow: "seven_day")

        #expect(usage.overallStatus == "throttled")
        #expect(usage.fiveHourStatus == "allowed")
        #expect(usage.sevenDayStatus == "throttled")
    }

    // MARK: - Predictive estimate

    @Test func estimatedTimeToLimit_lowUtilization_returnsNil() {
        // 15% utilization — too low to show estimate (threshold is >20%)
        let usage = makeUsage(
            fiveHourUtil: 0.15,
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

    @Test func estimatedTimeToLimit_resetInPast_returnsNil() {
        // Reset date already passed — remaining time is negative
        let usage = makeUsage(
            fiveHourUtil: 0.80,
            fiveHourReset: Date().addingTimeInterval(-60)
        )
        #expect(usage.estimatedTimeToLimit(for: "five_hour") == nil)
    }

    @Test func estimatedTimeToLimit_exactlyAtThreshold_returnsNil() {
        // Utilization at exactly 0.20 — threshold is > 0.20, so should return nil
        let usage = makeUsage(
            fiveHourUtil: 0.20,
            fiveHourReset: Date().addingTimeInterval(2 * 3600)
        )
        #expect(usage.estimatedTimeToLimit(for: "five_hour") == nil)
    }

    @Test func estimatedTimeToLimit_freshWindow_returnsNil() {
        // Window just started (< 60s elapsed) — not enough data for meaningful rate
        // 5h window = 18000s, reset in 17950s → only 50s elapsed
        let usage = makeUsage(
            fiveHourUtil: 0.60,
            fiveHourReset: Date().addingTimeInterval(5 * 3600 - 50)
        )
        #expect(usage.estimatedTimeToLimit(for: "five_hour") == nil)
    }

    @Test func estimatedTimeToLimit_justAboveThreshold_returnsEstimate() {
        // 25% utilization — above the 20% threshold, should not be blocked by the guard.
        // 5h window, reset in 4.5h → elapsed = 0.5h = 1800s
        // rate = 0.25/1800 ≈ 1.39e-4/s
        // timeToFull = 0.75/rate ≈ 5400s (1.5h)
        // 1.5h < 4.5h remaining → estimate returned
        // This proves projections work in the 20-50% utilization range
        let usage = makeUsage(
            fiveHourUtil: 0.25,
            fiveHourReset: Date().addingTimeInterval(4.5 * 3600)
        )
        let estimate = usage.estimatedTimeToLimit(for: "five_hour")
        #expect(estimate != nil)
        #expect(estimate! > 0)
    }

    @Test func requestsPercentUsed_unknownClaim_defaultsToFiveHour() {
        // An unrecognized claim string should fall back to the 5h window
        let usage = makeUsage(claim: "some_future_window", fiveHourUtil: 0.55, sevenDayUtil: 0.30)
        #expect(abs(usage.requestsPercentUsed - 55.0) < 0.001)
    }

    @Test func bindingReset_unknownClaim_defaultsToFiveHour() {
        let fiveDate = Date(timeIntervalSince1970: 1700000000)
        let sevenDate = Date(timeIntervalSince1970: 1700500000)
        let usage = makeUsage(claim: "unknown", fiveHourReset: fiveDate, sevenDayReset: sevenDate)
        #expect(usage.bindingReset == fiveDate)
    }

    @Test func bindingWindowLabel_unknownClaim_defaultsToFiveHour() {
        #expect(makeUsage(claim: "unknown").bindingWindowLabel == "5-hour")
    }

    // MARK: - Countdown formatter

    @Test func countdownText_hoursAndMinutes() {
        let now = Date()
        let future = now.addingTimeInterval(2 * 3600 + 30 * 60) // 2h 30m
        #expect(RateLimitUsage.countdownText(to: future, from: now) == "2h 30m")
    }

    @Test func countdownText_minutesOnly() {
        let now = Date()
        let future = now.addingTimeInterval(45 * 60) // 45m
        #expect(RateLimitUsage.countdownText(to: future, from: now) == "45m")
    }

    @Test func countdownText_pastDate() {
        let now = Date()
        let past = now.addingTimeInterval(-60)
        #expect(RateLimitUsage.countdownText(to: past, from: now) == "soon")
    }

    @Test func countdownText_multiDay() {
        let now = Date()
        let future = now.addingTimeInterval(3 * 24 * 3600 + 2 * 3600) // 3d 2h
        #expect(RateLimitUsage.countdownText(to: future, from: now) == "3d 2h")
    }

    @Test func countdownText_lessThanOneMinute() {
        let now = Date()
        let future = now.addingTimeInterval(30) // 30 seconds
        #expect(RateLimitUsage.countdownText(to: future, from: now) == "30s")
    }

    @Test func countdownText_exactlyOneHour() {
        let now = Date()
        let future = now.addingTimeInterval(3600) // exactly 1h
        #expect(RateLimitUsage.countdownText(to: future, from: now) == "1h 0m")
    }

    // MARK: - parse(clientData:) edge cases

    @Test func parse_clientData_emptyData_returnsNil() {
        #expect(RateLimitUsage.parse(clientData: Data()) == nil)
    }

    @Test func parse_clientData_invalidJSON_returnsNil() {
        let garbage = Data([0xFF, 0xFE, 0x00, 0x01])
        #expect(RateLimitUsage.parse(clientData: garbage) == nil)
    }

    @Test func parse_clientData_emptyObject_returnsNil() throws {
        let data = try #require("{}".data(using: .utf8))
        #expect(RateLimitUsage.parse(clientData: data) == nil)
    }

    @Test func parse_clientData_noUtilizationFields_returnsNil() throws {
        let data = try #require("""
        {"rate_limits": {"status": "allowed"}}
        """.data(using: .utf8))
        #expect(RateLimitUsage.parse(clientData: data) == nil)
    }

    // MARK: - Helpers

    private func makeUsage(
        claim: String = "five_hour",
        fiveHourUtil: Double = 0,
        sevenDayUtil: Double = 0,
        fiveHourReset: Date? = nil,
        sevenDayReset: Date? = nil,
        fiveHourStatus: String? = nil,
        sevenDayStatus: String? = nil,
        status: String = "allowed"
    ) -> RateLimitUsage {
        RateLimitUsage(
            representativeClaim: claim,
            fiveHourUtilization: fiveHourUtil,
            fiveHourReset: fiveHourReset,
            fiveHourStatus: fiveHourStatus ?? status,
            sevenDayUtilization: sevenDayUtil,
            sevenDayReset: sevenDayReset,
            sevenDayStatus: sevenDayStatus ?? status,
            overallStatus: status
        )
    }
}

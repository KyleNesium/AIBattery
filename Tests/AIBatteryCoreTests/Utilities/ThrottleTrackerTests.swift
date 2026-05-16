import Testing
import Foundation
@testable import AIBatteryCore

@Suite("ThrottleTracker")
struct ThrottleTrackerTests {
    // MARK: - evaluate

    @Test func evaluate_nilRateLimits_noRecord() {
        let tracker = ThrottleTracker()
        let (next, timestamp) = tracker.evaluate(nil)
        #expect(timestamp == nil)
        #expect(next.wasThrottled == false)
    }

    @Test func evaluate_notThrottled_noRecord() {
        let tracker = ThrottleTracker()
        let rl = RateLimitUsage(
            representativeClaim: "five_hour",
            fiveHourUtilization: 0.5,
            fiveHourReset: nil,
            fiveHourStatus: "allowed",
            sevenDayUtilization: 0.1,
            sevenDayReset: nil,
            sevenDayStatus: "allowed",
            overallStatus: "allowed"
        )
        let (next, timestamp) = tracker.evaluate(rl)
        #expect(timestamp == nil)
        #expect(next.wasThrottled == false)
    }

    @Test func evaluate_transitionToThrottled_records() {
        let tracker = ThrottleTracker()
        let rl = RateLimitUsage(
            representativeClaim: "five_hour",
            fiveHourUtilization: 1.0,
            fiveHourReset: nil,
            fiveHourStatus: "throttled",
            sevenDayUtilization: 0.1,
            sevenDayReset: nil,
            sevenDayStatus: "allowed",
            overallStatus: "throttled"
        )
        let (next, timestamp) = tracker.evaluate(rl)
        #expect(timestamp != nil)
        #expect(next.wasThrottled == true)
    }

    @Test func evaluate_alreadyThrottled_noDoubleRecord() {
        var tracker = ThrottleTracker()
        let rl = RateLimitUsage(
            representativeClaim: "five_hour",
            fiveHourUtilization: 1.0,
            fiveHourReset: nil,
            fiveHourStatus: "throttled",
            sevenDayUtilization: 0.1,
            sevenDayReset: nil,
            sevenDayStatus: "allowed",
            overallStatus: "throttled"
        )
        // First transition
        let (next1, ts1) = tracker.evaluate(rl)
        tracker = next1
        #expect(ts1 != nil)
        // Second call — still throttled, no new record
        let (_, ts2) = tracker.evaluate(rl)
        #expect(ts2 == nil)
    }

    @Test func evaluate_exhaustedNotThrottled_records() {
        let tracker = ThrottleTracker()
        let rl = RateLimitUsage(
            representativeClaim: "five_hour",
            fiveHourUtilization: 1.0,
            fiveHourReset: nil,
            fiveHourStatus: "allowed",
            sevenDayUtilization: 0.3,
            sevenDayReset: nil,
            sevenDayStatus: "allowed",
            overallStatus: "allowed"
        )
        let (next, timestamp) = tracker.evaluate(rl)
        #expect(timestamp != nil)
        #expect(next.wasThrottled == true)
    }

    @Test func evaluate_sevenDayExhausted_records() {
        let tracker = ThrottleTracker()
        let rl = RateLimitUsage(
            representativeClaim: "seven_day",
            fiveHourUtilization: 0.2,
            fiveHourReset: nil,
            fiveHourStatus: "allowed",
            sevenDayUtilization: 1.0,
            sevenDayReset: nil,
            sevenDayStatus: "allowed",
            overallStatus: "allowed"
        )
        let (next, timestamp) = tracker.evaluate(rl)
        #expect(timestamp != nil)
        #expect(next.wasThrottled == true)
    }

    @Test func evaluate_recoveryThenThrottle_recordsTwice() {
        var tracker = ThrottleTracker()
        let throttled = RateLimitUsage(
            representativeClaim: "five_hour",
            fiveHourUtilization: 1.0,
            fiveHourReset: nil,
            fiveHourStatus: "throttled",
            sevenDayUtilization: 0.1,
            sevenDayReset: nil,
            sevenDayStatus: "allowed",
            overallStatus: "throttled"
        )
        // First throttle
        let (next1, ts1) = tracker.evaluate(throttled)
        tracker = next1
        #expect(ts1 != nil)
        // Recovery
        let (next2, ts2) = tracker.evaluate(nil)
        tracker = next2
        #expect(ts2 == nil)
        #expect(tracker.wasThrottled == false)
        // Second throttle
        let (_, ts3) = tracker.evaluate(throttled)
        #expect(ts3 != nil)
    }

    // MARK: - parseTimestamps

    @Test func parseTimestamps_nil_returnsEmpty() {
        #expect(ThrottleTracker.parseTimestamps(nil).isEmpty)
    }

    @Test func parseTimestamps_doubles() {
        let raw: [Any] = [1.0, 2.0, 3.0]
        #expect(ThrottleTracker.parseTimestamps(raw) == [1.0, 2.0, 3.0])
    }

    @Test func parseTimestamps_strings() {
        let raw: [Any] = ["100.5", "200.0"]
        #expect(ThrottleTracker.parseTimestamps(raw) == [100.5, 200.0])
    }

    @Test func parseTimestamps_integers() {
        let raw: [Any] = [100 as Int, 200 as Int]
        #expect(ThrottleTracker.parseTimestamps(raw) == [100.0, 200.0])
    }

    @Test func parseTimestamps_mixedTypes() {
        let raw: [Any] = [1.0, "2.0", 3 as Int, "invalid"]
        #expect(ThrottleTracker.parseTimestamps(raw) == [1.0, 2.0, 3.0])
    }

    // MARK: - appendAndPrune

    @Test func appendAndPrune_addsNewTimestamp() {
        let result = ThrottleTracker.appendAndPrune(timestamps: [100.0], newTimestamp: 200.0)
        #expect(result == [100.0, 200.0])
    }

    @Test func appendAndPrune_prunesOlderThan30Days() {
        let now = Date().timeIntervalSince1970
        let old = now - 31 * 86_400 // 31 days ago
        let recent = now - 5 * 86_400 // 5 days ago
        let result = ThrottleTracker.appendAndPrune(timestamps: [old, recent], newTimestamp: now)
        #expect(result.count == 2) // recent + now (old pruned)
        #expect(!result.contains(old))
        #expect(result.contains(recent))
        #expect(result.contains(now))
    }

    // MARK: - count

    @Test func count_filtersOldEvents() {
        let now = Date().timeIntervalSince1970
        let old = now - 8 * 86_400 // 8 days ago
        let timestamps = [old, now]
        #expect(ThrottleTracker.count(timestamps: timestamps, days: 7) == 1)
        #expect(ThrottleTracker.count(timestamps: timestamps, days: 30) == 2)
    }

    @Test func count_emptyTimestamps_returnsZero() {
        #expect(ThrottleTracker.count(timestamps: [], days: 7) == 0)
    }
}

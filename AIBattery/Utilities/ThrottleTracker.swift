import Foundation

/// Pure value type that tracks throttle event transitions.
/// Detects normal → throttled/exhausted transitions and manages timestamp storage.
/// Extracted from UsageViewModel for testability without global mutable state.
struct ThrottleTracker {
    /// Whether the previous evaluation saw a throttled/exhausted state.
    private(set) var wasThrottled = false

    /// Evaluate rate limits and return an updated tracker plus an optional timestamp
    /// to record (non-nil only on the transition from normal → throttled/exhausted).
    /// Does NOT mutate self — returns a new tracker (immutable pattern).
    func evaluate(_ rateLimits: RateLimitUsage?) -> (tracker: ThrottleTracker, recordTimestamp: Double?) {
        let isThrottled = rateLimits?.isThrottled ?? false
        let isExhausted = (rateLimits?.fiveHourUtilization ?? 0) >= 1.0
            || (rateLimits?.sevenDayUtilization ?? 0) >= 1.0
        let effectivelyThrottled = isThrottled || isExhausted

        var next = ThrottleTracker()
        next.wasThrottled = effectivelyThrottled

        let shouldRecord = effectivelyThrottled && !wasThrottled
        return (next, shouldRecord ? Date().timeIntervalSince1970 : nil)
    }

    /// Parse throttle timestamps from a raw UserDefaults array, handling both
    /// numeric and string storage (legacy data may be stored as strings).
    static func parseTimestamps(_ raw: [Any]?) -> [Double] {
        guard let raw else { return [] }
        return raw.compactMap { element in
            if let d = element as? Double { return d }
            if let s = element as? String { return Double(s) }
            if let i = element as? Int { return Double(i) }
            return nil
        }
    }

    /// Append a new timestamp and prune entries older than 30 days.
    static func appendAndPrune(timestamps: [Double], newTimestamp: Double) -> [Double] {
        let cutoff = newTimestamp - 30 * 86_400
        var result = timestamps.filter { $0 >= cutoff }
        result.append(newTimestamp)
        return result
    }

    /// Count timestamps within a given number of days from now.
    static func count(timestamps: [Double], days: Int) -> Int {
        let cutoff = Date().timeIntervalSince1970 - Double(days) * 86_400
        return timestamps.filter { $0 >= cutoff }.count
    }
}

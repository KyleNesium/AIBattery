import Foundation

/// Parsed from Anthropic's unified rate limit headers.
///
/// The API uses a unified sliding-window system with two windows:
///   - 5-hour window (short-term burst)
///   - 7-day window (long-term usage)
/// Each reports a utilization fraction (0.0–1.0) and a reset timestamp.
/// The `representative-claim` tells which window is the binding constraint.
struct RateLimitUsage {
    /// The binding constraint: "five_hour" or "seven_day"
    let representativeClaim: String

    /// 5-hour window
    let fiveHourUtilization: Double   // 0.0 – 1.0
    let fiveHourReset: Date?
    let fiveHourStatus: String        // "allowed" or "throttled"

    /// 7-day window
    let sevenDayUtilization: Double
    let sevenDayReset: Date?
    let sevenDayStatus: String

    /// Overall status
    let overallStatus: String         // "allowed" or "throttled"

    // MARK: - Convenience

    /// The utilization percentage of the binding window (0–100).
    var requestsPercentUsed: Double {
        switch representativeClaim {
        case "seven_day": return sevenDayUtilization * 100.0
        default: return fiveHourUtilization * 100.0
        }
    }

    /// 5-hour utilization as percentage (0–100).
    var fiveHourPercent: Double { fiveHourUtilization * 100.0 }

    /// 7-day utilization as percentage (0–100).
    var sevenDayPercent: Double { sevenDayUtilization * 100.0 }

    /// Reset date of the binding window.
    var bindingReset: Date? {
        switch representativeClaim {
        case "seven_day": return sevenDayReset
        default: return fiveHourReset
        }
    }

    /// Human-readable label for the binding window.
    var bindingWindowLabel: String {
        switch representativeClaim {
        case "seven_day": return "7-day"
        default: return "5-hour"
        }
    }

    /// Whether the user is currently throttled.
    var isThrottled: Bool { overallStatus == "throttled" }

    // MARK: - Predictive estimate

    /// Estimate time until the rate limit is reached for a given window,
    /// based on current utilization and time remaining until reset.
    /// Returns nil if utilization is too low or the estimate exceeds reset time.
    func estimatedTimeToLimit(for window: String) -> TimeInterval? {
        let (utilization, reset): (Double, Date?) = {
            switch window {
            case "seven_day": return (sevenDayUtilization, sevenDayReset)
            default: return (fiveHourUtilization, fiveHourReset)
            }
        }()

        guard utilization > 0.50, let reset else { return nil }

        let remaining = reset.timeIntervalSinceNow
        guard remaining > 0 else { return nil }

        // Window duration inferred from window type
        let windowDuration: TimeInterval = window == "seven_day" ? 7 * 24 * 3600 : 5 * 3600
        let elapsed = windowDuration - remaining

        guard elapsed > 60 else { return nil } // Need meaningful elapsed time

        // burn rate = utilization / elapsed, project when we reach 1.0
        let rate = utilization / elapsed
        let timeToFull = (1.0 - utilization) / rate

        // Only show if estimate is before the reset (otherwise it's fine)
        guard timeToFull < remaining else { return nil }

        return timeToFull
    }

    // MARK: - Parsing

    /// Parse unified rate limit headers from an HTTP response.
    static func parse(headers: [AnyHashable: Any]) -> RateLimitUsage? {
        func stringHeader(_ key: String) -> String? {
            headers[key] as? String
        }

        func doubleHeader(_ key: String) -> Double {
            guard let val = headers[key] as? String else { return 0 }
            return Double(val) ?? 0
        }

        func dateFromUnix(_ key: String) -> Date? {
            guard let val = headers[key] as? String,
                  let ts = TimeInterval(val) else { return nil }
            return Date(timeIntervalSince1970: ts)
        }

        // Detect unified headers
        guard let status = stringHeader("anthropic-ratelimit-unified-status") else {
            return nil
        }

        return RateLimitUsage(
            representativeClaim: stringHeader("anthropic-ratelimit-unified-representative-claim") ?? "five_hour",
            fiveHourUtilization: doubleHeader("anthropic-ratelimit-unified-5h-utilization"),
            fiveHourReset: dateFromUnix("anthropic-ratelimit-unified-5h-reset"),
            fiveHourStatus: stringHeader("anthropic-ratelimit-unified-5h-status") ?? status,
            sevenDayUtilization: doubleHeader("anthropic-ratelimit-unified-7d-utilization"),
            sevenDayReset: dateFromUnix("anthropic-ratelimit-unified-7d-reset"),
            sevenDayStatus: stringHeader("anthropic-ratelimit-unified-7d-status") ?? status,
            overallStatus: status
        )
    }
}

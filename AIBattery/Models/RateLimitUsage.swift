import Foundation

/// Parsed from Anthropic's unified rate limit headers.
///
/// The API uses a unified sliding-window system with two windows:
///   - 5-hour window (short-term burst)
///   - 7-day window (long-term usage)
/// Each reports a utilization fraction (0.0–1.0) and a reset timestamp.
/// The `representative-claim` tells which window is the binding constraint.
struct RateLimitUsage: Equatable, Codable {
    /// Window identifiers used in API headers.
    static let fiveHourWindow = "five_hour"
    static let sevenDayWindow = "seven_day"

    private static func inferredWindowStatus(
        explicitStatus: String?,
        overallStatus: String,
        representativeClaim: String,
        window: String
    ) -> String {
        if let explicitStatus { return explicitStatus }
        guard overallStatus == "throttled" else { return overallStatus }
        return representativeClaim == window ? "throttled" : "allowed"
    }

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
        case Self.sevenDayWindow: return sevenDayUtilization * 100.0
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
        case Self.sevenDayWindow: return sevenDayReset
        default: return fiveHourReset
        }
    }

    /// Human-readable label for the binding window.
    var bindingWindowLabel: String {
        switch representativeClaim {
        case Self.sevenDayWindow: return "7-day"
        default: return "5-hour"
        }
    }

    /// Whether the user is currently throttled.
    /// Checks overall status and per-window statuses — the API may report
    /// a window as "throttled" before the overall status reflects it.
    var isThrottled: Bool {
        overallStatus == "throttled"
            || fiveHourStatus == "throttled"
            || sevenDayStatus == "throttled"
    }

    /// Whether a specific window is currently throttled.
    /// A global throttled status alone is not enough to mark every window as throttled.
    func isWindowThrottled(_ window: String) -> Bool {
        switch window {
        case Self.sevenDayWindow:
            return sevenDayStatus == "throttled"
        default:
            return fiveHourStatus == "throttled"
        }
    }

    /// Force a throttled state when the HTTP response proves the account is rate limited
    /// but the unified headers lag behind and still report an allowed status/utilization.
    func markedThrottled(bindingWindow: String? = nil) -> RateLimitUsage {
        let window = bindingWindow ?? representativeClaim
        return RateLimitUsage(
            representativeClaim: representativeClaim,
            fiveHourUtilization: fiveHourUtilization,
            fiveHourReset: fiveHourReset,
            fiveHourStatus: window == Self.fiveHourWindow ? "throttled" : fiveHourStatus,
            sevenDayUtilization: sevenDayUtilization,
            sevenDayReset: sevenDayReset,
            sevenDayStatus: window == Self.sevenDayWindow ? "throttled" : sevenDayStatus,
            overallStatus: "throttled"
        )
    }

    // MARK: - Countdown formatter

    /// Compact countdown string for menu bar: "2h 15m", "45m", "0s"
    static func countdownText(to date: Date, from now: Date = .now) -> String {
        DurationFormatter.compact(date.timeIntervalSince(now))
    }

    // MARK: - Predictive estimate

    /// Estimate time until the rate limit is reached for a given window,
    /// based on current utilization and time remaining until reset.
    /// Returns nil if utilization is too low or the estimate exceeds reset time.
    func estimatedTimeToLimit(for window: String) -> TimeInterval? {
        let (utilization, reset): (Double, Date?) = {
            switch window {
            case Self.sevenDayWindow: return (sevenDayUtilization, sevenDayReset)
            default: return (fiveHourUtilization, fiveHourReset)
            }
        }()

        guard utilization > 0.20, let reset else { return nil }

        let remaining = reset.timeIntervalSinceNow
        guard remaining > 0 else { return nil }

        // Window duration inferred from window type
        let windowDuration: TimeInterval = window == Self.sevenDayWindow ? 7 * 24 * 3600 : 5 * 3600
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
    /// Uses case-insensitive lookup to handle server-side casing changes
    /// (HTTPURLResponse.allHeaderFields bridging to Swift can lose case-insensitivity).
    static func parse(headers: [AnyHashable: Any]) -> RateLimitUsage? {
        // Build a lowercased lookup table for reliable case-insensitive access.
        let normalized: [String: String] = {
            var map = [String: String]()
            for (key, value) in headers {
                if let k = key as? String, let v = value as? String {
                    map[k.lowercased()] = v
                }
            }
            return map
        }()

        func stringHeader(_ key: String) -> String? {
            normalized[key.lowercased()]
        }

        func doubleHeader(_ key: String) -> Double {
            guard let val = normalized[key.lowercased()] else { return 0 }
            return Double(val) ?? 0
        }

        func dateFromUnix(_ key: String) -> Date? {
            guard let val = normalized[key.lowercased()],
                  let ts = TimeInterval(val),
                  ts > 0, ts < Date().timeIntervalSince1970 + 30 * 86400 else { return nil }
            return Date(timeIntervalSince1970: ts)
        }

        // Detect unified headers
        guard let status = stringHeader("anthropic-ratelimit-unified-status") else {
            return nil
        }

        let representativeClaim = stringHeader("anthropic-ratelimit-unified-representative-claim") ?? fiveHourWindow

        return RateLimitUsage(
            representativeClaim: representativeClaim,
            fiveHourUtilization: min(max(doubleHeader("anthropic-ratelimit-unified-5h-utilization"), 0), 1),
            fiveHourReset: dateFromUnix("anthropic-ratelimit-unified-5h-reset"),
            fiveHourStatus: inferredWindowStatus(
                explicitStatus: stringHeader("anthropic-ratelimit-unified-5h-status"),
                overallStatus: status,
                representativeClaim: representativeClaim,
                window: fiveHourWindow
            ),
            sevenDayUtilization: min(max(doubleHeader("anthropic-ratelimit-unified-7d-utilization"), 0), 1),
            sevenDayReset: dateFromUnix("anthropic-ratelimit-unified-7d-reset"),
            sevenDayStatus: inferredWindowStatus(
                explicitStatus: stringHeader("anthropic-ratelimit-unified-7d-status"),
                overallStatus: status,
                representativeClaim: representativeClaim,
                window: sevenDayWindow
            ),
            overallStatus: status
        )
    }

    /// Parse Claude Code's JSON usage payload as a fallback when Anthropic no
    /// longer exposes unified 5h/7d windows in response headers.
    static func parse(clientData data: Data) -> RateLimitUsage? {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return parse(clientDataJSON: json)
    }

    private static func parse(clientDataJSON json: Any) -> RateLimitUsage? {
        func normalizedKeys(from dictionary: [String: Any]) -> [String: Any] {
            var result: [String: Any] = [:]
            for (key, value) in dictionary {
                let normalized = key.lowercased().replacingOccurrences(of: "-", with: "_")
                result[normalized] = value
            }
            return result
        }

        func dictionary(_ value: Any?) -> [String: Any]? {
            guard let value = value as? [String: Any] else { return nil }
            return normalizedKeys(from: value)
        }

        func string(_ value: Any?) -> String? {
            if let value = value as? String, !value.isEmpty { return value }
            return nil
        }

        func parseDate(_ value: Any?) -> Date? {
            if let number = value as? NSNumber {
                let raw = number.doubleValue
                let seconds = raw > 10_000_000_000 ? raw / 1000.0 : raw
                return Date(timeIntervalSince1970: seconds)
            }
            if let text = value as? String {
                if let unix = TimeInterval(text) {
                    let seconds = unix > 10_000_000_000 ? unix / 1000.0 : unix
                    return Date(timeIntervalSince1970: seconds)
                }
                let iso = ISO8601DateFormatter()
                iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let date = iso.date(from: text) { return date }
                iso.formatOptions = [.withInternetDateTime]
                if let date = iso.date(from: text) { return date }
            }
            return nil
        }

        func parseUtilization(_ value: Any?) -> Double? {
            let raw: Double? = {
                if let number = value as? NSNumber { return number.doubleValue }
                if let text = value as? String { return Double(text) }
                return nil
            }()
            guard let raw else { return nil }
            let normalized = raw > 1.0 ? raw / 100.0 : raw
            return min(max(normalized, 0), 1)
        }

        func lookup(in json: Any, path: [String]) -> Any? {
            guard !path.isEmpty else { return json }
            guard let dict = dictionary(json) else { return nil }
            guard let value = dict[path[0]] else { return nil }
            return lookup(in: value, path: Array(path.dropFirst()))
        }

        func firstValue(in json: Any, paths: [[String]]) -> Any? {
            for path in paths {
                if let value = lookup(in: json, path: path) { return value }
            }
            return nil
        }

        let fiveHourUtilization = parseUtilization(firstValue(in: json, paths: [
            ["rate_limits", "five_hour", "utilization"],
            ["rate_limits", "five_hour", "usage"],
            ["rate_limits", "5h", "utilization"],
            ["rate_limits", "5h", "usage"],
            ["usage", "five_hour", "utilization"],
            ["usage", "five_hour", "usage"],
            ["usage", "5h", "utilization"],
            ["usage", "5h", "usage"],
            ["five_hour", "utilization"],
            ["five_hour", "usage"],
            ["5h", "utilization"],
            ["5h", "usage"],
        ]))

        let sevenDayUtilization = parseUtilization(firstValue(in: json, paths: [
            ["rate_limits", "seven_day", "utilization"],
            ["rate_limits", "seven_day", "usage"],
            ["rate_limits", "7d", "utilization"],
            ["rate_limits", "7d", "usage"],
            ["usage", "seven_day", "utilization"],
            ["usage", "seven_day", "usage"],
            ["usage", "7d", "utilization"],
            ["usage", "7d", "usage"],
            ["seven_day", "utilization"],
            ["seven_day", "usage"],
            ["7d", "utilization"],
            ["7d", "usage"],
        ]))

        guard fiveHourUtilization != nil || sevenDayUtilization != nil else { return nil }

        let fiveHourReset = parseDate(firstValue(in: json, paths: [
            ["rate_limits", "five_hour", "reset"],
            ["rate_limits", "five_hour", "reset_at"],
            ["rate_limits", "five_hour", "resets_at"],
            ["rate_limits", "5h", "reset"],
            ["rate_limits", "5h", "reset_at"],
            ["usage", "five_hour", "reset"],
            ["usage", "five_hour", "reset_at"],
            ["usage", "five_hour", "resets_at"],
            ["usage", "5h", "reset"],
            ["usage", "5h", "reset_at"],
            ["five_hour", "reset"],
            ["five_hour", "reset_at"],
            ["five_hour", "resets_at"],
            ["5h", "reset"],
            ["5h", "reset_at"],
        ]))

        let sevenDayReset = parseDate(firstValue(in: json, paths: [
            ["rate_limits", "seven_day", "reset"],
            ["rate_limits", "seven_day", "reset_at"],
            ["rate_limits", "seven_day", "resets_at"],
            ["rate_limits", "7d", "reset"],
            ["rate_limits", "7d", "reset_at"],
            ["usage", "seven_day", "reset"],
            ["usage", "seven_day", "reset_at"],
            ["usage", "seven_day", "resets_at"],
            ["usage", "7d", "reset"],
            ["usage", "7d", "reset_at"],
            ["seven_day", "reset"],
            ["seven_day", "reset_at"],
            ["seven_day", "resets_at"],
            ["7d", "reset"],
            ["7d", "reset_at"],
        ]))

        let overallStatus = string(firstValue(in: json, paths: [
            ["rate_limits", "status"],
            ["usage", "status"],
            ["status"],
        ]))

        let fiveHourStatus = string(firstValue(in: json, paths: [
            ["rate_limits", "five_hour", "status"],
            ["rate_limits", "5h", "status"],
            ["usage", "five_hour", "status"],
            ["usage", "5h", "status"],
            ["five_hour", "status"],
            ["5h", "status"],
        ]))

        let sevenDayStatus = string(firstValue(in: json, paths: [
            ["rate_limits", "seven_day", "status"],
            ["rate_limits", "7d", "status"],
            ["usage", "seven_day", "status"],
            ["usage", "7d", "status"],
            ["seven_day", "status"],
            ["7d", "status"],
        ]))

        let representativeClaim = string(firstValue(in: json, paths: [
            ["rate_limits", "representative_claim"],
            ["rate_limits", "binding_window"],
            ["usage", "representative_claim"],
            ["usage", "binding_window"],
            ["representative_claim"],
            ["binding_window"],
        ])) ?? {
            let five = fiveHourUtilization ?? 0
            let seven = sevenDayUtilization ?? 0
            return seven > five ? sevenDayWindow : fiveHourWindow
        }()

        let inferredOverallStatus: String = {
            if overallStatus == "throttled" || fiveHourStatus == "throttled" || sevenDayStatus == "throttled" {
                return "throttled"
            }
            if (fiveHourUtilization ?? 0) >= 1.0 || (sevenDayUtilization ?? 0) >= 1.0 {
                return "throttled"
            }
            return overallStatus ?? "allowed"
        }()

        let normalizedRepresentativeClaim = representativeClaim == sevenDayWindow ? sevenDayWindow : fiveHourWindow

        return RateLimitUsage(
            representativeClaim: normalizedRepresentativeClaim,
            fiveHourUtilization: fiveHourUtilization ?? 0,
            fiveHourReset: fiveHourReset,
            fiveHourStatus: inferredWindowStatus(
                explicitStatus: fiveHourStatus,
                overallStatus: inferredOverallStatus,
                representativeClaim: normalizedRepresentativeClaim,
                window: fiveHourWindow
            ),
            sevenDayUtilization: sevenDayUtilization ?? 0,
            sevenDayReset: sevenDayReset,
            sevenDayStatus: inferredWindowStatus(
                explicitStatus: sevenDayStatus,
                overallStatus: inferredOverallStatus,
                representativeClaim: normalizedRepresentativeClaim,
                window: sevenDayWindow
            ),
            overallStatus: inferredOverallStatus
        )
    }
}

import Foundation

nonisolated enum CodexUsageParser {
    // MARK: - Public Interfaces

    /// Parse wham/usage JSON response body.
    nonisolated static func parseUsageResponse(_ data: Data) -> RateLimitUsage? {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return nil }
        guard let dict = json as? [String: Any] else { return nil }

        guard let rateLimit = dict["rate_limit"] as? [String: Any] else { return nil }

        let primary = rateLimit["primary_window"]
        let secondary = rateLimit["secondary_window"]

        let reachedType = dict["rate_limit_reached_type"] as? String

        return assemble(primaryAny: primary, secondaryAny: secondary, reachedType: reachedType)
    }

    /// Parse rate_limits from session-log token_count event.
    nonisolated static func parseSessionRateLimits(_ rateLimits: [String: Any]) -> RateLimitUsage? {
        let primary = rateLimits["primary"]
        let secondary = rateLimits["secondary"]
        let reachedType = rateLimits["rate_limit_reached_type"] as? String

        return assemble(primaryAny: primary, secondaryAny: secondary, reachedType: reachedType)
    }

    /// Extract plan_type from wham/usage JSON.
    nonisolated static func planType(_ data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return nil }
        guard let dict = json as? [String: Any] else { return nil }
        return dict["plan_type"] as? String
    }

    // MARK: - Private Helpers

    private struct WindowData {
        let utilization: Double
        let reset: Date?
        let windowMinutes: Int?
    }

    /// Extract window data from a rate limit window dictionary.
    /// Handles:
    /// - used_percent as Int or Double (0-100, divide by 100)
    /// - reset_at or resets_at (epoch seconds)
    /// - limit_window_seconds (→ /60) or window_minutes
    private nonisolated static func parseWindow(_ window: [String: Any]?) -> WindowData? {
        guard let window else { return nil }

        // Parse used_percent: accept Int or Double
        let usedPercentRaw: Double? = if let intVal = window["used_percent"] as? Int {
            Double(intVal)
        } else if let doubleVal = window["used_percent"] as? Double {
            doubleVal
        } else {
            nil
        }

        guard let usedPercentRaw else { return nil }
        let utilization = min(max(usedPercentRaw / 100.0, 0), 1)

        // Parse reset timestamp: accept reset_at or resets_at (epoch seconds)
        let resetTimestamp: TimeInterval? = {
            if let val = window["reset_at"] as? TimeInterval {
                return val
            }
            if let val = window["reset_at"] as? Int {
                return TimeInterval(val)
            }
            if let val = window["resets_at"] as? TimeInterval {
                return val
            }
            if let val = window["resets_at"] as? Int {
                return TimeInterval(val)
            }
            return nil
        }()
        let reset = resetTimestamp.map { Date(timeIntervalSince1970: $0) }

        // Parse window minutes: accept limit_window_seconds (→ /60) or window_minutes
        let windowMinutes: Int? = {
            // Try limit_window_seconds first
            if let seconds = window["limit_window_seconds"] as? Int {
                return seconds / 60
            }
            if let seconds = window["limit_window_seconds"] as? NSNumber {
                return seconds.intValue / 60
            }
            // Then try window_minutes
            if let minutes = window["window_minutes"] as? Int {
                return minutes
            }
            if let minutes = window["window_minutes"] as? NSNumber {
                return minutes.intValue
            }
            return nil
        }()

        return WindowData(utilization: utilization, reset: reset, windowMinutes: windowMinutes)
    }

    /// Assemble final RateLimitUsage from parsed primary/secondary windows and throttle type.
    /// Implements the full semantics table from the brief.
    private nonisolated static func assemble(
        primaryAny: Any?,
        secondaryAny: Any?,
        reachedType: String?
    ) -> RateLimitUsage? {
        let primary = primaryAny as? [String: Any]
        let secondary = secondaryAny as? [String: Any]
        let primaryData = parseWindow(primary)
        let secondaryData = parseWindow(secondary)

        // Missing both windows → nil
        guard primaryData != nil || secondaryData != nil else { return nil }

        let fiveHourUtil = primaryData?.utilization ?? 0
        let fiveHourReset = primaryData?.reset
        let fiveHourMinutes = primaryData?.windowMinutes

        let sevenDayUtil = secondaryData?.utilization ?? 0
        let sevenDayReset = secondaryData?.reset
        let sevenDayMinutes = secondaryData?.windowMinutes

        // representativeClaim: seven_day only if strictly greater, else five_hour
        let representativeClaim = sevenDayUtil > fiveHourUtil ? RateLimitUsage.sevenDayWindow : RateLimitUsage.fiveHourWindow

        // Determine throttle status:
        // - Window at used_percent >= 100 → throttled
        // - non-null rate_limit_reached_type → throttle named window (or binding if unrecognized)
        var fiveHourThrottled = primaryData != nil && fiveHourUtil >= 1.0
        var sevenDayThrottled = secondaryData != nil && sevenDayUtil >= 1.0

        if let reachedType {
            if reachedType == "five_hour" || reachedType == "5h" {
                fiveHourThrottled = true
            } else if reachedType == "seven_day" || reachedType == "7d" {
                sevenDayThrottled = true
            } else {
                // Unrecognized type → throttle the binding window
                if representativeClaim == RateLimitUsage.sevenDayWindow {
                    sevenDayThrottled = true
                } else {
                    fiveHourThrottled = true
                }
            }
        }

        let overallStatus = (fiveHourThrottled || sevenDayThrottled) ? "throttled" : "allowed"

        // One missing window → utilization 0, reset nil, status "allowed"
        let fiveHourStatus = primaryData == nil ? "allowed" : (fiveHourThrottled ? "throttled" : "allowed")
        let sevenDayStatus = secondaryData == nil ? "allowed" : (sevenDayThrottled ? "throttled" : "allowed")

        return RateLimitUsage(
            representativeClaim: representativeClaim,
            fiveHourUtilization: fiveHourUtil,
            fiveHourReset: fiveHourReset,
            fiveHourStatus: fiveHourStatus,
            sevenDayUtilization: sevenDayUtil,
            sevenDayReset: sevenDayReset,
            sevenDayStatus: sevenDayStatus,
            overallStatus: overallStatus,
            provider: .codex,
            fiveHourWindowMinutes: fiveHourMinutes,
            sevenDayWindowMinutes: sevenDayMinutes
        )
    }
}

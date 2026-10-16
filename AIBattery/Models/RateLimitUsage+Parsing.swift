import Foundation

/// Parsing `RateLimitUsage` out of the wire formats: the unified rate-limit response
/// headers, and the Claude Code `client_data` JSON with its path tables.
///
/// Split out of `RateLimitUsage.swift` so the model and its normalisation helpers stay
/// readable on their own; the file was 646 lines against the 200–400 the project aims
/// for. Pure functions only — no state, no I/O.
extension RateLimitUsage {
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
                  ts > 0, ts < Date().timeIntervalSince1970 + 8 * 86_400 else { return nil }
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
            if let value = value as? String, !value.isEmpty {
                return value
            }
            return nil
        }

        func parseDate(_ value: Any?) -> Date? {
            if let number = value as? NSNumber {
                let raw = number.doubleValue
                let seconds = raw > 10_000_000_000 ? raw / 1_000.0 : raw
                return Date(timeIntervalSince1970: seconds)
            }
            if let text = value as? String {
                if let unix = TimeInterval(text) {
                    let seconds = unix > 10_000_000_000 ? unix / 1_000.0 : unix
                    return Date(timeIntervalSince1970: seconds)
                }
                if let date = DateFormatters.parseISO8601(text) {
                    return date
                }
            }
            return nil
        }

        func parseUtilization(_ value: Any?) -> Double? {
            let raw: Double? = {
                if let number = value as? NSNumber {
                    return number.doubleValue
                }
                if let text = value as? String {
                    return Double(text)
                }
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
                if let value = lookup(in: json, path: path) {
                    return value
                }
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
            // Throttle is signalled ONLY by an explicit "throttled" status (or, elsewhere,
            // a real HTTP 429 via `markedThrottled`). 100% utilization means "at capacity",
            // not throttled — the user can typically keep working — so it must NOT synthesize
            // a throttled status here.
            if overallStatus == "throttled" || fiveHourStatus == "throttled" || sevenDayStatus == "throttled" {
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

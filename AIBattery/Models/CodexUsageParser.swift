import Foundation

nonisolated enum CodexUsageParser {
    // MARK: - Public Interfaces

    /// Parse wham/usage JSON response body.
    nonisolated static func parseUsageResponse(_ data: Data) -> RateLimitUsage? {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return nil }
        guard let dict = json as? [String: Any] else { return nil }

        let reachedType = dict["rate_limit_reached_type"] as? String
        let budget = parseCreditBudget(dict)

        // Windowed plans (Plus / Pro / Team): primary + secondary windows.
        if let rateLimit = dict["rate_limit"] as? [String: Any],
           let windowed = assemble(primaryAny: rateLimit["primary_window"], secondaryAny: rateLimit["secondary_window"], reachedType: reachedType, budget: budget) {
            return windowed
        }

        // Spend-control plans (Business / Enterprise): `rate_limit` is null and the
        // budget lives in `spend_control.individual_limit`. Mirror it onto both windows.
        guard let budget, budget.limit > 0 else { return nil }
        let utilization = min(max(budget.usedPercent / 100.0, 0), 1)
        let throttled = budget.reached || !budget.hasCredits || reachedType != nil
        let status = throttled ? "throttled" : "allowed"
        return RateLimitUsage(
            representativeClaim: RateLimitUsage.sevenDayWindow,
            fiveHourUtilization: utilization,
            fiveHourReset: budget.resetsAt,
            fiveHourStatus: status,
            sevenDayUtilization: utilization,
            sevenDayReset: budget.resetsAt,
            sevenDayStatus: status,
            overallStatus: status,
            provider: .codex,
            creditBudget: budget
        )
    }

    /// `spend_control.individual_limit` + `credits` → `CodexCreditBudget`. Numbers arrive
    /// as strings ("32768", "7006.29…") or numbers; both are accepted. Without a
    /// spend-control limit, a subscription plan's purchased-credit `balance` yields a
    /// balance-only record (limit 0) so the UI can show it under the windows.
    nonisolated static func parseCreditBudget(_ dict: [String: Any]) -> CodexCreditBudget? {
        func number(_ value: Any?) -> Double? {
            if let n = value as? NSNumber {
                return n.doubleValue
            }
            if let s = value as? String {
                return Double(s)
            }
            return nil
        }
        let credits = dict["credits"] as? [String: Any]
        let spend = dict["spend_control"] as? [String: Any]
        let planType = dict["plan_type"] as? String
        guard let limit = spend?["individual_limit"] as? [String: Any],
              let limitValue = number(limit["limit"]), limitValue > 0 else {
            guard let credits, let balance = number(credits["balance"]) else { return nil }
            return CodexCreditBudget(
                usedPercent: 0, used: 0, limit: 0, remaining: balance, unit: "credit", resetsAt: nil,
                reached: false,
                hasCredits: (credits["has_credits"] as? Bool) ?? true,
                unlimited: (credits["unlimited"] as? Bool) ?? false,
                planType: planType,
                balance: balance
            )
        }
        let used = number(limit["used"]) ?? 0
        let remaining = number(limit["remaining"]) ?? max(0, limitValue - used)
        let usedPercent = number(limit["used_percent"]) ?? (used / limitValue * 100)
        return CodexCreditBudget(
            usedPercent: min(max(usedPercent, 0), 100),
            used: used,
            limit: limitValue,
            remaining: remaining,
            unit: (limit["unit"] as? String) ?? "credit",
            resetsAt: number(limit["reset_at"]).map { Date(timeIntervalSince1970: $0) },
            reached: (spend?["reached"] as? Bool) ?? false,
            hasCredits: (credits?["has_credits"] as? Bool) ?? true,
            unlimited: (credits?["unlimited"] as? Bool) ?? false,
            planType: planType,
            balance: number(credits?["balance"])
        )
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
        reachedType: String?,
        budget: CodexCreditBudget? = nil
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
            sevenDayWindowMinutes: sevenDayMinutes,
            creditBudget: budget
        )
    }
}

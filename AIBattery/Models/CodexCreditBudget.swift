import Foundation

/// A Codex credit budget — what Business / Enterprise ChatGPT plans report instead of
/// 5-hour / weekly rate-limit windows. Parsed from `spend_control.individual_limit`
/// (+ `credits`) in the `wham/usage` payload. Amounts are in `unit` (observed: "credit").
struct CodexCreditBudget: Codable, Equatable, Sendable {
    /// 0–100, as reported (`used_percent`).
    let usedPercent: Double
    let used: Double
    let limit: Double
    let remaining: Double
    let unit: String
    /// When the budget period rolls over (`reset_at`, epoch seconds).
    let resetsAt: Date?
    /// `spend_control.reached` — the workspace/individual cap is hit.
    let reached: Bool
    /// `credits.has_credits` — false when the workspace's credits are depleted.
    let hasCredits: Bool
    /// `credits.unlimited`.
    let unlimited: Bool
    let planType: String?
    /// Purchased-credit balance (`credits.balance`) on subscription plans — spent only once
    /// the rate-limit windows are exhausted. nil when the plan doesn't report one.
    var balance: Double? = nil
    /// True when the plan reports neither rate-limit windows nor an individual spend cap
    /// (a Business / Enterprise workspace without spend controls): a healthy account with
    /// nothing to meter. `limit` is 0 and `usedPercent` is 0 in that case. Optional so
    /// blobs persisted before the field existed still decode.
    var uncapped: Bool? = nil
    /// `limit_name` from the payload (e.g. a workspace's named spend cap). Optional so
    /// persisted blobs decode.
    var limitName: String? = nil
    /// First reading AI Battery saw in the current budget period: the baseline for the
    /// runway estimate. Carried across readings while `resetsAt` is unchanged. Optional
    /// so persisted blobs decode.
    var periodAnchor: PeriodAnchor? = nil

    var isUncapped: Bool { uncapped == true }

    struct PeriodAnchor: Codable, Equatable, Sendable {
        let at: Date
        let used: Double
        let resetsAt: Date?
    }

    /// Carry the cached reading's anchor when it is the same period; otherwise start one.
    func anchored(from cached: CodexCreditBudget?, now: Date) -> CodexCreditBudget {
        var copy = self
        if let anchor = cached?.periodAnchor, anchor.resetsAt == resetsAt, anchor.used <= used {
            copy.periodAnchor = anchor
        } else {
            copy.periodAnchor = PeriodAnchor(at: now, used: used, resetsAt: resetsAt)
        }
        return copy
    }

    /// "~N to limit" for a capped budget at the pace observed since `periodAnchor`.
    /// nil until an hour of observation, with no spend, when nothing remains, or when
    /// the projection lands after the period resets (the reset gets there first).
    func estimatedTimeToExhaustion(now: Date) -> TimeInterval? {
        guard !isUncapped, limit > 0, remaining > 0, let anchor = periodAnchor else { return nil }
        let elapsed = now.timeIntervalSince(anchor.at)
        guard elapsed >= RateLimitUsage.creditRunwayMinObservation else { return nil }
        let spent = used - anchor.used
        guard spent > 0 else { return nil }
        let rate = spent / elapsed
        let eta = remaining / rate
        if let resetsAt, now.addingTimeInterval(eta) >= resetsAt {
            return nil
        }
        return eta
    }

    /// The budget after its period has rolled over and no fresh reading has arrived
    /// yet: nothing used, nothing reached, no reset to count down to. The cap, unit,
    /// plan, purchased-credit balance and uncapped flag are properties of the plan,
    /// not of the period, so they survive. Mirrors `withClearedExpiredWindows` on the
    /// windows the budget is projected onto — without it the popover's Credits bar
    /// kept reading the stale object ("Budget reached", old used / remaining) while
    /// the menu bar had already rolled over to 0%.
    func rolledOver() -> CodexCreditBudget {
        var next = CodexCreditBudget(
            usedPercent: 0,
            used: 0,
            limit: limit,
            remaining: limit,
            unit: unit,
            resetsAt: nil,
            reached: false,
            hasCredits: hasCredits,
            unlimited: unlimited,
            planType: planType
        )
        next.balance = balance
        next.uncapped = uncapped
        next.limitName = limitName
        return next
    }

    /// Human-readable credit amounts: 7 006.3 → "7.0K", 32 768 → "32.8K", 950 → "950".
    static func formatCredits(_ value: Double) -> String {
        let magnitude = abs(value)
        if magnitude >= 1_000_000 {
            return String(format: "%.1fM", value / 1_000_000)
        }
        if magnitude >= 1_000 {
            return String(format: "%.1fK", value / 1_000)
        }
        return String(format: "%.0f", value)
    }
}

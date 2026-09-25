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

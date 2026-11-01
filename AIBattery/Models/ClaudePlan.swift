import Foundation

/// A Claude account's subscription plan, read from Anthropic's OAuth profile
/// (`GET /api/oauth/profile`, the endpoint Claude Code itself reads its plan from).
///
/// The plan is stored on `AccountRecord.billingType` as a short normalized string
/// (`"pro"`, `"max_5x"`, `"max_20x"`, `"max"`, `"team"`, `"enterprise"`), the same field
/// Codex's `plan_type` lands in. The Max values are deliberately the ones
/// `PlanTier(billingType:)` already parses, so a known plan also gives the local
/// estimates their per-account tier instead of the global Settings choice.
///
/// Conservative on both ends: an unrecognised `organization_type` yields no plan rather
/// than a guess, and `label` only names values this type writes. A legacy string from
/// the pre-multi-account migration (`aibattery_plan`) is never shown.
enum ClaudePlan {
    /// The `billingType` to store for a profile response body, or nil when the body is
    /// malformed or names no known plan.
    nonisolated static func billingType(fromProfile data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let organization = json["organization"] as? [String: Any]
        else { return nil }
        return billingType(
            organizationType: organization["organization_type"] as? String,
            rateLimitTier: organization["rate_limit_tier"] as? String
        )
    }

    /// `organization_type` names the plan; for Max, `rate_limit_tier` says which one.
    nonisolated static func billingType(organizationType: String?, rateLimitTier: String?) -> String? {
        switch organizationType {
        case "claude_pro": "pro"
        case "claude_team": "team"
        case "claude_enterprise": "enterprise"
        case "claude_max":
            switch rateLimitTier {
            case "default_claude_max_5x": "max_5x"
            case "default_claude_max_20x": "max_20x"
            default: "max"
            }
        default: nil
        }
    }

    /// "Pro", "Max 5×", "Max 20×", "Max", "Team", "Enterprise"; nil for anything else.
    nonisolated static func label(_ billingType: String?) -> String? {
        guard let billingType else { return nil }
        if let tier = PlanTier(billingType: billingType) {
            return tier.displayName
        }
        switch billingType {
        case "max": return "Max"
        case "enterprise": return "Enterprise"
        default: return nil
        }
    }
}

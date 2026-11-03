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
/// What one profile response says about an account: its plan, and who it belongs to.
struct ClaudeProfileFacts: Equatable {
    /// Normalized `billingType`, nil when the body names no plan this app knows.
    let billingType: String?
    /// The account's sign-in email (`account.email_address`), falling back to the
    /// organization name. This is the only place Anthropic's OAuth names a Claude
    /// account: there is no email on any usage response, which is why a Claude account
    /// used to have nothing but a workspace name — and nothing at all when the usage
    /// payload carried no workspace either.
    let identity: String?

    static let none = ClaudeProfileFacts(billingType: nil, identity: nil)
}

enum ClaudePlan {
    /// Plan + identity from a profile response body.
    nonisolated static func facts(fromProfile data: Data) -> ClaudeProfileFacts {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .none
        }
        let organization = json["organization"] as? [String: Any]
        let account = json["account"] as? [String: Any]
        // `email_address` is the field name in the profile body; `email` is accepted in
        // case the shape ever shortens. The organization name is the fallback, matching
        // what the usage path already stored for Claude.
        let email = sanitized(account?["email_address"] as? String) ?? sanitized(account?["email"] as? String)
        return ClaudeProfileFacts(
            billingType: billingType(
                organizationType: organization?["organization_type"] as? String,
                rateLimitTier: organization?["rate_limit_tier"] as? String
            ),
            identity: email ?? sanitized(organization?["name"] as? String)
        )
    }

    /// Trimmed and bounded — an identity is drawn in a 275pt popover, and an empty or
    /// absurd string is worse than none.
    private nonisolated static func sanitized(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty, trimmed.count <= 256 else { return nil }
        return trimmed
    }

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

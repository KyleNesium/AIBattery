import Foundation
import Testing
@testable import AIBatteryCore

@Suite("ClaudePlan")
struct ClaudePlanTests {
    /// A profile body shaped like Anthropic's: `account` + `organization`.
    private func profile(_ type: String?, tier: String? = nil) -> Data {
        var fields = [#""uuid":"org-1""#, #""name":"Personal""#]
        if let type {
            fields.append(#""organization_type":"\#(type)""#)
        }
        if let tier {
            fields.append(#""rate_limit_tier":"\#(tier)""#)
        }
        return Data(#"{"account":{"uuid":"acct-1"},"organization":{\#(fields.joined(separator: ","))}}"#.utf8)
    }

    // MARK: - Profile → stored billingType (the mapping Claude Code itself uses)

    @Test func max_isSplitByRateLimitTier() {
        #expect(ClaudePlan.billingType(fromProfile: profile("claude_max", tier: "default_claude_max_20x")) == "max_20x")
        #expect(ClaudePlan.billingType(fromProfile: profile("claude_max", tier: "default_claude_max_5x")) == "max_5x")
        // A Max org with a tier we don't know is still Max, just without the multiplier.
        #expect(ClaudePlan.billingType(fromProfile: profile("claude_max", tier: "default_claude_max_99x")) == "max")
        #expect(ClaudePlan.billingType(fromProfile: profile("claude_max")) == "max")
    }

    @Test func otherPlans_mapByOrganizationType() {
        #expect(ClaudePlan.billingType(fromProfile: profile("claude_pro")) == "pro")
        #expect(ClaudePlan.billingType(fromProfile: profile("claude_team")) == "team")
        #expect(ClaudePlan.billingType(fromProfile: profile("claude_enterprise")) == "enterprise")
    }

    /// Never a guess: anything not recognised, or not shaped like a profile, yields nil.
    @Test func unknownOrMalformed_yieldsNoPlan() {
        #expect(ClaudePlan.billingType(fromProfile: profile("claude_free")) == nil)
        #expect(ClaudePlan.billingType(fromProfile: profile(nil)) == nil)
        #expect(ClaudePlan.billingType(fromProfile: Data("not json".utf8)) == nil)
        #expect(ClaudePlan.billingType(fromProfile: Data(#"{"organization":"claude_max"}"#.utf8)) == nil)
        #expect(ClaudePlan.billingType(fromProfile: Data(#"{"organization":{"organization_type":7}}"#.utf8)) == nil)
        #expect(ClaudePlan.billingType(fromProfile: Data(#"[]"#.utf8)) == nil)
    }

    // MARK: - Stored billingType → label

    @Test func label_namesEveryValueTheParserWrites() {
        #expect(ClaudePlan.label("pro") == "Pro")
        #expect(ClaudePlan.label("max_5x") == "Max 5×")
        #expect(ClaudePlan.label("max_20x") == "Max 20×")
        #expect(ClaudePlan.label("max") == "Max")
        #expect(ClaudePlan.label("team") == "Team")
        #expect(ClaudePlan.label("enterprise") == "Enterprise")
    }

    /// The pre-multi-account migration copied an unvalidated `aibattery_plan` string
    /// into `billingType`; it must never surface as a plan.
    @Test func label_ignoresLegacyAndUnknownStrings() {
        #expect(ClaudePlan.label("stripe_subscription") == nil)
        #expect(ClaudePlan.label("business") == nil)
        #expect(ClaudePlan.label("") == nil)
        #expect(ClaudePlan.label(nil) == nil)
    }

    /// The stored Max values are the ones `PlanTier` parses, so a looked-up plan also
    /// drives that account's local estimates.
    @Test func storedValues_feedPlanTier() {
        #expect(PlanTier(billingType: "pro") == .pro)
        #expect(PlanTier(billingType: "max_5x") == .max5x)
        #expect(PlanTier(billingType: "max_20x") == .max20x)
        #expect(PlanTier(billingType: "team") == .team)
    }
}

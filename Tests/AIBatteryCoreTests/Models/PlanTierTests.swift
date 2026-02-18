import Testing
@testable import AIBatteryCore

@Suite("PlanTier")
struct PlanTierTests {

    // MARK: - Known billing types

    @Test func fromBillingType_pro() {
        let tier = PlanTier.fromBillingType("pro")
        #expect(tier?.name == "Pro")
        #expect(tier?.price == "$20/mo")
    }

    @Test func fromBillingType_proUppercase() {
        let tier = PlanTier.fromBillingType("Pro")
        #expect(tier?.name == "Pro")
    }

    @Test func fromBillingType_max() {
        let tier = PlanTier.fromBillingType("max")
        #expect(tier?.name == "Max")
        #expect(tier?.price == "$100/mo per seat")
    }

    @Test func fromBillingType_max5x() {
        let tier = PlanTier.fromBillingType("max_5x")
        #expect(tier?.name == "Max")
    }

    @Test func fromBillingType_teams() {
        let tier = PlanTier.fromBillingType("teams")
        #expect(tier?.name == "Teams")
        #expect(tier?.price == "$30/mo per seat")
    }

    @Test func fromBillingType_team() {
        let tier = PlanTier.fromBillingType("team")
        #expect(tier?.name == "Teams")
    }

    @Test func fromBillingType_free() {
        let tier = PlanTier.fromBillingType("free")
        #expect(tier?.name == "Free")
        #expect(tier?.price == nil)
    }

    @Test func fromBillingType_apiEvaluation() {
        let tier = PlanTier.fromBillingType("api_evaluation")
        #expect(tier?.name == "API")
        #expect(tier?.price == "Usage-based")
    }

    @Test func fromBillingType_api() {
        let tier = PlanTier.fromBillingType("api")
        #expect(tier?.name == "API")
    }

    // MARK: - Edge cases

    @Test func fromBillingType_empty() {
        let tier = PlanTier.fromBillingType("")
        #expect(tier == nil)
    }

    @Test func fromBillingType_unknownShowsCapitalized() {
        let tier = PlanTier.fromBillingType("enterprise")
        #expect(tier?.name == "Enterprise")
        #expect(tier?.price == nil)
    }

    @Test func fromBillingType_unknownCasingPreserved() {
        let tier = PlanTier.fromBillingType("customTier")
        // lowercased() falls to default, capitalized first char
        #expect(tier?.name == "CustomTier")
    }
}

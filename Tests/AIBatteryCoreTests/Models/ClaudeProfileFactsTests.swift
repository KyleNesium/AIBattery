import Foundation
import Testing
@testable import AIBatteryCore

/// `GET /api/oauth/profile` is the only Anthropic response that names an account — no
/// usage endpoint carries an email. Before this, a Claude account's identity was
/// whatever workspace name the usage payload happened to include, which for an account
/// with no workspace was nothing at all, and "Show account email" had nothing to show.
@Suite("ClaudePlan profile facts")
struct ClaudeProfileFactsTests {
    private func facts(_ json: String) -> ClaudeProfileFacts {
        ClaudePlan.facts(fromProfile: Data(json.utf8))
    }

    @Test func readsTheSignInEmail() {
        let parsed = facts(#"{"account":{"email_address":"kyle@example.com"}}"#)
        #expect(parsed.identity == "kyle@example.com")
    }

    /// Accepted in case the field name ever shortens; `email_address` is what the
    /// endpoint sends today.
    @Test func acceptsTheShorterFieldName() {
        #expect(facts(#"{"account":{"email":"kyle@example.com"}}"#).identity == "kyle@example.com")
    }

    /// The email outranks the organization name: it identifies the person who signed
    /// in, which is the question two Claude accounts raise. The org name identifies
    /// neither when both accounts are in the same org.
    @Test func theEmailOutranksTheOrganizationName() {
        let parsed = facts(#"{"account":{"email_address":"kyle@example.com"},"organization":{"name":"Ringier"}}"#)
        #expect(parsed.identity == "kyle@example.com")
    }

    /// The fallback is the identity the usage path already stored, so an account that
    /// gets no email is no worse off than before.
    @Test func fallsBackToTheOrganizationName() {
        #expect(facts(#"{"organization":{"name":"Ringier"}}"#).identity == "Ringier")
    }

    @Test func blankAndWhitespaceNamesAreNoIdentity() {
        #expect(facts(#"{"account":{"email_address":"   "},"organization":{"name":""}}"#).identity == nil)
        #expect(facts(#"{"account":{"email_address":"  kyle@example.com "}}"#).identity == "kyle@example.com")
    }

    /// An identity is drawn in a 275pt popover; an absurd string is worse than none.
    @Test func absurdlyLongNamesAreRejected() {
        let long = String(repeating: "a", count: 257)
        #expect(facts(#"{"organization":{"name":"\#(long)"}}"#).identity == nil)
    }

    @Test func nonStringAndMalformedBodiesYieldNothing() {
        #expect(facts(#"{"account":{"email_address":42}}"#).identity == nil)
        #expect(facts("not json") == .none)
        #expect(facts("[]") == .none)
    }

    /// Plan and identity come from one parse of one response — they are two fields of
    /// the same lookup, not two requests.
    @Test func planAndIdentityComeFromTheSameBody() {
        let parsed = facts(#"{"account":{"email_address":"kyle@example.com"},"organization":{"organization_type":"claude_max","rate_limit_tier":"default_claude_max_20x"}}"#)
        #expect(parsed == ClaudeProfileFacts(billingType: "max_20x", identity: "kyle@example.com"))
    }

    /// The existing plan-only entry point still works; it is the same parse.
    @Test func theplanOnlyEntryPointIsUnchanged() {
        let body = Data(#"{"organization":{"organization_type":"claude_pro"}}"#.utf8)
        #expect(ClaudePlan.billingType(fromProfile: body) == "pro")
    }
}

import Foundation
import Testing
@testable import AIBatteryCore

@Suite("ClaudePlanFetcher")
struct ClaudePlanFetcherTests {
    private let maxBody = Data(#"{"organization":{"organization_type":"claude_max","rate_limit_tier":"default_claude_max_20x"}}"#.utf8)

    private func record(_ id: String, _ provider: AIProvider) -> AccountRecord {
        AccountRecord(id: id, addedAt: Date(timeIntervalSince1970: 0), provider: provider)
    }

    // MARK: - Response interpretation

    @Test func success_answersWithThePlan() {
        #expect(
            ClaudePlanFetcher.interpret(statusCode: 200, data: maxBody)
                == .answered(ClaudeProfileFacts(billingType: "max_20x", identity: nil))
        )
    }

    /// A 2xx that names no known plan still settles the lookup — asking again won't help.
    @Test func success_withUnknownPlan_answersNil() {
        #expect(ClaudePlanFetcher.interpret(statusCode: 200, data: Data("{}".utf8)) == .answered(.none))
    }

    /// The whole reason this request exists for identity: no Anthropic *usage* endpoint
    /// carries an email, so without the profile a Claude account has nothing to show.
    @Test func success_carriesTheSignInEmail() {
        let body = Data(#"{"account":{"email_address":"kyle@example.com"},"organization":{"organization_type":"claude_team","name":"Ringier"}}"#.utf8)
        #expect(
            ClaudePlanFetcher.interpret(statusCode: 200, data: body)
                == .answered(ClaudeProfileFacts(billingType: "team", identity: "kyle@example.com"))
        )
    }

    /// Refusals are final for this launch: retrying a 403 every cycle would only spam.
    @Test func refusals_areNotRetried() {
        for status in [401, 403, 404] {
            #expect(ClaudePlanFetcher.interpret(statusCode: status, data: maxBody) == .rejected)
        }
    }

    @Test func throttleAndServerErrors_areRetried() {
        for status in [429, 500, 503] {
            #expect(ClaudePlanFetcher.interpret(statusCode: status, data: maxBody) == .unavailable)
        }
    }

    // MARK: - Which accounts get a lookup

    @Test func onlySignedInResolvedClaudeAccounts_needAPlan() {
        let accounts = [
            record("c1", .claude),
            record("x1", .codex),
            record("pending-abc", .claude),
            record("c2", .claude),
            record("c3", .claude),
        ]
        let ids = ClaudePlanFetcher.accountsNeedingPlan(
            accounts,
            settled: ["c2"],
            isAuthenticated: { $0 != "c3" }
        )
        #expect(ids == ["c1"])
    }

    /// After every account has settled, a refresh cycle costs a set lookup and nothing else.
    @Test func settledAccounts_needNothing() {
        let accounts = [record("c1", .claude), record("c2", .claude)]
        #expect(ClaudePlanFetcher.accountsNeedingPlan(accounts, settled: ["c1", "c2"], isAuthenticated: { _ in true }).isEmpty)
    }

    /// An account inside its backoff window is skipped. `.unavailable` (429/5xx/transport)
    /// does not settle the account — the plan is still unknown and worth retrying — so
    /// without this the fan-out tail would re-request it on every single poll, against an
    /// endpoint that is already failing.
    @Test func accountsNeedingPlan_skipsAnAccountInsideItsBackoffWindow() {
        let accounts = [
            record("c1", .claude),
            record("c2", .claude),
        ]
        let ids = ClaudePlanFetcher.accountsNeedingPlan(
            accounts,
            settled: [],
            isAuthenticated: { _ in true },
            isBackingOff: { $0 == "c1" }
        )
        #expect(ids == ["c2"])
    }

    /// Backoff is a delay, not a verdict: once the window passes the account is eligible
    /// again, because its plan was never learned.
    @Test func accountsNeedingPlan_returnsAnAccountOnceItsBackoffExpires() {
        let accounts = [record("c1", .claude)]
        let failed = EndpointBackoff.recordingFailure(EndpointBackoff(), now: Date())
        let stillBacking = EndpointBackoff.shouldSkip(failed, now: Date())
        let expired = EndpointBackoff.shouldSkip(failed, now: Date().addingTimeInterval(600))
        #expect(stillBacking)
        #expect(!expired)
        #expect(ClaudePlanFetcher.accountsNeedingPlan(
            accounts, settled: [], isAuthenticated: { _ in true }, isBackingOff: { _ in expired }
        ) == ["c1"])
    }

    @Test func profileURL_isTheOAuthProfileEndpoint() {
        #expect(ClaudePlanFetcher.profileURL.absoluteString == "https://api.anthropic.com/api/oauth/profile")
    }

    /// The outcome is interpolated into a `privacy: .public` log line, and its payload
    /// carries the account's sign-in email. Anything that reproduces that email — which
    /// the synthesised `description` does — puts it in the unified log in the clear.
    @Test func logDescription_namesThePlanButNeverTheEmail() {
        let facts = ClaudeProfileFacts(billingType: "max_20x", identity: "someone@example.com")
        let answered = ClaudePlanFetcher.Outcome.answered(facts)

        #expect(!answered.logDescription.contains("someone@example.com"))
        #expect(!answered.logDescription.contains("example.com"))
        #expect(answered.logDescription.contains("max_20x"))
        #expect(answered.logDescription.contains("present"))
        // The default description is exactly what must not be logged — guards against
        // someone "simplifying" this back to String(describing:).
        #expect(String(describing: answered).contains("someone@example.com"))

        let noIdentity = ClaudePlanFetcher.Outcome.answered(
            ClaudeProfileFacts(billingType: nil, identity: nil)
        )
        #expect(noIdentity.logDescription == "answered(plan: none, identity: none)")
        #expect(ClaudePlanFetcher.Outcome.rejected.logDescription == "rejected")
        #expect(ClaudePlanFetcher.Outcome.unavailable.logDescription == "unavailable")
    }
}

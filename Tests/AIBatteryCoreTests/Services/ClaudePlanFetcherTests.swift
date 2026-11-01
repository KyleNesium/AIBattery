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
        #expect(ClaudePlanFetcher.interpret(statusCode: 200, data: maxBody) == .answered("max_20x"))
    }

    /// A 2xx that names no known plan still settles the lookup — asking again won't help.
    @Test func success_withUnknownPlan_answersNil() {
        #expect(ClaudePlanFetcher.interpret(statusCode: 200, data: Data("{}".utf8)) == .answered(nil))
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

    @Test func profileURL_isTheOAuthProfileEndpoint() {
        #expect(ClaudePlanFetcher.profileURL.absoluteString == "https://api.anthropic.com/api/oauth/profile")
    }
}

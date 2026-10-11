import Foundation
import Testing
@testable import AIBatteryCore

@Suite("OAuthManager codex routing")
@MainActor
struct OAuthManagerCodexRoutingTests {
    @Test func storageKeyIsProviderScoped() {
        #expect(OAuthManager.tokenStorageKey(accountId: "acc-1", provider: .codex) == "codex_acc-1")
        #expect(OAuthManager.tokenStorageKey(accountId: "org-1", provider: .claude) == "org-1")
    }

    @Test func codexAccountRecordFromIdToken() {
        // The account-creation helper (extracted for testability) builds a
        // non-pending record with provider .codex from a raw account id.
        let record = OAuthManager.makeCodexAccountRecord(accountId: "acc-uuid-7", addedAt: Date(timeIntervalSince1970: 1_000))
        #expect(record.id == "acc-uuid-7")
        #expect(record.provider == .codex)
        #expect(!record.isPendingIdentity)
        #expect(record.discoveredIdentity == nil)
    }

    /// Sign-in and auth.json import both pass the id_token so the email claim seeds
    /// the discovered identity. A token without an email leaves it nil.
    @Test func codexAccountRecordSeedsDiscoveredIdentityFromIdToken() {
        func jwt(_ payload: [String: Any]) -> String {
            let header = Data(#"{"alg":"none"}"#.utf8).base64URLEncoded()
            let body = ((try? JSONSerialization.data(withJSONObject: payload)) ?? Data()).base64URLEncoded()
            return "\(header).\(body).sig"
        }
        let withEmail = OAuthManager.makeCodexAccountRecord(accountId: "acc-1", idToken: jwt(["email": "kyle@example.com"]))
        #expect(withEmail.discoveredIdentity == "kyle@example.com")
        let withoutEmail = OAuthManager.makeCodexAccountRecord(accountId: "acc-2", idToken: jwt(["sub": "x"]))
        #expect(withoutEmail.discoveredIdentity == nil)
    }
}

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
    }
}

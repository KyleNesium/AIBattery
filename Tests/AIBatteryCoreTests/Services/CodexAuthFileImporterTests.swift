import Foundation
import Testing
@testable import AIBatteryCore

@Suite("CodexAuthFileImporter")
struct CodexAuthFileImporterTests {
    @Test func parsesChatGPTModeAuthJSON() {
        // Field names verified against a real ~/.codex/auth.json (values faked).
        let json = Data("""
        {"auth_mode":"chatgpt","OPENAI_API_KEY":null,
         "tokens":{"id_token":"id.a.b","access_token":"at.a.b","refresh_token":"rt-1","account_id":"acc-77"},
         "last_refresh":"2026-09-01T09:26:07.000Z"}
        """.utf8)
        let imported = CodexAuthFileImporter.parse(json)
        #expect(imported == CodexImportedAuth(accountId: "acc-77", idToken: "id.a.b", accessToken: "at.a.b", refreshToken: "rt-1"))
    }

    @Test func rejectsAPIKeyModeAndMalformed() {
        let apiKeyMode = Data(#"{"auth_mode":"apikey","OPENAI_API_KEY":"sk-x","tokens":null}"#.utf8)
        #expect(CodexAuthFileImporter.parse(apiKeyMode) == nil)
        #expect(CodexAuthFileImporter.parse(Data("nonsense".utf8)) == nil)
        let missingRefresh = Data(#"{"tokens":{"id_token":"i","access_token":"a","account_id":"x"}}"#.utf8)
        #expect(CodexAuthFileImporter.parse(missingRefresh) == nil)
    }

    /// `account_id` becomes a Keychain account suffix, a UserDefaults key suffix and the
    /// `ChatGPT-Account-Id` header, out of a file any local process can write. Hold it to
    /// the shape OpenAI issues instead of trusting whatever is on disk.
    @Test func rejectsImplausibleAccountIds() {
        #expect(CodexAuthFileImporter.isPlausibleAccountId("acc-77"))
        #expect(CodexAuthFileImporter.isPlausibleAccountId("01a06764-9c28-78d1-9b78-00cf239db521"))
        #expect(!CodexAuthFileImporter.isPlausibleAccountId(""))
        #expect(!CodexAuthFileImporter.isPlausibleAccountId("acc 77"))
        #expect(!CodexAuthFileImporter.isPlausibleAccountId("acc\r\nX-Injected: 1"))
        #expect(!CodexAuthFileImporter.isPlausibleAccountId("../../etc/passwd"))
        #expect(!CodexAuthFileImporter.isPlausibleAccountId(String(repeating: "a", count: 129)))

        let injected = Data(#"{"tokens":{"id_token":"i","access_token":"a","refresh_token":"r","account_id":"a\r\nX: 1"}}"#.utf8)
        #expect(CodexAuthFileImporter.parse(injected) == nil)
    }

    // MARK: - Account id source

    /// The OAuth flow keys accounts by the id_token's `chatgpt_account_id` claim. When
    /// the file's own field disagrees (a workspace-scoped login), importing under the
    /// file field would land the same real account twice.
    @Test func accountId_prefersTheIdTokenClaimOverTheFileField() {
        let idToken = Self.idToken(accountId: "claim-acc")
        #expect(CodexAuthFileImporter.accountId(idToken: idToken, fileField: "file-acc") == "claim-acc")

        let json = Data("""
        {"auth_mode":"chatgpt",
         "tokens":{"id_token":"\(idToken)","access_token":"at","refresh_token":"rt","account_id":"file-acc"}}
        """.utf8)
        #expect(CodexAuthFileImporter.parse(json)?.accountId == "claim-acc")
    }

    @Test func accountId_fallsBackToTheFileFieldWhenTheClaimIsUnreadable() {
        #expect(CodexAuthFileImporter.accountId(idToken: "not.a.jwt", fileField: "acc-77") == "acc-77")
        #expect(CodexAuthFileImporter.accountId(idToken: "not.a.jwt", fileField: nil) == nil)
        // An implausible claim is not trusted either; the file field still has to pass.
        let bogus = Self.idToken(accountId: "bad id")
        #expect(CodexAuthFileImporter.accountId(idToken: bogus, fileField: "acc-77") == "acc-77")
        #expect(CodexAuthFileImporter.accountId(idToken: bogus, fileField: "also bad") == nil)
    }

    /// Unsigned id_token carrying only the OpenAI auth claim — the decoder reads the
    /// payload segment and never verifies the signature.
    private static func idToken(accountId: String) -> String {
        let payload = #"{"https://api.openai.com/auth":{"chatgpt_account_id":"\#(accountId)"}}"#
        let encoded = Data(payload.utf8).base64EncodedString()
        return "header.\(encoded).signature"
    }
}

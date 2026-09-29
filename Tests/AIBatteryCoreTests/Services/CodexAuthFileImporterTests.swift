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
}

import Foundation
import Testing
@testable import AIBatteryCore

@Suite("CodexOAuthConstants")
struct CodexOAuthConstantsTests {
    @Test func authorizeURLCarriesAllRequiredParams() throws {
        let url = CodexOAuthConstants.buildAuthorizeURL(codeChallenge: "CHAL", state: "STATE123")
        let comps = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(comps.scheme == "https")
        #expect(comps.host == "auth.openai.com")
        #expect(comps.path == "/oauth/authorize")
        let q = Dictionary(uniqueKeysWithValues: (comps.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(q["response_type"] == "code")
        #expect(q["client_id"] == "app_EMoamEEZ73f0CkXaXp7hrann")
        #expect(q["redirect_uri"] == "http://localhost:1455/auth/callback")
        #expect(q["scope"] == "openid profile email offline_access api.connectors.read api.connectors.invoke")
        #expect(q["code_challenge"] == "CHAL")
        #expect(q["code_challenge_method"] == "S256")
        #expect(q["id_token_add_organizations"] == "true")
        #expect(q["codex_cli_simplified_flow"] == "true")
        #expect(q["state"] == "STATE123")
        #expect(q["originator"] == "codex_cli_rs")
    }
}

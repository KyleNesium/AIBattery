import Foundation

/// OpenAI OAuth constants — lifted verbatim from the open-source Codex CLI
/// (codex-rs/login). The client-id is the CLI's public app id, not a secret.
enum CodexOAuthConstants {
    static let clientId = "app_EMoamEEZ73f0CkXaXp7hrann"
    static let issuer = "https://auth.openai.com"
    static let callbackPort: UInt16 = 1_455
    static var redirectURI: String { "http://localhost:\(callbackPort)/auth/callback" }
    static let scope = "openid profile email offline_access api.connectors.read api.connectors.invoke"
    static let originator = "codex_cli_rs"
    static var tokenURL: URL { URL(string: "\(issuer)/oauth/token")! }

    static func buildAuthorizeURL(codeChallenge: String, state: String) -> URL {
        var comps = URLComponents(string: "\(issuer)/oauth/authorize")!
        comps.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "id_token_add_organizations", value: "true"),
            URLQueryItem(name: "codex_cli_simplified_flow", value: "true"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "originator", value: originator),
        ]
        return comps.url!
    }
}

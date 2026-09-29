import Foundation

struct CodexImportedAuth: Equatable {
    let accountId: String
    let idToken: String
    let accessToken: String
    let refreshToken: String
}

/// What `~/.codex/auth.json` holds: a ChatGPT OAuth login or a plain API key.
enum CodexImportedCredential: Equatable {
    case chatGPT(CodexImportedAuth)
    case apiKey(String)
}

/// One-click "Import current Codex CLI login": reads ~/.codex/auth.json and
/// seeds a Codex account from it. One-time seeding — AIBattery refreshes
/// independently afterwards. Never writes back to the file.
enum CodexAuthFileImporter {
    /// Either auth mode. ChatGPT mode requires the full token set; API-key mode
    /// requires a non-empty `OPENAI_API_KEY`.
    nonisolated static func parseCredential(_ data: Data) -> CodexImportedCredential? {
        if let auth = parse(data) {
            return .chatGPT(auth)
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let key = root["OPENAI_API_KEY"] as? String, !key.isEmpty else { return nil }
        return .apiKey(key)
    }

    nonisolated static func parse(_ data: Data) -> CodexImportedAuth? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = root["tokens"] as? [String: Any],
              let accountId = tokens["account_id"] as? String,
              let idToken = tokens["id_token"] as? String,
              let accessToken = tokens["access_token"] as? String,
              let refreshToken = tokens["refresh_token"] as? String else {
            return nil
        }
        return CodexImportedAuth(accountId: accountId, idToken: idToken, accessToken: accessToken, refreshToken: refreshToken)
    }

    /// Whether the CLI has a login (ChatGPT or API key) to import.
    static var cliLoginAvailable: Bool {
        guard let data = try? Data(contentsOf: CodexPaths.authJSON) else { return false }
        return parseCredential(data) != nil
    }

    @MainActor
    static func importCurrentLogin(into manager: OAuthManager) -> Result<String, OAuthManager.AuthError> {
        guard let data = try? Data(contentsOf: CodexPaths.authJSON), let credential = parseCredential(data) else {
            return .failure(.unknownError("No Codex CLI login found at ~/.codex/auth.json"))
        }
        // `registerCodexAccount` / `registerCodexAPIKey` enforce the per-provider cap
        // themselves and report via Result — no duplicate guard here.
        switch credential {
        case .chatGPT(let imported):
            return manager.registerCodexAccount(
                accountId: imported.accountId,
                tokenSet: CodexTokenSet(idToken: imported.idToken, accessToken: imported.accessToken, refreshToken: imported.refreshToken)
            ).map { imported.accountId }
        case .apiKey(let key):
            return manager.registerCodexAPIKey(key).map { OAuthManager.apiKeyAccountId(for: key) }
        }
    }
}

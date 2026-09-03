import Foundation

struct CodexImportedAuth: Equatable {
    let accountId: String
    let idToken: String
    let accessToken: String
    let refreshToken: String
}

/// One-click "Import current Codex CLI login": reads ~/.codex/auth.json and
/// seeds a Codex account from it. One-time seeding — AIBattery refreshes
/// independently afterwards. Never writes back to the file.
enum CodexAuthFileImporter {
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

    /// Whether the CLI has a ChatGPT-mode login to import.
    static var cliLoginAvailable: Bool {
        guard let data = try? Data(contentsOf: CodexPaths.authJSON) else { return false }
        return parse(data) != nil
    }

    @MainActor
    static func importCurrentLogin(into manager: OAuthManager) -> Result<String, OAuthManager.AuthError> {
        guard let data = try? Data(contentsOf: CodexPaths.authJSON), let imported = parse(data) else {
            return .failure(.unknownError("No Codex CLI login found at ~/.codex/auth.json"))
        }
        guard manager.accountStore.canAddAccount(provider: .codex)
            || manager.accountStore.accounts.contains(where: { $0.id == imported.accountId }) else {
            return .failure(.unknownError("Codex account limit reached (max \(AccountStore.maxAccountsPerProvider))"))
        }
        manager.registerCodexAccount(
            accountId: imported.accountId,
            tokenSet: CodexTokenSet(idToken: imported.idToken, accessToken: imported.accessToken, refreshToken: imported.refreshToken)
        )
        return .success(imported.accountId)
    }
}

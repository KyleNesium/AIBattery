import Foundation

extension OAuthManager {
    nonisolated static func tokenStorageKey(accountId: String, provider: AIProvider) -> String {
        provider == .codex ? "codex_\(accountId)" : accountId
    }

    nonisolated static func makeCodexAccountRecord(accountId: String, addedAt: Date = Date()) -> AccountRecord {
        AccountRecord(id: accountId, addedAt: addedAt, provider: .codex)
    }

    /// Start the Codex browser sign-in. Returns the URL to open, or nil when
    /// the callback port couldn't be bound (typically: Codex CLI login in
    /// progress, or a previous flow still winding down).
    func startCodexAuthFlow() -> URL? {
        cancelCodexAuthFlow()
        do {
            let (session, url) = try CodexAuthSession.begin()
            codexAuthSession = session
            return url
        } catch {
            AppLogger.oauth.error("Codex auth: cannot bind localhost:1455 — \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Await redirect → validate state → exchange code → derive identity → persist.
    func completeCodexAuthFlow() async -> Result<Void, AuthError> {
        guard let session = codexAuthSession else { return .failure(.unknownError("No auth flow in progress")) }
        defer { codexAuthSession = nil }

        let callback = await session.awaitCallback()
        switch callback {
        case .failure(let error):
            return .failure(.unknownError("Sign-in did not complete (\(String(describing: error)))"))
        case .success(let payload):
            guard payload.state == session.state else {
                return .failure(.unknownError("State mismatch — possible CSRF, sign-in aborted"))
            }
            let exchanged = await CodexTokenClient.exchangeCode(payload.code, verifier: session.verifier)
            switch exchanged {
            case .failure(let error):
                return .failure(error)
            case .success(let tokenSet):
                guard let accountId = JWTDecoder.chatGPTAccountId(idToken: tokenSet.idToken) else {
                    return .failure(.unknownError("Could not read account identity from sign-in response"))
                }
                registerCodexAccount(accountId: accountId, tokenSet: tokenSet)
                return .success(())
            }
        }
    }

    func cancelCodexAuthFlow() {
        codexAuthSession?.cancel()
        codexAuthSession = nil
    }

    /// Shared by the OAuth flow and the auth.json importer (Task 10).
    func registerCodexAccount(accountId: String, tokenSet: CodexTokenSet) {
        storeTokens(
            accountId: accountId,
            provider: .codex,
            accessToken: tokenSet.accessToken,
            refreshToken: tokenSet.refreshToken,
            expiresAt: JWTDecoder.expiry(tokenSet.accessToken) ?? Date().addingTimeInterval(3_600)
        )
        if !accountStore.accounts.contains(where: { $0.id == accountId }) {
            accountStore.add(Self.makeCodexAccountRecord(accountId: accountId))
        }
        accountStore.setActive(id: accountId)
        updateAuthState()
    }
}

import CryptoKit
import Foundation

extension OAuthManager {
    /// Stable, key-free account id for an API-key account: `openai-api-` + the first 24
    /// hex chars of SHA-256(key). The key itself never appears in UserDefaults.
    nonisolated static func apiKeyAccountId(for apiKey: String) -> String {
        let digest = SHA256.hash(data: Data(apiKey.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "openai-api-" + hex.prefix(24)
    }

    /// Register a Codex account backed by an OpenAI API key (pay-per-token). The key
    /// is stored in the Keychain as the account's "refresh token" (and served as the
    /// access token with no expiry); `billingType` is "api".
    @discardableResult
    func registerCodexAPIKey(_ rawKey: String) -> Result<Void, AuthError> {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.hasPrefix("sk-"), key.count >= 20 else {
            return .failure(.unknownError("That doesn't look like an OpenAI API key (expected sk-…)."))
        }
        let accountId = Self.apiKeyAccountId(for: key)
        guard accountStore.canAddAccount(provider: .codex)
            || accountStore.accounts.contains(where: { $0.id == accountId }) else {
            return .failure(.maxAccountsReached)
        }
        storeTokens(accountId: accountId, provider: .codex, accessToken: key, refreshToken: key, expiresAt: .distantFuture)
        if !accountStore.accounts.contains(where: { $0.id == accountId }) {
            accountStore.add(AccountRecord(id: accountId, billingType: "api", addedAt: Date(), provider: .codex, codexAccessMode: .apiKey))
        }
        accountStore.setActive(id: accountId)
        updateAuthState()
        return .success(())
    }

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
                return registerCodexAccount(accountId: accountId, tokenSet: tokenSet)
            }
        }
    }

    func cancelCodexAuthFlow() {
        codexAuthSession?.cancel()
        codexAuthSession = nil
    }

    /// Shared by the OAuth flow and the auth.json importer (Task 10).
    ///
    /// Returns `.failure(.maxAccountsReached)` when the per-provider cap blocks
    /// registration. Previously returned `Void` and silently no-op'd on the cap guard,
    /// which let `completeCodexAuthFlow` report `.success` with a stuck overlay even
    /// though nothing was registered — callers must propagate this Result.
    @discardableResult
    func registerCodexAccount(accountId: String, tokenSet: CodexTokenSet) -> Result<Void, AuthError> {
        // Guard the cap here too — a 4th Codex sign-in must not persist tokens for an
        // account AccountStore.add will silently reject, which would otherwise orphan
        // a Keychain entry. The UI also hides "Add Codex Account…" at the cap, but this
        // is the real protection (a sign-in can still race a stale UI state).
        guard accountStore.canAddAccount(provider: .codex)
            || accountStore.accounts.contains(where: { $0.id == accountId }) else {
            AppLogger.oauth.warning("Codex sign-in rejected — per-provider account cap reached")
            return .failure(.maxAccountsReached)
        }
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
        return .success(())
    }
}

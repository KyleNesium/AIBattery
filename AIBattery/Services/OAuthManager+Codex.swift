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
    /// Cheap local shape check shared by the entry form and `registerCodexAPIKey`.
    nonisolated static func looksLikeOpenAIAPIKey(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("sk-") && trimmed.count >= 20
    }

    @discardableResult
    func registerCodexAPIKey(_ rawKey: String) -> Result<Void, AuthError> {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.looksLikeOpenAIAPIKey(key) else {
            return .failure(.unknownError(AuthError.malformedAPIKeyMessage))
        }
        let accountId = Self.apiKeyAccountId(for: key)
        guard accountStore.canAddAccount(provider: .codex)
            || accountStore.accounts.contains(where: { $0.id == accountId }) else {
            return .failure(.maxAccountsReached)
        }
        storeTokens(accountId: accountId, provider: .codex, accessToken: key, refreshToken: key, expiresAt: .distantFuture)
        activateCodexAccount(AccountRecord(id: accountId, billingType: "api", addedAt: Date(), provider: .codex, codexAccessMode: .apiKey))
        return .success(())
    }

    /// Shared tail of both Codex registrations: add the record if new, make it
    /// active, republish auth state.
    private func activateCodexAccount(_ record: AccountRecord) {
        if accountStore.account(id: record.id) == nil {
            accountStore.add(record)
        }
        accountStore.setActive(id: record.id)
        updateAuthState()
    }

    nonisolated static func tokenStorageKey(accountId: String, provider: AIProvider) -> String {
        provider == .codex ? "codex_\(accountId)" : accountId
    }

    /// `idToken` seeds `discoveredIdentity` from the email claim when present.
    nonisolated static func makeCodexAccountRecord(accountId: String, idToken: String? = nil, addedAt: Date = Date()) -> AccountRecord {
        AccountRecord(
            id: accountId,
            addedAt: addedAt,
            provider: .codex,
            discoveredIdentity: idToken.flatMap { JWTDecoder.email(idToken: $0) }
        )
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
            return .failure(AuthError.codexCallbackFailure(error))
        case .success(let payload):
            guard payload.state == session.state else {
                return .failure(.unknownError("State mismatch — possible CSRF, sign-in aborted"))
            }
            let exchanged = await CodexTokenClient.exchangeCode(payload.code, verifier: session.verifier)
            switch exchanged {
            case .failure(let error):
                return .failure(error)
            case .success(let tokenSet):
                guard let idToken = tokenSet.idToken,
                      let accountId = JWTDecoder.chatGPTAccountId(idToken: idToken) else {
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
        let record = Self.makeCodexAccountRecord(accountId: accountId, idToken: tokenSet.idToken)
        activateCodexAccount(record)
        // Re-signing into a known account (or importing it) backfills an identity the
        // record didn't have yet — records created before the field existed.
        accountStore.backfillDiscoveredIdentity(accountId: accountId, identity: record.discoveredIdentity)
        return .success(())
    }
}

import Foundation
import CryptoKit
import os

/// Manages Anthropic OAuth 2.0 authentication with PKCE for multiple accounts.
///
/// Flow:
/// 1. User clicks "Authenticate" → opens browser to claude.ai/oauth/authorize
/// 2. User logs in and authorizes → browser shows an authorization code
/// 3. User pastes code into AIBattery → exchanged for access + refresh tokens
/// 4. Access token used as Bearer token for API calls
/// 5. Auto-refreshes when expired using refresh token
///
/// Multi-account:
/// - Supports up to 3 accounts (separate Claude orgs)
/// - Each account's tokens stored under prefixed Keychain entries
/// - `AccountStore` tracks known accounts; `activeAccountId` drives which one polls
/// - New accounts get a temporary `"pending-<UUID>"` ID until the first API call
///   returns the real `anthropic-organization-id`, which triggers `resolveAccountIdentity()`
///
/// Security:
/// - PKCE (SHA-256) prevents authorization code interception
/// - Tokens stored in macOS Keychain under AIBattery's own service name
/// - No API keys — uses OAuth Bearer tokens only
/// - Refresh tokens enable long-lived sessions without re-authentication
@MainActor
public final class OAuthManager: ObservableObject {
    public static let shared = OAuthManager()

    // Anthropic OAuth constants (same as Claude Code / OpenCode)
    private let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    private let authBaseURL = "https://claude.ai/oauth/authorize"
    nonisolated private static let tokenURL = "https://console.anthropic.com/v1/oauth/token"
    private let redirectURI = "https://console.anthropic.com/oauth/code/callback"
    private let scopes = "org:create_api_key user:profile user:inference"

    // In-flight PKCE verifier and state (lives only during auth flow)
    private var pendingVerifier: String?
    private var pendingState: String?

    /// Whether the current auth flow is for adding a second account.
    private var isAddingAccount = false

    /// Per-account in-memory token cache, keyed by account ID.
    private var tokens: [String: AccountTokens] = [:]

    /// Refresh the access token 5 minutes before it expires to avoid clock-skew
    /// and network-delay induced 401s that trigger unnecessary re-authentication.
    private static let expiryBuffer: TimeInterval = 300 // 5 minutes

    /// Serializes concurrent refresh attempts per account.
    private var refreshTasks: [String: Task<String?, Never>] = [:]
    /// Generation counter per account — used to detect stale refresh tasks.
    private var refreshGeneration: [String: UInt64] = [:]

    /// Account registry — persisted to UserDefaults.
    @Published public var accountStore = AccountStore()

    @Published public var isAuthenticated: Bool = false

    public init() {
        migrateFromLegacy()
        migrateStaleKeychainItems()
        migrateKeychainAccessibility()
        loadAllTokens()
        updateAuthState()
    }

    // MARK: - Public API

    /// Returns a valid access token for the active account, refreshing if needed.
    func getAccessToken() async -> String? {
        guard let accountId = accountStore.activeAccountId else { return nil }
        return await getAccessToken(for: accountId)
    }

    /// Returns a valid access token for a specific account, refreshing if needed.
    ///
    /// Concurrency contract — **must preserve, see `CLAUDE.md`**:
    /// - **Serialization**: concurrent callers for the same `accountId` share a single
    ///   refresh `Task` via `refreshTasks[accountId]`. The check + write pair runs on
    ///   MainActor with no suspension between them, so the second caller always sees
    ///   the in-flight task and piggybacks on it via `await existing.value`. This
    ///   prevents N concurrent token endpoint hits during a refresh.
    /// - **Generation counter**: `refreshGeneration[accountId]` ensures only the
    ///   latest refresh's `Task` is cleared from the map; an older refresh completing
    ///   after a newer one was kicked off won't trample the newer task slot.
    /// - **Transient vs. auth errors**: handled in `refreshAccessToken` — transient
    ///   (network, 5xx) keeps `isAuthenticated` true; only true auth errors trigger
    ///   `signOut`. This invariant is enforced by `AuthError.isTransient`.
    ///
    /// The actual HTTP work runs in `postToken`, which is `nonisolated static` so
    /// the network suspension happens entirely off-MainActor.
    func getAccessToken(for accountId: String) async -> String? {
        guard let acctTokens = tokens[accountId] else {
            AppLogger.oauth.error("getAccessToken: no tokens for account \(accountId, privacy: .public)")
            return nil
        }

        // If we have a valid token with enough remaining lifetime, return it
        if let token = acctTokens.accessToken, let expires = acctTokens.expiresAt,
           expires.addingTimeInterval(-Self.expiryBuffer) > Date() {
            return token
        }

        // If a refresh is already in-flight for this account, piggyback on it
        if let existing = refreshTasks[accountId] {
            return await existing.value
        }

        // Try to refresh
        guard let refresh = acctTokens.refreshToken else {
            AppLogger.oauth.error("getAccessToken: no refresh token for account \(accountId, privacy: .public)")
            return nil
        }

        let gen = (refreshGeneration[accountId] ?? 0) &+ 1
        refreshGeneration[accountId] = gen
        let task = Task<String?, Never> {
            await refreshAccessToken(refresh, accountId: accountId)
        }
        refreshTasks[accountId] = task
        let result = await task.value
        // Only clear if no newer refresh replaced this one while we were awaiting
        if refreshGeneration[accountId] == gen {
            refreshTasks[accountId] = nil
        }
        return result
    }

    /// Start the OAuth flow: generates PKCE, returns the authorization URL to open in browser.
    func startAuthFlow(addingAccount: Bool = false) -> URL? {
        isAddingAccount = addingAccount
        let (verifier, challenge) = generatePKCE()
        pendingVerifier = verifier

        // Separate state parameter — never reuse the PKCE verifier as state,
        // because the state is reflected in redirect URLs and server logs.
        let state = generateRandomState()
        pendingState = state

        guard var components = URLComponents(string: authBaseURL) else { return nil }
        components.queryItems = [
            URLQueryItem(name: "code", value: "true"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
        ]

        return components.url
    }

    /// Auth error types for specific failure feedback.
    enum AuthError: Error {
        case noVerifier
        case invalidCode
        case expired
        case networkError
        case serverError(Int)
        case maxAccountsReached
        case unknownError(String)

        var userMessage: String {
            switch self {
            case .noVerifier: "Auth flow not started. Please click Authenticate first."
            case .invalidCode: "Invalid authorization code. Please try again."
            case .expired: "Authorization code expired. Please re-authenticate."
            case .networkError: "Network error. Check your connection and try again."
            case .serverError(let code): "Anthropic's server returned \(code). This is a temporary issue on their end — please try again in a moment."
            case .maxAccountsReached: "Maximum of \(AccountStore.maxAccounts) accounts reached. Remove one before adding another."
            case .unknownError(let msg): msg
            }
        }

        /// Whether this error is transient and the caller should preserve auth state.
        var isTransient: Bool {
            switch self {
            case .networkError, .serverError: true
            default: false
            }
        }
    }

    /// Complete the OAuth flow: exchange the authorization code for tokens.
    /// Creates a new account record with a pending identity.
    func exchangeCode(_ rawCode: String) async -> Result<Void, AuthError> {
        guard let verifier = pendingVerifier else { return .failure(.noVerifier) }
        let expectedState = pendingState

        // Check account limit when adding
        if isAddingAccount && !accountStore.canAddAccount {
            return .failure(.maxAccountsReached)
        }

        // Anthropic returns code#state format
        let parts = rawCode.split(separator: "#")
        let code = parts.first.map(String.init) ?? rawCode

        // Validate state parameter (CSRF protection)
        if let expectedState {
            guard parts.count >= 2 else {
                return .failure(.unknownError("Missing state parameter. Please try again."))
            }
            let returnedState = String(parts[1])
            guard !returnedState.isEmpty, returnedState == expectedState else {
                return .failure(.unknownError("State mismatch — possible CSRF attack. Please try again."))
            }
        }

        let body: [String: String] = [
            "code": code.trimmingCharacters(in: .whitespacesAndNewlines),
            "state": expectedState ?? "",
            "grant_type": "authorization_code",
            "client_id": clientID,
            "redirect_uri": redirectURI,
            "code_verifier": verifier,
        ]

        let tokenResult = await Self.postToken(body: body)
        switch tokenResult {
        case .success(let result):
            // Only clear pending state on success — allows retry on network failure
            pendingVerifier = nil
            pendingState = nil

            // Create a new account with a temporary ID
            let tempId = "pending-\(UUID().uuidString)"
            let record = AccountRecord(
                id: tempId,
                displayName: nil,
                billingType: nil,
                addedAt: Date()
            )
            accountStore.add(record)
            accountStore.setActive(id: tempId)

            tokens[tempId] = AccountTokens(
                accessToken: result.accessToken,
                refreshToken: result.refreshToken,
                expiresAt: result.expiresAt
            )
            saveTokens(for: tempId)
            isAddingAccount = false
            updateAuthState()
            return .success(())
        case .failure(let error):
            return .failure(error)
        }
    }

    /// Resolve a pending account identity after the first API call returns the real org ID.
    /// Idempotent — skips if the account is already resolved.
    func resolveAccountIdentity(tempId: String, realOrgId: String, billingType: String? = nil) {
        guard let account = accountStore.accounts.first(where: { $0.id == tempId }),
              account.isPendingIdentity else { return }

        var updated = account
        updated.id = realOrgId
        if let billing = billingType { updated.billingType = billing }

        // Move Keychain entries from temp ID to real org ID
        let tokenData = tokens[tempId]
        deleteTokens(for: tempId)
        tokens.removeValue(forKey: tempId)

        if let data = tokenData {
            tokens[realOrgId] = data
            saveTokens(for: realOrgId)
        }

        // Update account store (handles duplicate detection/merge internally)
        accountStore.update(oldId: tempId, with: updated)

        // Clean up refresh tasks
        if let task = refreshTasks.removeValue(forKey: tempId) {
            refreshTasks[realOrgId] = task
        }

        updateAuthState()
        AppLogger.oauth.info("Resolved account identity: \(tempId, privacy: .public) → \(realOrgId, privacy: .public)")
    }

    /// Update an existing account's metadata (display name, billing type).
    func updateAccountMetadata(accountId: String, displayName: String? = nil, billingType: String? = nil) {
        guard var record = accountStore.accounts.first(where: { $0.id == accountId }) else { return }
        if let name = displayName { record.displayName = name }
        if let billing = billingType { record.billingType = billing }
        accountStore.update(oldId: accountId, with: record)
    }

    /// Sign out a specific account (or the active one if nil).
    func signOut(accountId: String? = nil) {
        let targetId = accountId ?? accountStore.activeAccountId
        guard let id = targetId else { return }

        tokens.removeValue(forKey: id)
        refreshTasks[id]?.cancel()
        refreshTasks.removeValue(forKey: id)
        deleteTokens(for: id)
        accountStore.remove(id: id)

        // Clear PKCE state if in the middle of a flow
        pendingVerifier = nil
        pendingState = nil
        isAddingAccount = false

        updateAuthState()
    }

    // MARK: - Auth State

    /// Whether a specific account currently has a refresh token (i.e. is authenticated).
    /// Used by multi-account fan-out to skip accounts whose refresh tokens are missing
    /// (e.g. removed account that hasn't been pruned, or pending sign-out).
    public func isAuthenticated(accountId: String) -> Bool {
        tokens[accountId]?.refreshToken != nil
    }

    private func updateAuthState() {
        guard let activeId = accountStore.activeAccountId,
              let acctTokens = tokens[activeId],
              acctTokens.refreshToken != nil else {
            isAuthenticated = false
            return
        }
        isAuthenticated = true
    }

    // MARK: - Token Refresh

    private func refreshAccessToken(_ refresh: String, accountId: String) async -> String? {
        let body: [String: String] = [
            "grant_type": "refresh_token",
            "refresh_token": refresh,
            "client_id": clientID,
        ]

        let tokenResult = await Self.postToken(body: body)
        switch tokenResult {
        case .success(let result):
            tokens[accountId] = AccountTokens(
                accessToken: result.accessToken,
                refreshToken: result.refreshToken,
                expiresAt: result.expiresAt
            )
            saveTokens(for: accountId)
            updateAuthState()
            return result.accessToken
        case .failure(let error):
            // Only mark as unauthenticated for auth errors (revoked/invalid token).
            // Transient errors (network, 5xx) keep isAuthenticated so we retry next cycle.
            if error.isTransient {
                AppLogger.oauth.warning("OAuth refresh failed for account \(accountId, privacy: .public) (\(String(describing: error))), will retry next cycle")
            } else {
                signOut(accountId: accountId)
            }
            return nil
        }
    }

    // MARK: - Token Endpoint

    struct TokenResult {
        let accessToken: String
        let refreshToken: String
        let expiresAt: Date
    }

    /// Maximum number of retries for transient server errors (5xx).
    /// `nonisolated` because `postToken` is `nonisolated static` and references this.
    nonisolated private static let maxRetries = 2

    /// HTTP POST to Anthropic's OAuth token endpoint. Pure: takes a body dict,
    /// returns a `Sendable Result<TokenResult, AuthError>`.
    ///
    /// `nonisolated static` so this can run off-MainActor; the network suspension
    /// already releases MainActor (see `getAccessToken(for:)` doc), but explicit
    /// nonisolation lets the compiler enforce that this function never depends
    /// on instance state — preventing the kind of accidental MainActor capture
    /// that would defeat the suspension contract.
    ///
    /// Used by both `exchangeCode` (authorization_code grant) and
    /// `refreshAccessToken` (refresh_token grant). The MainActor caller owns
    /// all side effects (token storage, account creation, auth state updates).
    nonisolated static func postToken(body: [String: String]) async -> Result<TokenResult, AuthError> {
        guard let url = URL(string: tokenURL) else { return .failure(.unknownError("Invalid token URL")) }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            return .failure(.unknownError("Failed to serialize request body"))
        }
        request.httpBody = bodyData

        var lastError: AuthError = .networkError
        for attempt in 0...Self.maxRetries {
            if attempt > 0 {
                // Exponential backoff with jitter via RetryPolicy.oauth (1s, 2s, 4s ±20%).
                let delay = RetryPolicy.oauth.delay(forAttempt: attempt)
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }

            do {
                let (data, response) = try await SecureNetworking.data(for: request)
                guard let http = response as? HTTPURLResponse else { return .failure(.networkError) }

                if http.statusCode == 401 || http.statusCode == 403 {
                    // Parse error body for specific message
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let errorMsg = json["error_description"] as? String {
                        if errorMsg.lowercased().contains("expired") {
                            return .failure(.expired)
                        }
                    }
                    return .failure(.invalidCode)
                }

                // Retry on rate limit (429) and transient server errors (5xx)
                if http.statusCode == 429 || (http.statusCode >= 500 && http.statusCode < 600) {
                    AppLogger.oauth.warning("Token endpoint returned \(http.statusCode), attempt \(attempt + 1)/\(Self.maxRetries + 1)")
                    // Honor Retry-After header on 429 if present (capped at 30s via RateLimitFetcher)
                    if http.statusCode == 429,
                       let delay = RateLimitFetcher.parseRetryAfter(
                           http.value(forHTTPHeaderField: "Retry-After")
                       ) {
                        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    }
                    lastError = .serverError(http.statusCode)
                    continue
                }

                guard http.statusCode == 200 else {
                    let bodyStr = String(data: data, encoding: .utf8) ?? "(no body)"
                    AppLogger.oauth.error("Token endpoint returned \(http.statusCode): \(bodyStr)")
                    // Parse OAuth error response for specific feedback.
                    // Anthropic wraps errors as {"error":{"type":"...","message":"..."}}
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        // Standard OAuth: top-level "error" string + "error_description"
                        let oauthError = json["error"] as? String
                        let desc = json["error_description"] as? String
                        // Anthropic nested: {"error":{"type":"...","message":"..."}}
                        let nested = json["error"] as? [String: Any]
                        let nestedType = nested?["type"] as? String
                        let nestedMsg = nested?["message"] as? String

                        let errorType = oauthError ?? nestedType ?? ""
                        let errorMsg = desc ?? nestedMsg

                        if errorType == "invalid_grant" {
                            return .failure(.expired)
                        }
                        if let errorMsg {
                            return .failure(.unknownError("Auth failed: \(errorMsg)"))
                        }
                    }
                    return .failure(.unknownError("Server returned status \(http.statusCode). Check Console.app for details."))
                }

                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let access = json["access_token"] as? String,
                      let refresh = json["refresh_token"] as? String,
                      let expiresIn = json["expires_in"] as? Int else {
                    AppLogger.oauth.warning("Token endpoint returned 200 with invalid JSON, attempt \(attempt + 1)/\(Self.maxRetries + 1)")
                    lastError = .unknownError("Invalid token response format")
                    continue
                }

                return .success(TokenResult(
                    accessToken: access,
                    refreshToken: refresh,
                    expiresAt: Date().addingTimeInterval(TimeInterval(expiresIn))
                ))
            } catch {
                AppLogger.oauth.error("Token exchange network error: \(error)")
                lastError = .networkError
                continue
            }
        }

        return .failure(lastError)
    }

    // MARK: - PKCE (SHA-256) & State

    /// Generate a random state parameter (separate from the PKCE verifier).
    private func generateRandomState() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncoded()
    }

    private func generatePKCE() -> (verifier: String, challenge: String) {
        // 32 random bytes → base64url → verifier
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let verifier = Data(bytes).base64URLEncoded()

        // SHA-256(verifier) → base64url → challenge
        let digest = SHA256.hash(data: Data(verifier.utf8))
        let challenge = Data(digest).base64URLEncoded()

        return (verifier, challenge)
    }

    // MARK: - Per-Account Keychain Storage

    /// Local alias so the `OAuthManager` body keeps reading `AccountTokens` — the
    /// type lives in `OAuthTokenStorage` so the auth-flow code and the persistence
    /// code can evolve separately. See `OAuthTokenStorage.swift` for layout details.
    typealias AccountTokens = OAuthTokenStorage.AccountTokens

    private func saveTokens(for accountId: String) {
        guard let data = tokens[accountId] else { return }
        OAuthTokenStorage.save(data, for: accountId)
    }

    private func loadTokens(for accountId: String) -> AccountTokens {
        OAuthTokenStorage.load(for: accountId)
    }

    private func deleteTokens(for accountId: String) {
        OAuthTokenStorage.delete(for: accountId)
    }

    private func loadAllTokens() {
        for account in accountStore.accounts {
            tokens[account.id] = loadTokens(for: account.id)
        }
    }

    // MARK: - Migration from Single-Account Format

    /// One-time migration: moves legacy Keychain entries (unprefixed) to the new prefixed format.
    private func migrateFromLegacy() {
        // Already migrated — accounts exist
        guard accountStore.accounts.isEmpty else { return }

        // Check for legacy (unprefixed) Keychain entries
        let legacyRefresh = KeychainHelper.get(account: "refreshToken")
        guard legacyRefresh != nil else { return }

        AppLogger.oauth.info("Migrating legacy single-account Keychain entries")

        let tempId = "pending-\(UUID().uuidString)"
        let record = AccountRecord(
            id: tempId,
            displayName: nil,
            billingType: UserDefaults.standard.string(forKey: UserDefaultsKeys.plan),
            addedAt: Date()
        )

        // Only persist the refresh token (access token will be re-derived on launch)
        if let value = KeychainHelper.get(account: "refreshToken") {
            KeychainHelper.set(account: "refreshToken_\(tempId)", value: value)
        }
        // expiresAt goes to UserDefaults (not a secret)
        if let expiresStr = KeychainHelper.get(account: "expiresAt"),
           let interval = Double(expiresStr) {
            UserDefaults.standard.set(interval,
                                      forKey: UserDefaultsKeys.tokenExpiresAtPrefix + tempId)
        }
        // Clean up all legacy unprefixed entries
        for key in ["accessToken", "refreshToken", "expiresAt"] {
            KeychainHelper.delete(account: key)
        }

        accountStore.add(record)
        accountStore.setActive(id: tempId)
    }

    // MARK: - Migration: Remove Stale Keychain Items

    /// Removes accessToken and expiresAt from Keychain (they're no longer stored
    /// there). Moves expiresAt to UserDefaults if not already present.
    private func migrateStaleKeychainItems() {
        for account in accountStore.accounts {
            let accountId = account.id

            // Move expiresAt from Keychain to UserDefaults if present
            let udKey = UserDefaultsKeys.tokenExpiresAtPrefix + accountId
            if UserDefaults.standard.double(forKey: udKey) == 0 {
                if let expiresStr = KeychainHelper.get(account: "expiresAt_\(accountId)"),
                   let interval = Double(expiresStr) {
                    UserDefaults.standard.set(interval, forKey: udKey)
                }
            }

            // Remove stale Keychain items (accessToken + expiresAt)
            KeychainHelper.delete(account: "accessToken_\(accountId)")
            KeychainHelper.delete(account: "expiresAt_\(accountId)")
        }
    }

    // MARK: - Migration: Keychain ThisDeviceOnly Accessibility

    /// One-time migration: re-creates Keychain items with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.
    /// The old flag (`kSecAttrAccessibleWhenUnlocked`) allows iCloud Keychain to sync refresh tokens
    /// to other Apple devices. Keychain doesn't support updating `kSecAttrAccessible` in-place, so
    /// we delete and re-add each item. Only runs once (tracked via UserDefaults flag).
    private func migrateKeychainAccessibility() {
        let migrationKey = "aibattery_keychainThisDeviceOnlyMigrated"
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }

        for account in accountStore.accounts {
            let keychainAccount = "refreshToken_\(account.id)"
            if let value = KeychainHelper.get(account: keychainAccount) {
                KeychainHelper.delete(account: keychainAccount)
                KeychainHelper.set(account: keychainAccount, value: value)
            }
        }

        UserDefaults.standard.set(true, forKey: migrationKey)
        AppLogger.oauth.info("Migrated Keychain items to ThisDeviceOnly accessibility")
    }
}

// MARK: - Base64URL encoding (RFC 7636)

private extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

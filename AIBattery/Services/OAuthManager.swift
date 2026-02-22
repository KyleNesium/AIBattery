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
/// - Supports up to 2 accounts (separate Claude orgs)
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
    private let tokenURL = "https://console.anthropic.com/v1/oauth/token"
    private let redirectURI = "https://console.anthropic.com/oauth/code/callback"
    private let scopes = "org:create_api_key user:profile user:inference"

    // Keychain storage (AIBattery's own entries, not Claude Code's)
    private let keychainService = "AIBattery"

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

    /// Account registry — persisted to UserDefaults.
    @Published public var accountStore = AccountStore()

    @Published public var isAuthenticated: Bool = false

    public init() {
        migrateFromLegacy()
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
    func getAccessToken(for accountId: String) async -> String? {
        guard let acctTokens = tokens[accountId] else { return nil }

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
        guard let refresh = acctTokens.refreshToken else { return nil }

        let task = Task<String?, Never> {
            let result = await refreshAccessToken(refresh, accountId: accountId)
            refreshTasks[accountId] = nil
            return result
        }
        refreshTasks[accountId] = task
        return await task.value
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
            case .noVerifier: return "Auth flow not started. Please click Authenticate first."
            case .invalidCode: return "Invalid authorization code. Please try again."
            case .expired: return "Authorization code expired. Please re-authenticate."
            case .networkError: return "Network error. Check your connection and try again."
            case .serverError(let code): return "Anthropic's server returned \(code). This is a temporary issue on their end — please try again in a moment."
            case .maxAccountsReached: return "Maximum of \(AccountStore.maxAccounts) accounts reached. Remove one before adding another."
            case .unknownError(let msg): return msg
            }
        }

        /// Whether this error is transient and the caller should preserve auth state.
        var isTransient: Bool {
            switch self {
            case .networkError, .serverError: return true
            default: return false
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
        if parts.count >= 2, let expectedState {
            let returnedState = String(parts[1])
            if returnedState != expectedState {
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

        let tokenResult = await postToken(body: body)
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

        let tokenResult = await postToken(body: body)
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

    private struct TokenResult {
        let accessToken: String
        let refreshToken: String
        let expiresAt: Date
    }

    /// Maximum number of retries for transient server errors (5xx).
    private static let maxRetries = 2

    private func postToken(body: [String: String]) async -> Result<TokenResult, AuthError> {
        guard let url = URL(string: tokenURL) else { return .failure(.unknownError("Invalid token URL")) }

        var lastError: AuthError = .networkError
        for attempt in 0...Self.maxRetries {
            if attempt > 0 {
                // Exponential backoff with jitter: 1s, 2s (±20%)
                let base = TimeInterval(1 << (attempt - 1))
                let delay = base * Double.random(in: 0.8...1.2)
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 15
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
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
                    lastError = .serverError(http.statusCode)
                    continue
                }

                guard http.statusCode == 200 else {
                    return .failure(.unknownError("Server returned status \(http.statusCode)"))
                }

                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let access = json["access_token"] as? String,
                      let refresh = json["refresh_token"] as? String,
                      let expiresIn = json["expires_in"] as? Int else {
                    return .failure(.unknownError("Invalid token response format"))
                }

                return .success(TokenResult(
                    accessToken: access,
                    refreshToken: refresh,
                    expiresAt: Date().addingTimeInterval(TimeInterval(expiresIn))
                ))
            } catch {
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

    private struct AccountTokens {
        var accessToken: String?
        var refreshToken: String?
        var expiresAt: Date?
    }

    private func saveTokens(for accountId: String) {
        guard let data = tokens[accountId] else { return }
        if let token = data.accessToken {
            keychainSet(account: "accessToken_\(accountId)", value: token)
        }
        if let refresh = data.refreshToken {
            keychainSet(account: "refreshToken_\(accountId)", value: refresh)
        }
        if let expires = data.expiresAt {
            keychainSet(account: "expiresAt_\(accountId)", value: String(expires.timeIntervalSince1970))
        }
    }

    private func loadTokens(for accountId: String) -> AccountTokens {
        let access = keychainGet(account: "accessToken_\(accountId)")
        let refresh = keychainGet(account: "refreshToken_\(accountId)")
        var expires: Date?
        if let expiresStr = keychainGet(account: "expiresAt_\(accountId)"),
           let interval = Double(expiresStr) {
            expires = Date(timeIntervalSince1970: interval)
        }
        return AccountTokens(accessToken: access, refreshToken: refresh, expiresAt: expires)
    }

    private func deleteTokens(for accountId: String) {
        keychainDelete(account: "accessToken_\(accountId)")
        keychainDelete(account: "refreshToken_\(accountId)")
        keychainDelete(account: "expiresAt_\(accountId)")
    }

    private func loadAllTokens() {
        for account in accountStore.accounts {
            tokens[account.id] = loadTokens(for: account.id)
        }
    }

    // MARK: - Migration from Single-Account Format

    /// One-time migration: moves legacy Keychain entries to the new prefixed format.
    private func migrateFromLegacy() {
        // Already migrated — accounts exist
        guard accountStore.accounts.isEmpty else { return }

        // Check for legacy (unprefixed) Keychain entries
        let legacyRefresh = keychainGet(account: "refreshToken")
        guard legacyRefresh != nil else { return }

        AppLogger.oauth.info("Migrating legacy single-account Keychain entries")

        let tempId = "pending-\(UUID().uuidString)"
        let record = AccountRecord(
            id: tempId,
            displayName: nil,
            billingType: UserDefaults.standard.string(forKey: UserDefaultsKeys.plan),
            addedAt: Date()
        )

        // Copy legacy entries to new prefixed format
        for key in ["accessToken", "refreshToken", "expiresAt"] {
            if let value = keychainGet(account: key) {
                keychainSet(account: "\(key)_\(tempId)", value: value)
                keychainDelete(account: key)
            }
        }

        accountStore.add(record)
        accountStore.setActive(id: tempId)
    }

    // MARK: - Keychain Helpers

    private func keychainSet(account: String, value: String) {
        let data = Data(value.utf8)

        // Try to update existing item first
        let searchQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
        ]
        let updateAttrs: [String: Any] = [
            kSecValueData as String: data,
        ]
        let updateStatus = SecItemUpdate(searchQuery as CFDictionary, updateAttrs as CFDictionary)

        if updateStatus == errSecItemNotFound {
            // Item doesn't exist yet — add it
            var addQuery = searchQuery
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            if addStatus != errSecSuccess {
                AppLogger.oauth.error("Keychain add failed for \(account, privacy: .public): \(addStatus)")
            }
        } else if updateStatus != errSecSuccess {
            AppLogger.oauth.error("Keychain update failed for \(account, privacy: .public): \(updateStatus)")
            // Fallback: delete and re-add
            SecItemDelete(searchQuery as CFDictionary)
            var addQuery = searchQuery
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            if addStatus != errSecSuccess {
                AppLogger.oauth.error("Keychain fallback add failed for \(account, privacy: .public): \(addStatus)")
            }
        }
    }

    private func keychainGet(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status != errSecSuccess && status != errSecItemNotFound {
            AppLogger.oauth.error("Keychain read failed for \(account, privacy: .public): \(status)")
        }
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func keychainDelete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
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

import Foundation
import CryptoKit
import os

/// Manages Anthropic OAuth 2.0 authentication with PKCE.
///
/// Flow:
/// 1. User clicks "Authenticate" → opens browser to claude.ai/oauth/authorize
/// 2. User logs in and authorizes → browser shows an authorization code
/// 3. User pastes code into AIBattery → exchanged for access + refresh tokens
/// 4. Access token used as Bearer token for API calls
/// 5. Auto-refreshes when expired using refresh token
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
    private let accessTokenAccount = "accessToken"
    private let refreshTokenAccount = "refreshToken"
    private let expiresAtAccount = "expiresAt"

    // In-flight PKCE verifier and state (lives only during auth flow)
    private var pendingVerifier: String?
    private var pendingState: String?

    // Cached tokens (in-memory)
    private var accessToken: String?
    private var refreshToken: String?
    private var expiresAt: Date?

    /// Refresh the access token 5 minutes before it expires to avoid clock-skew
    /// and network-delay induced 401s that trigger unnecessary re-authentication.
    private static let expiryBuffer: TimeInterval = 300 // 5 minutes

    /// Serializes concurrent refresh attempts so only one token refresh is in-flight
    /// at a time. Without this, multiple polling cycles that all see an expired token
    /// could fire parallel refresh requests, wasting network and risking race conditions.
    private var refreshTask: Task<String?, Never>?

    @Published public var isAuthenticated: Bool = false

    public init() {
        loadFromKeychain()
    }

    // MARK: - Public API

    /// Returns a valid access token, refreshing if needed. Returns nil if not authenticated.
    ///
    /// Refreshes 5 minutes before expiry to avoid clock-skew 401s.
    /// Serializes concurrent refresh attempts — if a refresh is already in-flight,
    /// subsequent callers await the same task instead of firing parallel requests.
    func getAccessToken() async -> String? {
        // If we have a valid token with enough remaining lifetime, return it
        if let token = accessToken, let expires = expiresAt,
           expires.addingTimeInterval(-Self.expiryBuffer) > Date() {
            return token
        }

        // If a refresh is already in-flight, piggyback on it
        if let existing = refreshTask {
            return await existing.value
        }

        // Try to refresh
        guard let refresh = refreshToken else { return nil }

        let task = Task<String?, Never> {
            let result = await refreshAccessToken(refresh)
            refreshTask = nil
            return result
        }
        refreshTask = task
        return await task.value
    }

    /// Start the OAuth flow: generates PKCE, returns the authorization URL to open in browser.
    func startAuthFlow() -> URL? {
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
        case unknownError(String)

        var userMessage: String {
            switch self {
            case .noVerifier: return "Auth flow not started. Please click Authenticate first."
            case .invalidCode: return "Invalid authorization code. Please try again."
            case .expired: return "Authorization code expired. Please re-authenticate."
            case .networkError: return "Network error. Check your connection and try again."
            case .serverError(let code): return "Anthropic's server returned \(code). This is a temporary issue on their end — please try again in a moment."
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
    /// The code may be in "code#state" format (as returned by Anthropic).
    func exchangeCode(_ rawCode: String) async -> Result<Void, AuthError> {
        guard let verifier = pendingVerifier else { return .failure(.noVerifier) }
        let expectedState = pendingState

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
            "state": expectedState ?? verifier,
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
            accessToken = result.accessToken
            refreshToken = result.refreshToken
            expiresAt = result.expiresAt
            saveToKeychain()
            isAuthenticated = true
            return .success(())
        case .failure(let error):
            return .failure(error)
        }
    }

    /// Sign out: clear all stored tokens.
    func signOut() {
        accessToken = nil
        refreshToken = nil
        expiresAt = nil
        pendingVerifier = nil
        pendingState = nil
        refreshTask?.cancel()
        refreshTask = nil
        deleteFromKeychain()
        isAuthenticated = false
    }

    // MARK: - Token Refresh

    private func refreshAccessToken(_ refresh: String) async -> String? {
        let body: [String: String] = [
            "grant_type": "refresh_token",
            "refresh_token": refresh,
            "client_id": clientID,
        ]

        let tokenResult = await postToken(body: body)
        switch tokenResult {
        case .success(let result):
            accessToken = result.accessToken
            refreshToken = result.refreshToken
            expiresAt = result.expiresAt
            saveToKeychain()
            isAuthenticated = true
            return result.accessToken
        case .failure(let error):
            // Only mark as unauthenticated for auth errors (revoked/invalid token).
            // Transient errors (network, 5xx) keep isAuthenticated so we retry next cycle.
            if error.isTransient {
                AppLogger.oauth.warning("OAuth refresh failed (\(String(describing: error))), will retry next cycle")
            } else {
                isAuthenticated = false
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
                // Exponential backoff: 1s, 2s
                let delay = TimeInterval(1 << (attempt - 1))
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

                // Retry on transient server errors (500, 502, 503)
                if http.statusCode >= 500 && http.statusCode < 600 {
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

    // MARK: - Keychain Storage (AIBattery's own entries)

    private func saveToKeychain() {
        if let token = accessToken {
            keychainSet(account: accessTokenAccount, value: token)
        }
        if let refresh = refreshToken {
            keychainSet(account: refreshTokenAccount, value: refresh)
        }
        if let expires = expiresAt {
            keychainSet(account: expiresAtAccount, value: String(expires.timeIntervalSince1970))
        }
    }

    private func loadFromKeychain() {
        accessToken = keychainGet(account: accessTokenAccount)
        refreshToken = keychainGet(account: refreshTokenAccount)
        if let expiresStr = keychainGet(account: expiresAtAccount),
           let interval = Double(expiresStr) {
            expiresAt = Date(timeIntervalSince1970: interval)
        }
        isAuthenticated = (refreshToken != nil)
    }

    private func deleteFromKeychain() {
        keychainDelete(account: accessTokenAccount)
        keychainDelete(account: refreshTokenAccount)
        keychainDelete(account: expiresAtAccount)
    }

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

import Foundation
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
    nonisolated static let tokenURL = "https://console.anthropic.com/v1/oauth/token"
    private let redirectURI = "https://console.anthropic.com/oauth/code/callback"
    private let scopes = "org:create_api_key user:profile user:inference"

    // In-flight PKCE verifier and state (lives only during auth flow)
    private var pendingVerifier: String?
    private var pendingState: String?

    /// Whether the current auth flow is for adding a second account.
    private var isAddingAccount = false

    /// In-flight Codex OAuth session (PKCE verifier, state, callback server).
    /// Discarded when the flow completes or is cancelled. Internal (not
    /// private) so `OAuthManager+Codex.swift` can drive it.
    var codexAuthSession: CodexAuthSession?

    /// Per-account in-memory token cache, keyed by account ID.
    private var tokens: [String: AccountTokens] = [:]

    /// Refresh the access token 5 minutes before it expires to avoid clock-skew
    /// and network-delay induced 401s that trigger unnecessary re-authentication.
    private static let expiryBuffer: TimeInterval = 300 // 5 minutes

    /// Transport used by the refresh and code-exchange paths. Injectable so the refresh
    /// contract (cancellation, failure backoff) is testable without the live token
    /// endpoint; production keeps the `SecureNetworking` default.
    var tokenTransport: @Sendable (URLRequest) async throws -> (Data, URLResponse) = { try await SecureNetworking.data(for: $0) }
    /// Retry policy for the Claude token endpoint; tests swap in a zero-delay policy.
    var tokenRetryPolicy: RetryPolicy = .oauth

    /// Serializes concurrent refresh attempts per account.
    private var refreshTasks: [String: Task<String?, Never>] = [:]
    /// Generation counter per account — used to detect stale refresh tasks.
    private var refreshGeneration: [String: UInt64] = [:]
    /// Per-account backoff after a TRANSIENT refresh failure, on the shared
    /// `RetryPolicy.statusCheck` curve. Cleared on any successful refresh. Auth failures
    /// never land here: those sign the account out instead of being retried.
    private var refreshBackoff: [String: EndpointBackoff] = [:]

    func isRefreshBackingOff(accountId: String, now: Date = Date()) -> Bool {
        EndpointBackoff.shouldSkip(refreshBackoff[accountId] ?? EndpointBackoff(), now: now)
    }

    func recordRefreshFailure(accountId: String, now: Date = Date()) {
        refreshBackoff[accountId] = EndpointBackoff.recordingFailure(
            refreshBackoff[accountId] ?? EndpointBackoff(), now: now
        )
    }

    func clearRefreshBackoff(accountId: String) {
        refreshBackoff[accountId] = nil
    }

    /// Accounts whose saved sign-in couldn't be read: the Keychain read failed instead of
    /// finding nothing (a prompt cancelled by sleep → `errSecInDarkWake`, a locked
    /// keychain). They stay signed in on their last reading instead of dropping to the
    /// sign-in screen; `getAccessToken` retries the read on the refresh backoff curve.
    private var unreadableAccounts: Set<String> = []
    /// One in-flight retry read per account, so concurrent callers raise one prompt.
    private var keychainRetries: [String: Task<Void, Never>] = [:]
    /// Reader for the retry; tests swap in a stub. The launch read always uses the Keychain.
    var keychainRead: @Sendable (String) -> KeychainHelper.ReadResult = { KeychainHelper.read(account: $0) }

    /// Whether a failed read is worth retrying. Deny / Cancel on the prompt is a refusal,
    /// and retrying would only raise the prompt again, so that account signs out as before.
    nonisolated static func isRetryableReadFailure(_ status: OSStatus) -> Bool {
        status != errSecUserCanceled && status != errSecAuthFailed
    }

    /// Account registry — persisted to UserDefaults.
    @Published public var accountStore = AccountStore()

    @Published public var isAuthenticated: Bool = false

    /// Why the last sign-out happened when the app did it (rejected refresh token).
    /// nil after a user-initiated sign-out and cleared once any account authenticates.
    @Published public var lastSignOutReason: String?

    public init() {
        migrateFromLegacy()
        migrateStaleKeychainItems()
        migrateKeychainAccessibility()
        loadAllTokens()
        updateAuthState()
    }

    /// Launch-time maintenance: drop the token-ledger AND rate-limit cache entries for
    /// accounts the user no longer has — orphaned `pending-<uuid>` ids left by
    /// pre-migration identity resolutions, removed accounts, and any stray test ids that
    /// leaked in. Pruning the rate-limit cache here is what clears the stale
    /// `pending-*` blobs that could otherwise surface a false "Limit reached".
    ///
    /// Deliberately NOT called from `init` (and exposed as a separate public method)
    /// so unit-test `OAuthManager()` construction never mutates the real
    /// `token-ledger.json` or persisted rate limits. Call once from the app's launch
    /// path. Both prunes are internally guarded against an empty live set so a logged-out
    /// launch can't wipe held history.
    public func pruneOrphanedLedgerAccounts() {
        let liveIds = Set(accountStore.accounts.map(\.id))
        let hasLiveCodexAccount = accountStore.accounts.contains { $0.provider == .codex }
        TokenLedger.shared.pruneAccounts(keeping: liveIds, hasLiveCodexAccount: hasLiveCodexAccount)
        RateLimitFetcher.shared.pruneAccounts(keeping: liveIds)
        CodexRateLimitFetcher.shared.pruneAccounts(keeping: liveIds)
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

        // A refresh that just failed transiently is not retried on the very next poll.
        // Each attempt costs three requests with ~1 s and ~2 s sleeps between them (and
        // up to three 30 s timeouts), nothing recorded the failure, and on wake several
        // expired accounts did this at once inside the fan-out. Auth failures are not
        // backed off — those sign out immediately rather than being retried at all.
        if isRefreshBackingOff(accountId: accountId) {
            return nil
        }

        // Try to refresh
        guard let refresh = acctTokens.refreshToken else {
            if unreadableAccounts.contains(accountId) {
                retryKeychainRead(accountId: accountId)
                return nil
            }
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
        let (verifier, challenge) = OAuthPKCE.generatePKCE()
        pendingVerifier = verifier

        // Separate state parameter — never reuse the PKCE verifier as state,
        // because the state is reflected in redirect URLs and server logs.
        let state = OAuthPKCE.generateState()
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
        /// Transient failure from the provider's token endpoint (5xx, 429, …). The
        /// provider picks the wording — a Codex sign-in must never blame Anthropic.
        case serverError(Int, provider: AIProvider = .claude)
        case maxAccountsReached
        /// OpenAI's token endpoint refused the Codex sign-in (400/401/403). Non-transient.
        case codexSignInRejected(Int)
        /// The user cancelled the Codex browser sign-in. Not an error to display.
        case cancelled
        case unknownError(String)

        var userMessage: String {
            switch self {
            case .noVerifier: "Auth flow not started. Please click Authenticate first."
            case .invalidCode: "Invalid authorization code. Please try again."
            case .expired: "Authorization code expired. Please re-authenticate."
            case .networkError: "Network error. Check your connection and try again."
            case .serverError(let code, .claude): "Anthropic's server returned \(code). This is a temporary issue on their end — please try again in a moment."
            case .serverError(let code, .codex): "OpenAI's sign-in server returned \(code). This is a temporary issue on their end — please try again in a moment."
            case .maxAccountsReached: "Maximum of \(AccountStore.maxAccountsPerProvider) accounts per provider reached. Remove one before adding another."
            case .codexSignInRejected(let code): "OpenAI rejected the sign-in (HTTP \(code)). Please try again."
            case .cancelled: ""
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

        nonisolated static let malformedAPIKeyMessage = "That doesn't look like an OpenAI API key (expected sk-…)."

        /// True when the user backed out on purpose — callers show no error copy.
        var isCancellation: Bool {
            if case .cancelled = self {
                return true
            }
            return false
        }

        /// Copy for a Codex browser sign-in that ended without a usable redirect.
        nonisolated static func codexCallbackFailure(_ error: CodexCallbackError) -> AuthError {
            switch error {
            case .providerError("cancelled"):
                .cancelled
            case .providerError("timeout"):
                .unknownError("Sign-in timed out after 3 minutes. Please try again.")
            case .providerError(let reason):
                .unknownError("OpenAI declined the sign-in (\(Self.sanitizedProviderReason(reason))). Please try again.")
            case .missingCode, .missingState, .notCallbackPath:
                .unknownError("The browser redirect was malformed. Please try again.")
            }
        }

        /// The `error` query parameter arrives on an open loopback port, so any local
        /// process can put arbitrary text in front of the user attributed to OpenAI.
        /// Keep recognisable OAuth codes, replace anything else with a generic word.
        nonisolated static func sanitizedProviderReason(_ reason: String) -> String {
            let known: Set = [
                "access_denied", "invalid_request", "invalid_scope", "invalid_client",
                "unauthorized_client", "unsupported_response_type", "server_error",
                "temporarily_unavailable", "interaction_required", "login_required",
                "consent_required", "account_selection_required",
            ]
            return known.contains(reason) ? reason : "unrecognised error"
        }
    }

    /// Complete the OAuth flow: exchange the authorization code for tokens.
    /// Creates a new account record with a pending identity.
    func exchangeCode(_ rawCode: String) async -> Result<Void, AuthError> {
        guard let verifier = pendingVerifier else { return .failure(.noVerifier) }
        let expectedState = pendingState

        // Check account limit when adding. Must be the CLAUDE-specific cap: the
        // 3 Claude + <3 Codex accounts it would let this (Claude-only) flow proceed past
        // this guard only to have `accountStore.add` silently reject the 4th Claude
        // account further down — after tokens have already been written to Keychain.
        if isAddingAccount && !accountStore.canAddAccount(provider: .claude) {
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
            // `add` silently no-ops past the per-provider cap (e.g. the network round-trip
            // above gave a concurrent add time to fill it). Bail out BEFORE persisting
            // tokens for an account that was never actually added — otherwise
            // `refreshToken_pending-<uuid>` orphans in Keychain and this function would
            // still report `.success` with a stuck overlay.
            guard accountStore.accounts.contains(where: { $0.id == tempId }) else {
                isAddingAccount = false
                return .failure(.maxAccountsReached)
            }
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
        if let billing = billingType {
            updated.billingType = billing
        }

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

        // Move the token-ledger high-water marks from the pending id to the real org id
        // so the account's accumulated history follows it instead of orphaning.
        TokenLedger.shared.migrate(from: tempId, to: realOrgId)

        // Same for the rate-limit cache: the pending id's first-fetch blob must follow
        // the account, otherwise it orphans under the dead pending key and gets reloaded
        // every launch — where a stale "throttled"/100% reading can surface a false
        // "Limit reached" on the resolved account.
        RateLimitFetcher.shared.migrate(from: tempId, to: realOrgId)

        // Clean up refresh tasks
        if let task = refreshTasks.removeValue(forKey: tempId) {
            refreshTasks[realOrgId] = task
        }

        updateAuthState()
        AppLogger.oauth.info("Resolved account identity: \(tempId, privacy: .public) → \(realOrgId, privacy: .public)")
    }

    /// Update an existing account's metadata (display name, billing type, discovered identity).
    func updateAccountMetadata(accountId: String, displayName: String? = nil, billingType: String? = nil, discoveredIdentity: String? = nil) {
        guard var record = accountStore.accounts.first(where: { $0.id == accountId }) else { return }
        if let name = displayName {
            record.displayName = name
        }
        if let billing = billingType {
            record.billingType = billing
        }
        if let identity = discoveredIdentity {
            record.discoveredIdentity = identity
        }
        accountStore.update(oldId: accountId, with: record)
    }

    /// Sign out a specific account (or the active one if nil).
    /// - Parameter reason: user-facing copy when the app (not the user) signed the
    ///   account out, e.g. a rejected refresh token. Shown once on the sign-in screen.
    func signOut(accountId: String? = nil, reason: String? = nil) {
        let targetId = accountId ?? accountStore.activeAccountId
        guard let id = targetId else { return }

        let removedProvider = provider(for: id)
        // Remember which provider to offer on the signed-out root.
        UserDefaults.standard.set(removedProvider.rawValue, forKey: UserDefaultsKeys.signedOutProvider)
        lastSignOutReason = reason

        tokens.removeValue(forKey: id)
        refreshTasks[id]?.cancel()
        refreshTasks.removeValue(forKey: id)
        unreadableAccounts.remove(id)
        keychainRetries.removeValue(forKey: id)?.cancel()
        // Account ids are deterministic across a re-login (JWT account id / key hash),
        // so a fresh sign-in must not inherit the old one's backoff window.
        clearRefreshBackoff(accountId: id)
        deleteTokens(for: id)
        if removedProvider == .codex {
            cancelCodexAuthFlow()
            // Drop the signed-out account's cached/persisted Codex reading (which for an
            // API-key account includes per-minute limits) — nothing else prunes it until
            // the next launch sweep.
            CodexRateLimitFetcher.shared.clearCache(accountId: id)
        } else {
            // Same reasoning on the Claude side: `pruneAccounts` only runs at launch, so a
            // sign-out + re-add in one session would otherwise inherit the old reading under
            // the same (deterministic) org id.
            RateLimitFetcher.shared.clearCache(accountId: id)
        }
        // Drop the account's fired-alert latch too, or a re-added account stays silent at a
        // threshold it already crossed until a sub-threshold reading resets it.
        NotificationManager.shared.clearRateLimitAlerts(accountId: id)
        accountStore.remove(id: id)

        // Clear PKCE state if in the middle of a flow
        pendingVerifier = nil
        pendingState = nil
        isAddingAccount = false

        updateAuthState()
    }

    // MARK: - Auth State

    /// Whether a specific account currently has a refresh token (i.e. is authenticated),
    /// or has a saved one the Keychain couldn't hand over yet (`unreadableAccounts`).
    /// Used by multi-account fan-out to skip accounts whose refresh tokens are missing
    /// (e.g. removed account that hasn't been pruned, or pending sign-out).
    public func isAuthenticated(accountId: String) -> Bool {
        tokens[accountId]?.refreshToken != nil || unreadableAccounts.contains(accountId)
    }

    func updateAuthState() {
        guard let activeId = accountStore.activeAccountId, isAuthenticated(accountId: activeId) else {
            isAuthenticated = false
            return
        }
        isAuthenticated = true
        lastSignOutReason = nil
    }

    // MARK: - Token Refresh

    /// Copy shown on the sign-in screen after a refresh token is rejected.
    nonisolated static func sessionExpiredReason(for provider: AIProvider) -> String {
        switch provider {
        case .claude: "Your Claude session expired or was revoked — sign in again to continue."
        case .codex: "Your Codex (ChatGPT) session expired or was revoked — sign in again to continue."
        }
    }

    private func refreshAccessToken(_ refresh: String, accountId: String) async -> String? {
        if provider(for: accountId) == .codex {
            return await refreshCodexAccessToken(refresh, accountId: accountId)
        }

        let body: [String: String] = [
            "grant_type": "refresh_token",
            "refresh_token": refresh,
            "client_id": clientID,
        ]

        let tokenResult = await Self.postToken(body: body, transport: tokenTransport, retryPolicy: tokenRetryPolicy)
        switch tokenResult {
        case .success(let result):
            // `signOut` cancels this task and drops `tokens[accountId]`, but the network
            // round-trip can't be retracted. Writing the fresh set back here would
            // resurrect the account in memory and re-create its Keychain item.
            guard !Task.isCancelled, tokens[accountId] != nil else {
                AppLogger.oauth.info("OAuth refresh for \(accountId, privacy: .public) finished after sign-out — discarding")
                return nil
            }
            tokens[accountId] = AccountTokens(
                accessToken: result.accessToken,
                refreshToken: result.refreshToken,
                expiresAt: result.expiresAt
            )
            saveTokens(for: accountId)
            updateAuthState()
            clearRefreshBackoff(accountId: accountId)
            return result.accessToken
        case .failure(let error):
            // Only mark as unauthenticated for auth errors (revoked/invalid token).
            // Transient errors (network, 5xx) keep isAuthenticated so we retry next cycle.
            if error.isTransient {
                recordRefreshFailure(accountId: accountId)
                AppLogger.oauth.warning("OAuth refresh failed for account \(accountId, privacy: .public) (\(String(describing: error))), backing off before the next attempt")
            } else {
                signOut(accountId: accountId, reason: Self.sessionExpiredReason(for: .claude))
            }
            return nil
        }
    }

    /// Codex counterpart of `refreshAccessToken` above — same disposition on
    /// failure (transient keeps `isAuthenticated`, auth errors sign out), but
    /// exchanges via `CodexTokenClient` and derives expiry from the JWT `exp`
    /// claim rather than an `expires_in` field.
    private func refreshCodexAccessToken(_ refresh: String, accountId: String) async -> String? {
        // API-key accounts store the key as their "refresh token" — it IS the credential.
        if accountStore.account(id: accountId)?.isAPIKeyAccount == true {
            tokens[accountId] = AccountTokens(accessToken: refresh, refreshToken: refresh, expiresAt: .distantFuture)
            return refresh
        }
        let result = await CodexTokenClient.refresh(refreshToken: refresh, transport: tokenTransport)
        switch result {
        case .success(let set):
            // Same post-sign-out guard as the Anthropic arm: never resurrect a removed account.
            guard !Task.isCancelled, tokens[accountId] != nil else {
                AppLogger.oauth.info("Codex OAuth refresh for \(accountId, privacy: .public) finished after sign-out — discarding")
                return nil
            }
            let expires = JWTDecoder.expiry(set.accessToken) ?? Date().addingTimeInterval(3_600)
            tokens[accountId] = AccountTokens(
                accessToken: set.accessToken,
                refreshToken: set.refreshToken ?? refresh, // rotate only when a new one arrives
                expiresAt: expires
            )
            saveTokens(for: accountId)
            // The refresh grant may echo a fresh id_token: the one chance a Codex account
            // registered before `discoveredIdentity` existed gets its email without a
            // re-sign-in. No-op once the identity is known.
            if let idToken = set.idToken {
                accountStore.backfillDiscoveredIdentity(accountId: accountId, identity: JWTDecoder.email(idToken: idToken))
            }
            updateAuthState()
            clearRefreshBackoff(accountId: accountId)
            return set.accessToken
        case .failure(let error):
            // Identical disposition to the Anthropic arm above: transient errors
            // (network, 5xx) keep isAuthenticated and back off before the next attempt;
            // only genuine auth errors sign the account out.
            if error.isTransient {
                recordRefreshFailure(accountId: accountId)
                AppLogger.oauth.warning("Codex OAuth refresh failed for account \(accountId, privacy: .public) (\(String(describing: error))), backing off before the next attempt")
            } else {
                signOut(accountId: accountId, reason: Self.sessionExpiredReason(for: .codex))
            }
            return nil
        }
    }

    // MARK: - Per-Account Keychain Storage

    /// Local alias so the `OAuthManager` body keeps reading `AccountTokens` — the
    /// type lives in `OAuthTokenStorage` so the auth-flow code and the persistence
    /// code can evolve separately. See `OAuthTokenStorage.swift` for layout details.
    typealias AccountTokens = OAuthTokenStorage.AccountTokens

    /// The account's provider, looked up from `accountStore`. Accounts not yet
    /// in the store (mid-add — the Anthropic flow stores tokens under a
    /// temporary `pending-*` id before the record exists) default to `.claude`,
    /// which is correct because only the Anthropic flow does that.
    private func provider(for accountId: String) -> AIProvider {
        accountStore.provider(of: accountId)
    }

    private func saveTokens(for accountId: String) {
        guard let data = tokens[accountId] else { return }
        OAuthTokenStorage.save(data, for: Self.tokenStorageKey(accountId: accountId, provider: provider(for: accountId)))
    }

    private func loadTokens(for accountId: String) -> OAuthTokenStorage.Loaded {
        OAuthTokenStorage.load(for: Self.tokenStorageKey(accountId: accountId, provider: provider(for: accountId)))
    }

    private func deleteTokens(for accountId: String) {
        OAuthTokenStorage.delete(for: Self.tokenStorageKey(accountId: accountId, provider: provider(for: accountId)))
    }

    /// Write a token set into the in-memory cache + persistent storage for any
    /// provider. `OAuthTokenStorage.save` already persists the expiry to
    /// UserDefaults, so this does not write it a second time. Used by the
    /// Codex flow (`OAuthManager+Codex.swift`), which can't reach the private
    /// `tokens` dict directly since it lives in a different file.
    func storeTokens(accountId: String, provider: AIProvider, accessToken: String?, refreshToken: String?, expiresAt: Date?) {
        let data = AccountTokens(accessToken: accessToken, refreshToken: refreshToken, expiresAt: expiresAt)
        tokens[accountId] = data
        OAuthTokenStorage.save(data, for: Self.tokenStorageKey(accountId: accountId, provider: provider))
    }

    /// Memory-only token seed for tests — nothing is written to the Keychain or
    /// UserDefaults, so a test can prove the code under test didn't write either.
    func seedTokensForTesting(accountId: String, accessToken: String?, refreshToken: String?, expiresAt: Date?) {
        tokens[accountId] = AccountTokens(accessToken: accessToken, refreshToken: refreshToken, expiresAt: expiresAt)
    }

    /// Synchronous on purpose (state is complete before the first refresh), so an
    /// unapproved Keychain prompt holds launch until it is answered or cancelled.
    private func loadAllTokens() {
        for account in accountStore.accounts {
            let loaded = loadTokens(for: account.id)
            tokens[account.id] = loaded.tokens
            if let status = loaded.readFailure, Self.isRetryableReadFailure(status) {
                unreadableAccounts.insert(account.id)
            }
        }
    }

    // MARK: - Keychain read retry

    /// Re-reads an unreadable account's saved sign-in. Fire-and-forget and off the main
    /// actor: a read that raises the Keychain prompt blocks its thread until the prompt is
    /// answered, and on main that froze the whole app. The caller gets nil this cycle (the
    /// last reading stays up); the refresh after the read succeeds uses the token.
    private func retryKeychainRead(accountId: String) {
        guard keychainRetries[accountId] == nil else { return }
        let key = Self.tokenStorageKey(accountId: accountId, provider: provider(for: accountId))
        let read = keychainRead
        keychainRetries[accountId] = Task { [weak self] in
            let loaded = await Task.detached { OAuthTokenStorage.load(for: key, readKeychain: read) }.value
            self?.finishKeychainRetry(accountId: accountId, loaded: loaded)
        }
    }

    private func finishKeychainRetry(accountId: String, loaded: OAuthTokenStorage.Loaded) {
        keychainRetries[accountId] = nil
        // Signed out, or signed in afresh, while the read was out: nothing to restore.
        guard unreadableAccounts.contains(accountId), let current = tokens[accountId], current.refreshToken == nil else {
            unreadableAccounts.remove(accountId)
            return
        }
        if let status = loaded.readFailure, Self.isRetryableReadFailure(status) {
            recordRefreshFailure(accountId: accountId)
            AppLogger.oauth.info("Keychain retry for \(accountId, privacy: .public) still failing (\(status)), backing off")
            return
        }
        // Found the token, found nothing (gone), or refused: either way no longer "unreadable".
        unreadableAccounts.remove(accountId)
        tokens[accountId] = loaded.tokens
        clearRefreshBackoff(accountId: accountId)
        let restored = loaded.tokens.refreshToken != nil
        AppLogger.oauth.info("Keychain retry for \(accountId, privacy: .public): \(restored ? "sign-in restored" : "no usable sign-in", privacy: .public)")
        updateAuthState()
    }

    /// Test seams: mark an account as having an unreadable saved sign-in, and expose the
    /// in-flight retry so a test can await it.
    func seedUnreadableKeychainForTesting(accountId: String) {
        tokens[accountId] = AccountTokens(accessToken: nil, refreshToken: nil, expiresAt: nil)
        unreadableAccounts.insert(accountId)
    }

    func pendingKeychainRetry(accountId: String) -> Task<Void, Never>? {
        keychainRetries[accountId]
    }
}

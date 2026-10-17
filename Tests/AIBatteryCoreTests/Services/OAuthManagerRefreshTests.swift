import Foundation
import Testing
@testable import AIBatteryCore

/// Behavioural coverage for `OAuthManager`'s refresh path through the injectable
/// `tokenTransport` / `tokenRetryPolicy` seams — no network, no real token endpoint.
/// Tokens are seeded in memory only (`seedTokensForTesting`), so the happy path never
/// touches the Keychain; the assertions read the Keychain to prove the code under test
/// didn't either.
@Suite("OAuthManager — refresh path")
@MainActor
struct OAuthManagerRefreshTests {
    private static let validTokenBody = #"{"access_token":"at-new","refresh_token":"rt-new","expires_in":3600}"#
    private static let noDelay = RetryPolicy(baseDelay: 0, maxDelay: 0)

    /// Lets a stubbed transport park until the test says go, and lets the test wait
    /// until the transport has actually been entered.
    private actor Gate {
        private var opened = false
        private var entered = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func enter() async {
            entered = true
            if opened {
                return
            }
            await withCheckedContinuation { waiters.append($0) }
        }

        func open() {
            opened = true
            let pending = waiters
            waiters = []
            pending.forEach { $0.resume() }
        }

        func hasBeenEntered() -> Bool {
            entered
        }
    }

    nonisolated private static func response(_ request: URLRequest, status: Int, body: String) throws -> (Data, URLResponse) {
        let url = try #require(request.url)
        let http = try #require(HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil))
        return (Data(body.utf8), http)
    }

    /// A4: a refresh that completes after `signOut` must not write the fresh tokens back
    /// into memory or the Keychain — the user removed the account, and the Keychain item
    /// would otherwise reappear (under the wrong prefix for a Codex account).
    @Test func signOutDuringInFlightRefresh_doesNotResurrectTokens() async {
        let manager = OAuthManager()
        let accountId = "a4-refresh-\(UUID().uuidString)"
        let keychainAccount = "refreshToken_\(accountId)"
        defer { KeychainHelper.delete(account: keychainAccount) }

        manager.seedTokensForTesting(accountId: accountId, accessToken: nil, refreshToken: "rt-old", expiresAt: nil)
        #expect(manager.isAuthenticated(accountId: accountId))

        let gate = Gate()
        manager.tokenRetryPolicy = Self.noDelay
        manager.tokenTransport = { request in
            await gate.enter()
            return try Self.response(request, status: 200, body: Self.validTokenBody)
        }

        let refresh = Task { await manager.getAccessToken(for: accountId) }
        while await !gate.hasBeenEntered() {
            await Task.yield()
        }

        manager.signOut(accountId: accountId)
        await gate.open()

        let token = await refresh.value
        #expect(token == nil, "a refresh finishing after sign-out must not hand out a token")
        #expect(!manager.isAuthenticated(accountId: accountId))
        #expect(KeychainHelper.get(account: keychainAccount) == nil, "sign-out must win: no Keychain write")
    }

    /// Control for the test above: the same transport with no sign-out stores the token.
    @Test func refresh_withoutSignOut_installsNewTokens() async {
        let manager = OAuthManager()
        let accountId = "a4-control-\(UUID().uuidString)"
        let keychainAccount = "refreshToken_\(accountId)"
        defer {
            manager.signOut(accountId: accountId)
            KeychainHelper.delete(account: keychainAccount)
        }

        manager.seedTokensForTesting(accountId: accountId, accessToken: nil, refreshToken: "rt-old", expiresAt: nil)
        manager.tokenRetryPolicy = Self.noDelay
        manager.tokenTransport = { request in try Self.response(request, status: 200, body: Self.validTokenBody) }

        let token = await manager.getAccessToken(for: accountId)
        #expect(token == "at-new")
        #expect(manager.isAuthenticated(accountId: accountId))
    }

    // MARK: - Transient-failure backoff

    /// A transient refresh failure used to be retried on the very next poll, and each
    /// attempt costs three requests with sleeps between them. The account now backs off,
    /// stays authenticated, and the endpoint is not touched again until the window ends.
    @Test func transientFailure_backsOffAndSkipsTheNextAttempt() async {
        let manager = OAuthManager()
        let accountId = "a4-backoff-\(UUID().uuidString)"
        let keychainAccount = "refreshToken_\(accountId)"
        defer {
            manager.signOut(accountId: accountId)
            KeychainHelper.delete(account: keychainAccount)
        }

        manager.seedTokensForTesting(accountId: accountId, accessToken: nil, refreshToken: "rt-old", expiresAt: nil)
        manager.tokenRetryPolicy = Self.noDelay
        let attempts = Counter()
        manager.tokenTransport = { request in
            await attempts.increment()
            return try Self.response(request, status: 500, body: "")
        }

        #expect(await manager.getAccessToken(for: accountId) == nil)
        let afterFirst = await attempts.value
        #expect(afterFirst > 0, "the first call must actually reach the endpoint")
        // A 5xx is transient: the account keeps its session rather than being signed out.
        #expect(manager.isAuthenticated(accountId: accountId))
        #expect(manager.isRefreshBackingOff(accountId: accountId))

        // Second call inside the window: no further requests.
        #expect(await manager.getAccessToken(for: accountId) == nil)
        #expect(await attempts.value == afterFirst)

        // Past the widest first window (60 s ± 20% jitter) it is live again.
        #expect(!manager.isRefreshBackingOff(accountId: accountId, now: Date().addingTimeInterval(73)))
    }

    /// Backoff is per account — one account's bad network must not stall another's.
    @Test func backoffIsPerAccount() async {
        let manager = OAuthManager()
        let failing = "a4-fail-\(UUID().uuidString)"
        let healthy = "a4-ok-\(UUID().uuidString)"
        defer {
            manager.signOut(accountId: failing)
            manager.signOut(accountId: healthy)
            KeychainHelper.delete(account: "refreshToken_\(failing)")
            KeychainHelper.delete(account: "refreshToken_\(healthy)")
        }

        // Distinct refresh tokens so the stub can fail one and serve the other.
        manager.seedTokensForTesting(accountId: failing, accessToken: nil, refreshToken: "rt-doomed", expiresAt: nil)
        manager.seedTokensForTesting(accountId: healthy, accessToken: nil, refreshToken: "rt-fine", expiresAt: nil)
        manager.tokenRetryPolicy = Self.noDelay
        manager.tokenTransport = { request in
            let body = request.httpBody.flatMap { String(bytes: $0, encoding: .utf8) } ?? ""
            let doomed = body.contains("rt-doomed")
            return try Self.response(request, status: doomed ? 500 : 200, body: doomed ? "" : Self.validTokenBody)
        }

        #expect(await manager.getAccessToken(for: failing) == nil)
        #expect(await manager.getAccessToken(for: healthy) == "at-new")

        #expect(manager.isRefreshBackingOff(accountId: failing))
        #expect(!manager.isRefreshBackingOff(accountId: healthy), "a healthy account must not inherit the window")
    }

    /// A success clears the window, so recovery is immediate rather than waiting it out.
    @Test func successClearsTheBackoff() async {
        let manager = OAuthManager()
        let accountId = "a4-recover-\(UUID().uuidString)"
        defer {
            manager.signOut(accountId: accountId)
            KeychainHelper.delete(account: "refreshToken_\(accountId)")
        }

        manager.seedTokensForTesting(accountId: accountId, accessToken: nil, refreshToken: "rt-old", expiresAt: nil)
        manager.tokenRetryPolicy = Self.noDelay
        manager.recordRefreshFailure(accountId: accountId)
        #expect(manager.isRefreshBackingOff(accountId: accountId))

        manager.clearRefreshBackoff(accountId: accountId)
        manager.tokenTransport = { request in try Self.response(request, status: 200, body: Self.validTokenBody) }
        #expect(await manager.getAccessToken(for: accountId) == "at-new")
        #expect(!manager.isRefreshBackingOff(accountId: accountId))
    }

    /// Counts transport invocations across concurrent contexts.
    private actor Counter {
        private(set) var value = 0
        func increment() {
            value += 1
        }
    }
}

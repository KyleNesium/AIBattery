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
}

import Combine
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
    nonisolated private static let validTokenBody = #"{"access_token":"at-new","refresh_token":"rt-new","expires_in":3600}"#
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
        defer { OAuthTokenStorage.delete(for: accountId) }

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
        #expect(OAuthTokenStorage.load(for: accountId).tokens.refreshToken == nil, "sign-out must win: no Keychain write")
    }

    /// A new Claude account starts under a temporary id and moves to its organisation id
    /// after the first API call. Three things change: the token is copied to the new id,
    /// the account record is pointed at it, and the old copy is removed. They must happen in
    /// that order, so that a crash after any one of them leaves a record whose id has a token.
    @Test func resolvingAnAccountId_neverLeavesTheRecordWithoutAToken() {
        let manager = OAuthManager()
        let tempId = "pending-\(UUID().uuidString)"
        let realId = "org-\(UUID().uuidString)"
        manager.accountStore.add(AccountRecord(id: tempId, addedAt: Date()))
        defer {
            manager.signOut(accountId: realId)
            manager.signOut(accountId: tempId)
        }
        manager.storeTokens(accountId: tempId, provider: .claude, accessToken: nil, refreshToken: "rt-move", expiresAt: nil)

        final class Observed: @unchecked Sendable {
            var copiesWhenTheRecordMoved: (temporary: String?, real: String?)?
        }
        let observed = Observed()
        // `$accounts` publishes the new list as it is assigned, so this runs inside the update.
        let watching = manager.accountStore.$accounts.sink { accounts in
            guard observed.copiesWhenTheRecordMoved == nil, accounts.contains(where: { $0.id == realId }) else { return }
            observed.copiesWhenTheRecordMoved = (
                OAuthTokenStorage.load(for: tempId).tokens.refreshToken,
                OAuthTokenStorage.load(for: realId).tokens.refreshToken
            )
        }
        defer { watching.cancel() }

        manager.resolveAccountIdentity(tempId: tempId, realOrgId: realId)

        #expect(observed.copiesWhenTheRecordMoved?.real == "rt-move", "the record moved before its new id had a token")
        #expect(observed.copiesWhenTheRecordMoved?.temporary == "rt-move", "the temporary copy was removed before the record moved")
        #expect(OAuthTokenStorage.load(for: realId).tokens.refreshToken == "rt-move")
        #expect(OAuthTokenStorage.load(for: tempId).tokens.refreshToken == nil)
        #expect(manager.isAuthenticated(accountId: realId))
    }

    /// Found in review: the record was pointed at the real id whether or not the Keychain
    /// had taken the token under it. If the write had failed and the app then quit, the next
    /// launch found a record for the real id and a token only under the temporary one.
    @Test func resolvingAnAccountId_waitsUntilTheTokenIsStored() {
        let manager = OAuthManager()
        manager.identityMoveRetryInterval = 0
        let tempId = "pending-\(UUID().uuidString)"
        let realId = "org-\(UUID().uuidString)"
        manager.accountStore.add(AccountRecord(id: tempId, addedAt: Date()))
        defer {
            manager.signOut(accountId: realId)
            manager.signOut(accountId: tempId)
        }
        manager.storeTokens(accountId: tempId, provider: .claude, accessToken: nil, refreshToken: "rt-wait", expiresAt: nil)

        // The Keychain does not take the copy.
        manager.tokenCopy = { _, _ in false }
        manager.resolveAccountIdentity(tempId: tempId, realOrgId: realId)

        #expect(manager.accountStore.accounts.contains { $0.id == tempId }, "the record must keep the id its stored token is under")
        #expect(!manager.accountStore.accounts.contains { $0.id == realId })
        #expect(manager.isAuthenticated(accountId: tempId), "and the account is still signed in")
        #expect(!manager.isAuthenticated(accountId: realId))
        #expect(OAuthTokenStorage.load(for: tempId).tokens.refreshToken == "rt-wait")

        // It runs again after a later API call; this time the copy lands.
        manager.tokenCopy = { OAuthTokenStorage.copy(from: $0, to: $1) }
        manager.resolveAccountIdentity(tempId: tempId, realOrgId: realId)

        #expect(manager.accountStore.accounts.contains { $0.id == realId })
        #expect(OAuthTokenStorage.load(for: realId).tokens.refreshToken == "rt-wait")
        #expect(OAuthTokenStorage.load(for: tempId).tokens.refreshToken == nil)
    }

    /// Found in review, twice. The same organisation signed in twice: account A is registered
    /// under the real id, and B is still under a temporary one. When B's move failed, the
    /// attempt left B's token on its way to A's id, where it later replaced A's, even after
    /// B had been signed out. A failed move must leave A exactly as it was, in memory and in
    /// storage. (`RefreshTokenVaultTests` covers the storage half: a failed copy leaves
    /// nothing behind.)
    @Test func aFailedAccountIdMove_leavesTheOtherAccountAlone() {
        let manager = OAuthManager()
        let tempId = "pending-\(UUID().uuidString)"
        let realId = "org-\(UUID().uuidString)"
        manager.accountStore.add(AccountRecord(id: realId, addedAt: Date()))
        manager.accountStore.add(AccountRecord(id: tempId, addedAt: Date()))
        defer {
            manager.signOut(accountId: realId)
            manager.signOut(accountId: tempId)
        }
        manager.storeTokens(accountId: realId, provider: .claude, accessToken: "at-A", refreshToken: "rt-A", expiresAt: Date().addingTimeInterval(3_600))
        manager.storeTokens(accountId: tempId, provider: .claude, accessToken: nil, refreshToken: "rt-B", expiresAt: nil)

        final class Saves: @unchecked Sendable { var keys: [String] = [] }
        let saves = Saves()
        manager.tokenPersistence = { tokens, storageKey in
            saves.keys.append(storageKey)
            OAuthTokenStorage.save(tokens, for: storageKey)
        }
        manager.tokenCopy = { _, _ in false }
        manager.resolveAccountIdentity(tempId: tempId, realOrgId: realId)

        #expect(saves.keys.isEmpty, "a failed move must write nothing: \(saves.keys)")
        #expect(OAuthTokenStorage.load(for: realId).tokens.refreshToken == "rt-A")

        manager.signOut(accountId: tempId)
        #expect(OAuthTokenStorage.load(for: realId).tokens.refreshToken == "rt-A")
        #expect(manager.isAuthenticated(accountId: realId))
        #expect(OAuthTokenStorage.load(for: tempId).tokens.refreshToken == nil)
    }

    /// The move is retried after every API call while the account is pending. Without a
    /// wait, a Keychain that prompts for each write would prompt on every poll.
    @Test func aFailedAccountIdMove_isNotRetriedStraightAway() {
        let manager = OAuthManager()
        let tempId = "pending-\(UUID().uuidString)"
        let realId = "org-\(UUID().uuidString)"
        manager.accountStore.add(AccountRecord(id: tempId, addedAt: Date()))
        defer {
            manager.signOut(accountId: realId)
            manager.signOut(accountId: tempId)
        }
        manager.storeTokens(accountId: tempId, provider: .claude, accessToken: nil, refreshToken: "rt-later", expiresAt: nil)

        final class Count: @unchecked Sendable { var value = 0 }
        let attempts = Count()
        manager.tokenCopy = { _, _ in
            attempts.value += 1
            return false
        }
        manager.resolveAccountIdentity(tempId: tempId, realOrgId: realId)
        manager.resolveAccountIdentity(tempId: tempId, realOrgId: realId)
        manager.resolveAccountIdentity(tempId: tempId, realOrgId: realId)

        #expect(attempts.value == 1, "the next polls must wait out the retry interval")
    }

    /// Control for the test above: the same transport with no sign-out stores the token.
    @Test func refresh_withoutSignOut_installsNewTokens() async {
        let manager = OAuthManager()
        let accountId = "a4-control-\(UUID().uuidString)"
        defer {
            manager.signOut(accountId: accountId)
            OAuthTokenStorage.delete(for: accountId)
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
        defer {
            manager.signOut(accountId: accountId)
            OAuthTokenStorage.delete(for: accountId)
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
            OAuthTokenStorage.delete(for: failing)
            OAuthTokenStorage.delete(for: healthy)
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
            OAuthTokenStorage.delete(for: accountId)
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

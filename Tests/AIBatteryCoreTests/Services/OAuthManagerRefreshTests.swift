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

    /// Waits for the stubbed transport to be entered, for at most five seconds, so a
    /// regression that never calls it fails the test instead of hanging the suite.
    private static func entered(_ gate: Gate) async -> Bool {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if await gate.hasBeenEntered() {
                return true
            }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        return false
    }

    /// `signOut` records the provider to offer on the signed-out screen in
    /// `UserDefaults.standard`. A test that signs out puts the previous value back, so the
    /// suite leaves no trace for the tests that run after it.
    private static func restoringSignedOutProvider() -> () -> Void {
        let previous = UserDefaults.standard.object(forKey: UserDefaultsKeys.signedOutProvider)
        return { UserDefaults.standard.set(previous, forKey: UserDefaultsKeys.signedOutProvider) }
    }

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
        let restoreSignedOutProvider = Self.restoringSignedOutProvider()
        defer { restoreSignedOutProvider() }
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
        guard await Self.entered(gate) else {
            Issue.record("the refresh never reached the token endpoint")
            await gate.open()
            return
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
        let restoreSignedOutProvider = Self.restoringSignedOutProvider()
        defer { restoreSignedOutProvider() }
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
        let restoreSignedOutProvider = Self.restoringSignedOutProvider()
        defer { restoreSignedOutProvider() }
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
        let restoreSignedOutProvider = Self.restoringSignedOutProvider()
        defer { restoreSignedOutProvider() }
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
        let restoreSignedOutProvider = Self.restoringSignedOutProvider()
        defer { restoreSignedOutProvider() }
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

    /// Found in the seventh review. A refresh request can take a minute and more. If the
    /// user signs in again to the same account meanwhile (same id), the old request's
    /// "invalid grant" is about a token that is already gone. It signed out the new sign-in
    /// and deleted its fresh token.
    @Test func aRefreshFailingAfterANewSignIn_leavesTheNewSignInAlone() async {
        let restoreSignedOutProvider = Self.restoringSignedOutProvider()
        defer { restoreSignedOutProvider() }
        let manager = OAuthManager()
        let accountId = "a4-relogin-\(UUID().uuidString)"
        defer {
            manager.signOut(accountId: accountId)
            OAuthTokenStorage.delete(for: accountId)
        }
        manager.seedTokensForTesting(accountId: accountId, accessToken: nil, refreshToken: "rt-old", expiresAt: nil)

        let gate = Gate()
        manager.tokenRetryPolicy = Self.noDelay
        manager.tokenTransport = { request in
            await gate.enter()
            return try Self.response(request, status: 400, body: #"{"error":"invalid_grant"}"#)
        }
        let refresh = Task { await manager.getAccessToken(for: accountId) }
        guard await Self.entered(gate) else {
            Issue.record("the refresh never reached the token endpoint")
            await gate.open()
            return
        }

        manager.storeTokens(accountId: accountId, provider: .claude, accessToken: "at-fresh", refreshToken: "rt-fresh", expiresAt: Date().addingTimeInterval(3_600))
        await gate.open()
        _ = await refresh.value

        #expect(manager.isAuthenticated(accountId: accountId), "the old request's failure signed out the new sign-in")
        #expect(manager.lastSignOutReason == nil)
        #expect(OAuthTokenStorage.load(for: accountId).tokens.refreshToken == "rt-fresh")
        #expect(!manager.isRefreshBackingOff(accountId: accountId))
    }

    /// The same race with a successful answer: tokens derived from the old credential must
    /// not overwrite the ones the user just signed in with.
    @Test func aRefreshSucceedingAfterANewSignIn_doesNotOverwriteIt() async {
        let restoreSignedOutProvider = Self.restoringSignedOutProvider()
        defer { restoreSignedOutProvider() }
        let manager = OAuthManager()
        let accountId = "a4-relogin-ok-\(UUID().uuidString)"
        defer {
            manager.signOut(accountId: accountId)
            OAuthTokenStorage.delete(for: accountId)
        }
        manager.seedTokensForTesting(accountId: accountId, accessToken: nil, refreshToken: "rt-old", expiresAt: nil)

        let gate = Gate()
        manager.tokenRetryPolicy = Self.noDelay
        manager.tokenTransport = { request in
            await gate.enter()
            return try Self.response(request, status: 200, body: Self.validTokenBody)
        }
        let refresh = Task { await manager.getAccessToken(for: accountId) }
        guard await Self.entered(gate) else {
            Issue.record("the refresh never reached the token endpoint")
            await gate.open()
            return
        }

        manager.storeTokens(accountId: accountId, provider: .claude, accessToken: "at-fresh", refreshToken: "rt-fresh", expiresAt: Date().addingTimeInterval(3_600))
        await gate.open()
        _ = await refresh.value

        #expect(OAuthTokenStorage.load(for: accountId).tokens.refreshToken == "rt-fresh", "the old request overwrote the new sign-in")
        #expect(await manager.getAccessToken(for: accountId) == "at-fresh")
    }

    /// Found in the seventh review. An install migrated by a version without the done-flag,
    /// whose delete of the old single-account entry failed, kept that entry. With accounts
    /// registered the migration returned early and never set the flag, so signing out of
    /// every account later migrated the leftover back in. It now sets the flag and leaves
    /// the old entries alone. (Real Keychain items are not touched by this test: it checks
    /// the flag only.)
    @Test func legacyMigration_withAccountsRegistered_setsItsFlag() {
        let flag = "aibattery_legacyKeychainLayoutMigrated"
        let wasSet = UserDefaults.standard.object(forKey: flag)
        defer { UserDefaults.standard.set(wasSet, forKey: flag) }

        let manager = OAuthManager()
        let accountId = "org-legacy-\(UUID().uuidString)"
        manager.accountStore.add(AccountRecord(id: accountId, addedAt: Date()))
        defer { manager.accountStore.remove(id: accountId) }
        UserDefaults.standard.removeObject(forKey: flag)

        manager.migrateFromLegacy()

        #expect(UserDefaults.standard.bool(forKey: flag), "a leftover old entry could be migrated back in later")
    }

    /// Control for the test above: the same transport with no sign-out stores the token.
    @Test func refresh_withoutSignOut_installsNewTokens() async {
        let restoreSignedOutProvider = Self.restoringSignedOutProvider()
        defer { restoreSignedOutProvider() }
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

    // MARK: - A rejected sign-in keeps its account

    /// A refresh token the provider rejects used to remove the account: it vanished from
    /// the overview, and the next launch dropped its history (2026-11-18). The account now
    /// stays, signed out, with the reason ready for the sign-in screen.
    @Test func rejectedRefresh_keepsTheAccountSignedOut() async {
        let restoreSignedOutProvider = Self.restoringSignedOutProvider()
        defer { restoreSignedOutProvider() }
        let manager = OAuthManager()
        let accountId = "expired-\(UUID().uuidString)"
        manager.accountStore.add(AccountRecord(id: accountId, displayName: "Work", addedAt: Date()))
        defer {
            manager.signOut(accountId: accountId)
            OAuthTokenStorage.delete(for: accountId)
        }
        manager.seedTokensForTesting(accountId: accountId, accessToken: nil, refreshToken: "rt-old", expiresAt: nil)
        manager.tokenRetryPolicy = Self.noDelay
        manager.tokenTransport = { request in try Self.response(request, status: 400, body: #"{"error":"invalid_grant"}"#) }

        #expect(await manager.getAccessToken(for: accountId) == nil)
        #expect(!manager.isAuthenticated(accountId: accountId))
        #expect(manager.accountStore.account(id: accountId)?.displayName == "Work", "the account and its name must stay")
        #expect(manager.lastSignOutReason == OAuthManager.sessionExpiredReason(for: .claude))
    }

    /// The active account drives the whole popover. When its sign-in is rejected and another
    /// account is still signed in, the popover moves there instead of the sign-in screen.
    @Test func rejectedActiveAccount_movesToASignedInAccount() async {
        let restoreSignedOutProvider = Self.restoringSignedOutProvider()
        defer { restoreSignedOutProvider() }
        let manager = OAuthManager()
        let rejected = "rejected-\(UUID().uuidString)"
        let healthy = "healthy-\(UUID().uuidString)"
        manager.accountStore.add(AccountRecord(id: rejected, addedAt: Date()))
        manager.accountStore.add(AccountRecord(id: healthy, addedAt: Date()))
        defer {
            for id in [rejected, healthy] {
                manager.signOut(accountId: id)
                OAuthTokenStorage.delete(for: id)
            }
        }
        manager.seedTokensForTesting(accountId: rejected, accessToken: nil, refreshToken: "rt-rejected", expiresAt: nil)
        manager.seedTokensForTesting(accountId: healthy, accessToken: "at", refreshToken: "rt-healthy", expiresAt: .distantFuture)
        manager.accountStore.setActive(id: rejected)
        manager.tokenRetryPolicy = Self.noDelay
        manager.tokenTransport = { request in try Self.response(request, status: 401, body: #"{"error":"invalid_grant"}"#) }

        #expect(await manager.getAccessToken(for: rejected) == nil)
        #expect(manager.accountStore.activeAccountId == healthy)
        #expect(manager.isAuthenticated)
        #expect(manager.accountStore.account(id: rejected) != nil)
    }

    /// Removing an account is still a removal: only the provider's rejection keeps it.
    @Test func userSignOut_stillRemovesTheAccount() {
        let restoreSignedOutProvider = Self.restoringSignedOutProvider()
        defer { restoreSignedOutProvider() }
        let manager = OAuthManager()
        let accountId = "removed-\(UUID().uuidString)"
        manager.accountStore.add(AccountRecord(id: accountId, addedAt: Date()))
        manager.seedTokensForTesting(accountId: accountId, accessToken: "at", refreshToken: "rt", expiresAt: nil)

        manager.signOut(accountId: accountId)

        #expect(manager.accountStore.account(id: accountId) == nil)
        #expect(!manager.isAuthenticated(accountId: accountId))
    }

    // MARK: - Transient-failure backoff

    /// A transient refresh failure used to be retried on the very next poll, and each
    /// attempt costs three requests with sleeps between them. The account now backs off,
    /// stays authenticated, and the endpoint is not touched again until the window ends.
    @Test func transientFailure_backsOffAndSkipsTheNextAttempt() async {
        let restoreSignedOutProvider = Self.restoringSignedOutProvider()
        defer { restoreSignedOutProvider() }
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
        let restoreSignedOutProvider = Self.restoringSignedOutProvider()
        defer { restoreSignedOutProvider() }
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
        let restoreSignedOutProvider = Self.restoringSignedOutProvider()
        defer { restoreSignedOutProvider() }
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

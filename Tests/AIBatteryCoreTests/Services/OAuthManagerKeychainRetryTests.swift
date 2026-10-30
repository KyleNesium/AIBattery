import Foundation
import Testing
@testable import AIBatteryCore

/// A saved sign-in the Keychain couldn't hand over (a prompt cancelled by sleep, a locked
/// keychain) keeps the account signed in and is re-read off the main actor, instead of
/// dropping the user on the sign-in screen while their token is still stored.
@Suite("OAuthManager — Keychain read retry", .serialized)
@MainActor
struct OAuthManagerKeychainRetryTests {
    private static let validTokenBody = #"{"access_token":"at-new","refresh_token":"rt-new","expires_in":3600}"#

    /// Scripted Keychain reader: hands out results in order, counts reads, and can hold
    /// the first read until the test releases it (a prompt still waiting for an answer).
    private final class ScriptedReader: @unchecked Sendable {
        private let lock = NSLock()
        private var results: [KeychainHelper.ReadResult]
        private var calls = 0
        private let hold: DispatchSemaphore?

        init(_ results: KeychainHelper.ReadResult..., holding: Bool = false) {
            self.results = results
            hold = holding ? DispatchSemaphore(value: 0) : nil
        }

        func read(_: String) -> KeychainHelper.ReadResult {
            hold?.wait()
            lock.lock()
            defer { lock.unlock() }
            calls += 1
            return results.isEmpty ? .notFound : results.removeFirst()
        }

        func release() {
            hold?.signal()
        }

        var callCount: Int {
            lock.lock()
            defer { lock.unlock() }
            return calls
        }
    }

    private func unreadableAccount(_ manager: OAuthManager) -> String {
        let accountId = "kc-retry-\(UUID().uuidString)"
        manager.seedUnreadableKeychainForTesting(accountId: accountId)
        return accountId
    }

    nonisolated private static func response(_ request: URLRequest, status: Int, body: String) throws -> (Data, URLResponse) {
        let url = try #require(request.url)
        let http = try #require(HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil))
        return (Data(body.utf8), http)
    }

    /// The 2026-10-30 incident: the launch read failed, the token was still in Keychain.
    @Test func failedRead_staysSignedIn_thenRestoresTheSavedToken() async {
        let manager = OAuthManager()
        let accountId = unreadableAccount(manager)
        defer { KeychainHelper.delete(account: "refreshToken_\(accountId)") }
        #expect(manager.isAuthenticated(accountId: accountId), "a sign-in we couldn't read is not a sign-out")

        let reader = ScriptedReader(.found("rt-saved"))
        manager.keychainRead = { reader.read($0) }
        #expect(await manager.getAccessToken(for: accountId) == nil, "this cycle keeps the last reading")
        await manager.pendingKeychainRetry(accountId: accountId)?.value
        #expect(reader.callCount == 1)
        #expect(manager.isAuthenticated(accountId: accountId))

        // The next cycle refreshes with the token the retry restored.
        manager.tokenRetryPolicy = RetryPolicy(baseDelay: 0, maxDelay: 0)
        manager.tokenTransport = { request in
            let body = request.httpBody.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            return try Self.response(request, status: body.contains("rt-saved") ? 200 : 400, body: Self.validTokenBody)
        }
        #expect(await manager.getAccessToken(for: accountId) == "at-new")
    }

    /// A read that keeps failing stays signed in, raises one prompt however many callers
    /// ask, and waits out the refresh backoff before asking again.
    @Test func stillFailing_raisesOnePrompt_andBacksOff() async {
        let manager = OAuthManager()
        let accountId = unreadableAccount(manager)
        let reader = ScriptedReader(.failed(errSecInDarkWake), holding: true)
        manager.keychainRead = { reader.read($0) }

        _ = await manager.getAccessToken(for: accountId)
        _ = await manager.getAccessToken(for: accountId) // while the first read is still out
        let retry = manager.pendingKeychainRetry(accountId: accountId)
        reader.release()
        await retry?.value

        #expect(reader.callCount == 1)
        #expect(manager.isAuthenticated(accountId: accountId))
        #expect(manager.isRefreshBackingOff(accountId: accountId))
        _ = await manager.getAccessToken(for: accountId)
        #expect(manager.pendingKeychainRetry(accountId: accountId) == nil, "backing off: no new read")
    }

    /// The item is really gone: that is a sign-out, same as finding nothing at launch.
    @Test func notFoundOnRetry_signsOut() async {
        let manager = OAuthManager()
        let accountId = unreadableAccount(manager)
        let reader = ScriptedReader(.notFound)
        manager.keychainRead = { reader.read($0) }

        _ = await manager.getAccessToken(for: accountId)
        await manager.pendingKeychainRetry(accountId: accountId)?.value
        #expect(!manager.isAuthenticated(accountId: accountId))
    }

    /// Deny / Cancel on the prompt is an answer, not a glitch: no prompt loop.
    @Test func refusedPrompt_signsOut_andIsNotRetried() async {
        let manager = OAuthManager()
        let accountId = unreadableAccount(manager)
        let reader = ScriptedReader(.failed(errSecUserCanceled))
        manager.keychainRead = { reader.read($0) }

        _ = await manager.getAccessToken(for: accountId)
        await manager.pendingKeychainRetry(accountId: accountId)?.value
        #expect(!manager.isAuthenticated(accountId: accountId))
        _ = await manager.getAccessToken(for: accountId)
        #expect(manager.pendingKeychainRetry(accountId: accountId) == nil)
        #expect(reader.callCount == 1)
    }

    /// Removing the account while its prompt is up must win over the read's answer.
    @Test func signOutDuringRetry_discardsTheRead() async {
        let manager = OAuthManager()
        let accountId = unreadableAccount(manager)
        let reader = ScriptedReader(.found("rt-saved"), holding: true)
        manager.keychainRead = { reader.read($0) }

        _ = await manager.getAccessToken(for: accountId)
        let retry = manager.pendingKeychainRetry(accountId: accountId)
        manager.signOut(accountId: accountId)
        reader.release()
        await retry?.value

        #expect(!manager.isAuthenticated(accountId: accountId))
        #expect(KeychainHelper.get(account: "refreshToken_\(accountId)") == nil)
    }

    @Test func onlyRefusalsAreFinal() {
        #expect(OAuthManager.isRetryableReadFailure(errSecInDarkWake))
        #expect(OAuthManager.isRetryableReadFailure(errSecInteractionNotAllowed))
        // "Unable to obtain authorization": the prompt was torn down as the Mac slept.
        #expect(OAuthManager.isRetryableReadFailure(-60_008))
        #expect(!OAuthManager.isRetryableReadFailure(errSecUserCanceled))
        #expect(!OAuthManager.isRetryableReadFailure(errSecAuthFailed))
    }

    /// Storage keeps "couldn't read" apart from "nothing saved".
    @Test func load_reportsAFailedReadSeparatelyFromNoItem() {
        let accountId = "kc-load-\(UUID().uuidString)"
        let failed = OAuthTokenStorage.load(for: accountId, readKeychain: { _ in .failed(errSecInDarkWake) })
        #expect(failed.readFailure == errSecInDarkWake)
        #expect(failed.tokens.refreshToken == nil)

        let missing = OAuthTokenStorage.load(for: accountId, readKeychain: { _ in .notFound })
        #expect(missing.readFailure == nil)
        #expect(missing.tokens.refreshToken == nil)

        let found = OAuthTokenStorage.load(for: accountId, readKeychain: { _ in .found("rt") })
        #expect(found.readFailure == nil)
        #expect(found.tokens.refreshToken == "rt")

        #expect(KeychainHelper.read(account: "kc-missing-\(UUID().uuidString)") == .notFound)
    }
}

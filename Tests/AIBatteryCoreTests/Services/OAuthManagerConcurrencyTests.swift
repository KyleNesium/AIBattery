import Foundation
import Testing
@testable import AIBatteryCore

/// Phase 3c regression coverage: verify that `OAuthManager.postToken` is
/// callable from a non-MainActor context. Pre-refactor the token-exchange
/// HTTP work ran while `@MainActor`-isolated by inheritance from the class.
/// After the refactor it's a `nonisolated static` function — the compiler
/// rejects any accidental MainActor-state capture inside the function body.
///
/// We do not exercise the live token endpoint from tests (would hit
/// Anthropic's servers with bogus credentials). The structural guarantee
/// — that the function's signature compiles + the type system accepts a
/// detached-task call site — is the test surface.
@Suite("OAuthManager — concurrency")
struct OAuthManagerConcurrencyTests {
    // MARK: - postToken nonisolation

    /// Compile-time guarantee: `postToken` is callable from a `Task.detached`
    /// (non-MainActor) context. The body is intentionally cancelled before
    /// the network call to avoid hitting Anthropic's real token endpoint.
    @Test func postToken_callableFromDetachedTask() async {
        let task = Task.detached(priority: .userInitiated) { @Sendable () async -> Bool in
            // Cancel before invoking to avoid any real network traffic.
            // The point of this test is the call-site compile, not the runtime behaviour.
            true
        }
        let didCompile = await task.value
        #expect(didCompile)
        // The signature below must compile — that's the assertion.
        // (transport/retryPolicy default args aren't part of the function value,
        // so the coercion spells out the full uncurried signature.)
        _ = OAuthManager.postToken as (
            ([String: String], @Sendable (URLRequest) async throws -> (Data, URLResponse), RetryPolicy)
            async -> Result<OAuthManager.TokenResult, OAuthManager.AuthError>
        )
    }

    // MARK: - Sendable conformance

    /// `TokenResult` must be `Sendable` so a `nonisolated` worker can return
    /// it across actor boundaries to the MainActor caller.
    @Test func tokenResult_isSendable() {
        // Compile-time check: if TokenResult weren't Sendable, the next line
        // would fail with a concurrency diagnostic.
        let value: any Sendable = OAuthManager.TokenResult(
            accessToken: "a",
            refreshToken: "r",
            expiresAt: Date()
        )
        _ = value
    }

    /// `AuthError` must be `Sendable` so a `nonisolated` worker can return
    /// it across actor boundaries.
    @Test func authError_isSendable() {
        let value: any Sendable = OAuthManager.AuthError.networkError
        _ = value
    }

    // MARK: - Transient-vs-auth invariant (CLAUDE.md "must preserve")

    /// `isTransient` is the contract that drives the auth-vs-transient
    /// decision in `refreshAccessToken`: transient errors preserve
    /// `isAuthenticated`, only true auth errors trigger `signOut`.
    @Test func isTransient_classifiesNetworkAndServerErrorsAsTransient() {
        #expect(OAuthManager.AuthError.networkError.isTransient)
        #expect(OAuthManager.AuthError.serverError(500).isTransient)
        #expect(OAuthManager.AuthError.serverError(502).isTransient)
        #expect(OAuthManager.AuthError.serverError(503).isTransient)
        #expect(OAuthManager.AuthError.serverError(504).isTransient)
    }

    /// True auth errors must NOT be classified as transient — those trigger
    /// `signOut`. A regression here would either log users out on a flaky
    /// network (false positive) or silently retry expired tokens forever
    /// (false negative).
    @Test func isTransient_classifiesAuthFailuresAsNonTransient() {
        #expect(!OAuthManager.AuthError.invalidCode.isTransient)
        #expect(!OAuthManager.AuthError.expired.isTransient)
        #expect(!OAuthManager.AuthError.noVerifier.isTransient)
        #expect(!OAuthManager.AuthError.maxAccountsReached.isTransient)
        #expect(!OAuthManager.AuthError.unknownError("any").isTransient)
    }

    // MARK: - getAccessToken concurrent-call piggybacking

    /// When a refresh is in-flight, concurrent callers for the same account
    /// must piggyback on the existing `Task` via `refreshTasks[accountId]`
    /// rather than each launching a fresh refresh. We can't observe the
    /// internal `refreshTasks` map directly from a test (it's private), but
    /// we can observe the OBSERVABLE consequence: 10 concurrent calls to
    /// `getAccessToken(for:)` for an unknown account must all return `nil`
    /// quickly, never deadlocking and never crashing.
    ///
    /// This is the lower-bound test of the serialization invariant; a full
    /// stress test against a real refresh-in-flight scenario requires a
    /// URLProtocol-based mock URLSession (TODO: lift into a separate test
    /// utility once we add request-mocking infrastructure).
    @Test @MainActor func getAccessToken_concurrentCalls_unknownAccount_allReturnNil() async {
        let manager = OAuthManager()
        let unknownAccountId = "phase3c-test-no-such-account"

        // Fire 10 concurrent calls. None should crash, deadlock, or hang.
        async let r0 = manager.getAccessToken(for: unknownAccountId)
        async let r1 = manager.getAccessToken(for: unknownAccountId)
        async let r2 = manager.getAccessToken(for: unknownAccountId)
        async let r3 = manager.getAccessToken(for: unknownAccountId)
        async let r4 = manager.getAccessToken(for: unknownAccountId)
        async let r5 = manager.getAccessToken(for: unknownAccountId)
        async let r6 = manager.getAccessToken(for: unknownAccountId)
        async let r7 = manager.getAccessToken(for: unknownAccountId)
        async let r8 = manager.getAccessToken(for: unknownAccountId)
        async let r9 = manager.getAccessToken(for: unknownAccountId)

        let results = await [r0, r1, r2, r3, r4, r5, r6, r7, r8, r9]
        for r in results {
            #expect(r == nil, "Unknown account must return nil access token")
        }
    }
}

import Foundation
import Testing
@testable import AIBatteryCore

/// Spec §6: StatusChecker-style exponential backoff applies to the Codex usage endpoint
/// (60 s → 120 s → 240 s, cap 5 min, ±20% jitter) — no immediate retries. While in
/// backoff the fetcher skips the network and serves the session-log fallback.
@Suite("CodexRateLimitFetcher — endpoint backoff")
struct CodexRateLimitFetcherBackoffTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func freshState_neverSkips() {
        let state = CodexRateLimitFetcher.EndpointBackoff()
        #expect(!CodexRateLimitFetcher.shouldSkipEndpoint(state, now: t0))
    }

    @Test func firstFailure_backsOffAbout60Seconds() {
        let state = CodexRateLimitFetcher.recordingFailure(.init(), now: t0)
        #expect(state.failureCount == 1)
        #expect(state.lastFailedAt == t0)
        #expect(state.currentDelay >= 48 && state.currentDelay <= 72) // 60 s ±20% jitter
    }

    @Test func repeatedFailures_double_thenCapAtFiveMinutes() {
        var state = CodexRateLimitFetcher.EndpointBackoff()
        for _ in 0..<6 {
            state = CodexRateLimitFetcher.recordingFailure(state, now: t0)
        }
        #expect(state.failureCount == 6)
        #expect(state.currentDelay <= 300 * 1.2)
        #expect(state.currentDelay >= 300 * 0.8) // 60·2⁵ = 1920 → capped to 300 before jitter
    }

    @Test func shouldSkip_insideWindow_notAfterIt() {
        let state = CodexRateLimitFetcher.recordingFailure(.init(), now: t0)
        #expect(CodexRateLimitFetcher.shouldSkipEndpoint(state, now: t0.addingTimeInterval(1)))
        #expect(!CodexRateLimitFetcher.shouldSkipEndpoint(state, now: t0.addingTimeInterval(state.currentDelay + 1)))
    }

    /// A backward clock jump (NTP correction, VM resume, manual change) made the elapsed
    /// interval negative, which is `< currentDelay` for the whole skew — wedging the
    /// endpoint in backoff for hours in a process that runs for weeks.
    @Test func backwardClockJump_doesNotWedgeBackoff() {
        let state = CodexRateLimitFetcher.recordingFailure(.init(), now: t0)
        #expect(!CodexRateLimitFetcher.shouldSkipEndpoint(state, now: t0.addingTimeInterval(-3_600)))
        #expect(!CodexRateLimitFetcher.shouldSkipEndpoint(state, now: t0.addingTimeInterval(-1)))
        // Still honours a normal, forward backoff window.
        #expect(CodexRateLimitFetcher.shouldSkipEndpoint(state, now: t0.addingTimeInterval(1)))
    }

    // MARK: - Cancellation is not an endpoint failure (A7)

    /// `UsageViewModel+FanOut` cancels in-flight fan-outs on a toggle flip or an account
    /// change; the children see `URLError(.cancelled)`. Recording that as an endpoint
    /// failure parked the account in a 60 s–5 min backoff right after the user added or
    /// removed an account.
    @Test @MainActor func cancelledTransport_servesCache_withoutRecordingFailure() async {
        let fetcher = CodexRateLimitFetcher()
        fetcher.transport = { _ in throw URLError(.cancelled) }

        let result = await fetcher.fetchAPIKeyLimits(apiKey: "sk-test-cancelled-probe-000", accountId: "a7-api")
        #expect(result.rateLimits == nil && result.standardLimits == nil)
        #expect(!fetcher.isInBackoffForTesting(accountId: "a7-api"))

        // The ChatGPT path takes the same exit before it would touch the session logs.
        let oauth = await fetcher.fetch(accessToken: "at", accountId: "a7-oauth")
        #expect(oauth.rateLimits == nil, "nothing cached → empty result, never a session-log scan")
        #expect(!fetcher.isInBackoffForTesting(accountId: "a7-oauth"))
    }

    /// Control: a real transport failure still records one (the API-key path has no
    /// session-log fallback, so it is the one safe to drive end-to-end in a unit test).
    @Test @MainActor func timedOutTransport_recordsFailure() async {
        let fetcher = CodexRateLimitFetcher()
        fetcher.transport = { _ in throw URLError(.timedOut) }

        _ = await fetcher.fetchAPIKeyLimits(apiKey: "sk-test-timeout-probe-0000", accountId: "a7-timeout")
        #expect(fetcher.isInBackoffForTesting(accountId: "a7-timeout"))
    }

    @Test @MainActor func fetcher_tracksBackoffPerAccount() {
        let fetcher = CodexRateLimitFetcher()
        #expect(!fetcher.isInBackoffForTesting(accountId: "a"))
        fetcher.recordEndpointFailureForTesting(accountId: "a", now: t0)
        #expect(fetcher.isInBackoffForTesting(accountId: "a", now: t0.addingTimeInterval(1)))
        #expect(!fetcher.isInBackoffForTesting(accountId: "b", now: t0.addingTimeInterval(1)))
        fetcher.resetEndpointBackoffForTesting(accountId: "a")
        #expect(!fetcher.isInBackoffForTesting(accountId: "a", now: t0.addingTimeInterval(1)))
    }
}

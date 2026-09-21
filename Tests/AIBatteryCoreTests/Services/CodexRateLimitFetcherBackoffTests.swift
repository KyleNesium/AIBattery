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

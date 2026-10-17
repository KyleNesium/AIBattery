import Foundation
import Testing
@testable import AIBatteryCore

/// The Claude usage endpoint gets the same StatusChecker-style backoff the Codex one has
/// had since it shipped (60 s → 120 s → 240 s, cap 5 min, ±20% jitter). Without it, an
/// outage on `/api/oauth/usage` turned every poll into a burst: the usage call, then a
/// Messages probe per candidate model, then a client-data read on each header-less
/// success — against two further endpoints, every cycle, for as long as it stayed down.
@MainActor
@Suite("RateLimitFetcher — usage endpoint backoff")
struct RateLimitFetcherBackoffTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func freshAccount_isNotInBackoff() {
        let fetcher = RateLimitFetcher()
        #expect(!fetcher.isUsageEndpointInBackoff(accountId: "a", now: t0))
    }

    @Test func afterAFailure_theAccountIsSkippedForAboutAMinute() {
        let fetcher = RateLimitFetcher()
        fetcher.recordUsageEndpointFailure(accountId: "a", now: t0)

        #expect(fetcher.isUsageEndpointInBackoff(accountId: "a", now: t0.addingTimeInterval(1)))
        // 60 s ±20% jitter — past the widest window it must be live again.
        #expect(!fetcher.isUsageEndpointInBackoff(accountId: "a", now: t0.addingTimeInterval(73)))
    }

    @Test func backoffIsPerAccount() {
        let fetcher = RateLimitFetcher()
        fetcher.recordUsageEndpointFailure(accountId: "a", now: t0)

        #expect(fetcher.isUsageEndpointInBackoff(accountId: "a", now: t0.addingTimeInterval(1)))
        #expect(!fetcher.isUsageEndpointInBackoff(accountId: "b", now: t0.addingTimeInterval(1)))
    }

    @Test func repeatedFailuresLengthenTheWindow_thenCapAtFiveMinutes() {
        let fetcher = RateLimitFetcher()
        for _ in 0..<6 {
            fetcher.recordUsageEndpointFailure(accountId: "a", now: t0)
        }

        // 60·2⁵ = 1920 s, capped to 300 s before jitter.
        #expect(fetcher.isUsageEndpointInBackoff(accountId: "a", now: t0.addingTimeInterval(239)))
        #expect(!fetcher.isUsageEndpointInBackoff(accountId: "a", now: t0.addingTimeInterval(361)))
    }

    /// A success on either path (usage endpoint or Messages probe) means the account has
    /// a live data source again, so the next poll must not be skipped.
    @Test func resetClearsTheWindowImmediately() {
        let fetcher = RateLimitFetcher()
        fetcher.recordUsageEndpointFailure(accountId: "a", now: t0)
        #expect(fetcher.isUsageEndpointInBackoff(accountId: "a", now: t0.addingTimeInterval(1)))

        fetcher.resetUsageEndpointBackoff(accountId: "a")
        #expect(!fetcher.isUsageEndpointInBackoff(accountId: "a", now: t0.addingTimeInterval(1)))
    }

    /// A backward clock jump (NTP correction, VM resume, manual change) makes the elapsed
    /// interval negative, which compares `< currentDelay` for the whole skew. In a process
    /// that runs for weeks that would wedge the endpoint until the next relaunch.
    @Test func backwardClockJumpDoesNotWedgeBackoff() {
        let fetcher = RateLimitFetcher()
        fetcher.recordUsageEndpointFailure(accountId: "a", now: t0)
        #expect(!fetcher.isUsageEndpointInBackoff(accountId: "a", now: t0.addingTimeInterval(-3_600)))
    }

    /// Both fetchers share one implementation now; pin that they agree.
    @Test func claudeAndCodexShareTheSameCurve() {
        let claude = EndpointBackoff.recordingFailure(.init(), now: t0)
        let codex = CodexRateLimitFetcher.recordingFailure(.init(), now: t0)

        #expect(claude.failureCount == codex.failureCount)
        #expect(claude.currentDelay >= 48 && claude.currentDelay <= 72)
        #expect(codex.currentDelay >= 48 && codex.currentDelay <= 72)
    }
}

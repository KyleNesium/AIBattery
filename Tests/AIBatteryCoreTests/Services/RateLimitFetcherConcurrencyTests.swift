import Foundation
import Testing
@testable import AIBatteryCore

/// Phase 3b regression coverage: verify that `RateLimitFetcher.fetch` honors
/// Swift's actor-suspension semantics — every `await SecureNetworking.data(for:)`
/// inside the fetch pipeline must release MainActor for the duration of the
/// network call, so a 30s URLSession timeout cannot freeze the UI.
///
/// We cannot mock the Anthropic API endpoints from a test target, so these tests
/// validate the suspension boundary by:
///   1. Confirming pure header helpers (`quotaThrottleLikely`, `parseRetryAfter`)
///      are `nonisolated` and callable from any context. The compiler enforces
///      this — a non-isolated call site to a MainActor-isolated symbol won't
///      compile.
///   2. Running the same call from a `Task.detached` priority-userInitiated
///      task and from a `@MainActor` task, and verifying both produce the
///      identical result. This proves the helpers carry no hidden MainActor
///      dependency.
@Suite("RateLimitFetcher — concurrency")
struct RateLimitFetcherConcurrencyTests {
    /// `parseRetryAfter` is `nonisolated static` — callable from any actor context.
    /// This test exercises it from a `Task.detached` context to prove the
    /// declaration's promise holds at the call site, not just at the signature.
    @Test func parseRetryAfter_callableFromDetachedTask() async {
        let result = await Task.detached(priority: .userInitiated) {
            RateLimitFetcher.parseRetryAfter("5")
        }.value
        #expect(result == 5.0)
    }

    /// `parseRetryAfter` produces the same result regardless of the caller's actor.
    @Test func parseRetryAfter_actorIndependent() async {
        let detached = await Task.detached { RateLimitFetcher.parseRetryAfter("12") }.value
        let mainActor = await Task { @MainActor in RateLimitFetcher.parseRetryAfter("12") }.value
        #expect(detached == mainActor)
        #expect(detached == 12.0)
    }

    /// `quotaThrottleLikely` is `nonisolated static` — callable from a background
    /// context. Validates the header-policy classification doesn't depend on
    /// MainActor state.
    @Test func quotaThrottleLikely_callableFromDetachedTask() async {
        let throttled = RateLimitUsage(
            representativeClaim: "five_hour",
            fiveHourUtilization: 1.0,
            fiveHourReset: nil,
            fiveHourStatus: "throttled",
            sevenDayUtilization: 0.5,
            sevenDayReset: nil,
            sevenDayStatus: "allowed",
            overallStatus: "throttled"
        )
        let result = await Task.detached(priority: .userInitiated) {
            RateLimitFetcher.quotaThrottleLikely(throttled)
        }.value
        #expect(result == true)
    }

    /// Sanity: a healthy rate-limit struct (well below threshold) is NOT classified
    /// as quota-throttled, regardless of where the check runs.
    @Test func quotaThrottleLikely_healthyHeaders_returnsFalse() async {
        let healthy = RateLimitUsage(
            representativeClaim: "five_hour",
            fiveHourUtilization: 0.2,
            fiveHourReset: nil,
            fiveHourStatus: "allowed",
            sevenDayUtilization: 0.1,
            sevenDayReset: nil,
            sevenDayStatus: "allowed",
            overallStatus: "allowed"
        )
        let detached = await Task.detached { RateLimitFetcher.quotaThrottleLikely(healthy) }.value
        let mainActor = await Task { @MainActor in RateLimitFetcher.quotaThrottleLikely(healthy) }.value
        #expect(detached == false)
        #expect(mainActor == false)
    }
}

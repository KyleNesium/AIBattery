import Foundation

/// Per-endpoint, per-account failure backoff, shared by the Claude and Codex rate-limit
/// fetchers. An endpoint that just failed is skipped entirely for a growing delay rather
/// than retried on the next poll, so an outage costs one request per backoff window
/// instead of a fresh burst every cycle.
///
/// The curve comes from `RetryPolicy.statusCheck` — the same 60s → 120s → 240s, capped at
/// five minutes with jitter, that `StatusChecker` uses.
struct EndpointBackoff: Sendable, Equatable {
    var failureCount = 0
    var lastFailedAt: Date?
    var currentDelay: TimeInterval = 0

    /// Whether the endpoint is still inside its backoff window and should be skipped.
    static func shouldSkip(_ state: EndpointBackoff, now: Date) -> Bool {
        guard let failedAt = state.lastFailedAt, state.failureCount > 0 else { return false }
        let elapsed = now.timeIntervalSince(failedAt)
        // A backward clock jump (NTP correction, VM resume, manual change) makes `elapsed`
        // negative, which is `< currentDelay` for the whole skew. A menu-bar app runs for
        // weeks, so that would wedge the endpoint in backoff until the next relaunch.
        guard elapsed >= 0 else { return false }
        return elapsed < state.currentDelay
    }

    /// The state after one more failure: a longer delay, re-anchored to `now`.
    static func recordingFailure(_ state: EndpointBackoff, now: Date, policy: RetryPolicy = .statusCheck) -> EndpointBackoff {
        var next = state
        next.failureCount += 1
        next.lastFailedAt = now
        next.currentDelay = policy.delay(forAttempt: next.failureCount)
        return next
    }
}

import Foundation

/// A pure-value retry policy: exponential backoff with optional jitter, a delay cap,
/// and an optional maximum attempt count. Used by `OAuthManager`, `StatusChecker`,
/// `FileWatcher`, and `RateLimitFetcher` to share a single tested backoff implementation.
///
/// `RetryPolicy` is intentionally `Sendable` and `nonisolated`. It owns no mutable state
/// and contains no side effects: callers feed it an attempt number, it returns a delay.
///
/// Convention: attempts are **1-indexed** — the *first retry* is attempt 1.
public struct RetryPolicy: Sendable, Equatable {
    /// Base delay for the first retry (attempt 1).
    public let baseDelay: TimeInterval
    /// Hard cap; delays produced by `delay(forAttempt:)` and `delay(retryAfterHeader:)`
    /// are never larger than this value.
    public let maxDelay: TimeInterval
    /// Exponential growth factor between attempts. `2.0` means each retry doubles
    /// the prior delay. `1.0` means a flat delay.
    public let multiplier: Double
    /// Multiplicative jitter applied to the computed delay, e.g. `0.8...1.2` produces
    /// ±20% jitter. `nil` disables jitter (used for deterministic timers like
    /// `FileWatcher`'s stats-cache retry).
    public let jitterRange: ClosedRange<Double>?
    /// Optional maximum number of retry attempts. `nil` means unbounded — callers
    /// that need an upper bound (`FileWatcher`'s 10-retry give-up, `OAuthManager`'s
    /// `maxRetries`) read this value and stop calling `delay(forAttempt:)` once
    /// exceeded.
    public let maxAttempts: Int?

    public init(
        baseDelay: TimeInterval,
        maxDelay: TimeInterval,
        multiplier: Double = 2.0,
        jitterRange: ClosedRange<Double>? = nil,
        maxAttempts: Int? = nil
    ) {
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
        self.multiplier = multiplier
        self.jitterRange = jitterRange
        self.maxAttempts = maxAttempts
    }

    /// Delay for the n-th retry (1-indexed).
    ///
    /// Formula: `min(baseDelay * multiplier^(attempt-1), maxDelay) * jitter`
    /// where `jitter` is drawn from `jitterRange` (or `1.0` if disabled).
    ///
    /// Attempts < 1 are clamped to `attempt = 1` (no negative or zero exponent).
    public func delay(forAttempt attempt: Int) -> TimeInterval {
        delay(forAttempt: attempt, using: &SystemRandomNumberGenerator.shared)
    }

    /// Test-injectable overload. Pass a deterministic RNG to verify jitter bounds.
    public func delay<G: RandomNumberGenerator>(
        forAttempt attempt: Int,
        using generator: inout G
    ) -> TimeInterval {
        let clampedAttempt = max(1, attempt)
        let raw = baseDelay * pow(multiplier, Double(clampedAttempt - 1))
        let capped = min(raw, maxDelay)
        guard let range = jitterRange else { return capped }
        return capped * Double.random(in: range, using: &generator)
    }

    /// Parse an HTTP `Retry-After` header value (seconds form) into a delay,
    /// capped at `maxDelay`. Returns `nil` if the value is missing, non-numeric,
    /// zero, or negative.
    ///
    /// Note: this method does **not** apply jitter — server-supplied hints are
    /// authoritative and should be honored exactly (within the cap).
    public func delay(retryAfterHeader value: String?) -> TimeInterval? {
        guard let value, let delay = Double(value), delay > 0 else { return nil }
        return min(delay, maxDelay)
    }
}

// MARK: - Presets

public extension RetryPolicy {
    /// OAuth token endpoint: 1s → 2s → 4s with ±20% jitter, capped at 30s.
    /// Matches `OAuthManager`'s historical exponential-backoff loop.
    static let oauth = RetryPolicy(
        baseDelay: 1,
        maxDelay: 30,
        multiplier: 2,
        jitterRange: 0.8...1.2,
        maxAttempts: 2
    )

    /// Anthropic system-status fetch: 60s → 120s → 240s with ±20% jitter, capped at 300s.
    /// Matches `StatusChecker`'s historical backoff.
    static let statusCheck = RetryPolicy(
        baseDelay: 60,
        maxDelay: 300,
        multiplier: 2,
        jitterRange: 0.8...1.2,
        maxAttempts: nil
    )

    /// `~/.claude/stats-cache.json` discovery: 60s → 120s → 240s → 300s cap, no jitter,
    /// give up after 10 retries. Matches `FileWatcher`'s stats-cache retry.
    static let fileWatch = RetryPolicy(
        baseDelay: 60,
        maxDelay: 300,
        multiplier: 2,
        jitterRange: nil,
        maxAttempts: 10
    )

    /// `Retry-After` cap for rate-limit endpoint probes (`RateLimitFetcher`).
    /// Not used for client-side backoff — only to parse server-supplied hints.
    static let rateLimit = RetryPolicy(
        baseDelay: 1,
        maxDelay: 30,
        multiplier: 2,
        jitterRange: nil,
        maxAttempts: nil
    )
}

private extension SystemRandomNumberGenerator {
    /// Shared mutable instance so the non-injected `delay(forAttempt:)` overload
    /// has a stable target for the inout parameter. `SystemRandomNumberGenerator`
    /// is documented as thread-safe.
    static var shared = SystemRandomNumberGenerator()
}

import Foundation
import Testing
@testable import AIBatteryCore

@Suite("RetryPolicy")
struct RetryPolicyTests {
    // MARK: - Exponential growth

    @Test func delay_firstAttempt_returnsBaseDelay() {
        let policy = RetryPolicy(baseDelay: 1, maxDelay: 100, multiplier: 2)
        #expect(policy.delay(forAttempt: 1) == 1)
    }

    @Test func delay_secondAttempt_doublesBaseDelay() {
        let policy = RetryPolicy(baseDelay: 1, maxDelay: 100, multiplier: 2)
        #expect(policy.delay(forAttempt: 2) == 2)
    }

    @Test func delay_thirdAttempt_quadruplesBaseDelay() {
        let policy = RetryPolicy(baseDelay: 1, maxDelay: 100, multiplier: 2)
        #expect(policy.delay(forAttempt: 3) == 4)
    }

    @Test func delay_multiplier3_triplesEachAttempt() {
        let policy = RetryPolicy(baseDelay: 2, maxDelay: 1_000, multiplier: 3)
        #expect(policy.delay(forAttempt: 1) == 2)
        #expect(policy.delay(forAttempt: 2) == 6)
        #expect(policy.delay(forAttempt: 3) == 18)
    }

    // MARK: - Cap behaviour

    @Test func delay_cappedAtMaxDelay() {
        let policy = RetryPolicy(baseDelay: 1, maxDelay: 10, multiplier: 2)
        // 1 → 2 → 4 → 8 → 16 (capped to 10) → 32 (capped to 10)
        #expect(policy.delay(forAttempt: 5) == 10)
        #expect(policy.delay(forAttempt: 6) == 10)
        #expect(policy.delay(forAttempt: 100) == 10)
    }

    @Test func delay_attemptZero_clampedToOne() {
        let policy = RetryPolicy(baseDelay: 5, maxDelay: 100, multiplier: 2)
        #expect(policy.delay(forAttempt: 0) == 5)
        #expect(policy.delay(forAttempt: -1) == 5)
    }

    // MARK: - Jitter bounds

    @Test func delay_withJitter_stayWithinRange() {
        let policy = RetryPolicy(
            baseDelay: 10,
            maxDelay: 100,
            multiplier: 2,
            jitterRange: 0.8...1.2
        )
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<200 {
            let result = policy.delay(forAttempt: 1, using: &rng)
            #expect(result >= 8.0 && result <= 12.0)
        }
    }

    @Test func delay_jitterAppliedAfterCap() {
        // Cap at 10, jitter ±20% → result must land in [8, 12]
        let policy = RetryPolicy(
            baseDelay: 1,
            maxDelay: 10,
            multiplier: 2,
            jitterRange: 0.8...1.2
        )
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<200 {
            let result = policy.delay(forAttempt: 10, using: &rng)
            #expect(result >= 8.0 && result <= 12.0)
        }
    }

    @Test func delay_noJitter_returnsExactValue() {
        let policy = RetryPolicy(
            baseDelay: 60,
            maxDelay: 300,
            multiplier: 2,
            jitterRange: nil
        )
        #expect(policy.delay(forAttempt: 1) == 60)
        #expect(policy.delay(forAttempt: 2) == 120)
        #expect(policy.delay(forAttempt: 3) == 240)
        #expect(policy.delay(forAttempt: 4) == 300)
    }

    // MARK: - Retry-After header parsing

    @Test func retryAfterHeader_validSeconds_returnsDelay() {
        let policy = RetryPolicy.rateLimit
        #expect(policy.delay(retryAfterHeader: "5") == 5)
        #expect(policy.delay(retryAfterHeader: "0.5") == 0.5)
    }

    @Test func retryAfterHeader_cappedAtMaxDelay() {
        let policy = RetryPolicy(baseDelay: 1, maxDelay: 30, multiplier: 2)
        #expect(policy.delay(retryAfterHeader: "60") == 30)
        #expect(policy.delay(retryAfterHeader: "9999") == 30)
    }

    @Test func retryAfterHeader_invalidInputs_returnNil() {
        let policy = RetryPolicy.rateLimit
        #expect(policy.delay(retryAfterHeader: nil) == nil)
        #expect(policy.delay(retryAfterHeader: "") == nil)
        #expect(policy.delay(retryAfterHeader: "abc") == nil)
        #expect(policy.delay(retryAfterHeader: "0") == nil)
        #expect(policy.delay(retryAfterHeader: "-5") == nil)
    }

    @Test func retryAfterHeader_doesNotApplyJitter() {
        // Even when the policy has jitter for backoff, Retry-After is honored exactly.
        let policy = RetryPolicy(
            baseDelay: 1,
            maxDelay: 30,
            multiplier: 2,
            jitterRange: 0.8...1.2
        )
        #expect(policy.delay(retryAfterHeader: "5") == 5.0)
        #expect(policy.delay(retryAfterHeader: "5") == 5.0)
        #expect(policy.delay(retryAfterHeader: "5") == 5.0)
    }

    // MARK: - Presets

    @Test func preset_oauth_matchesHistoricalValues() {
        let policy = RetryPolicy.oauth
        #expect(policy.baseDelay == 1)
        #expect(policy.maxDelay == 30)
        #expect(policy.multiplier == 2)
        #expect(policy.jitterRange == 0.8...1.2)
        #expect(policy.maxAttempts == 2)
    }

    @Test func preset_statusCheck_matchesHistoricalValues() {
        let policy = RetryPolicy.statusCheck
        #expect(policy.baseDelay == 60)
        #expect(policy.maxDelay == 300)
        #expect(policy.multiplier == 2)
        #expect(policy.jitterRange == 0.8...1.2)
    }

    @Test func preset_fileWatch_hasNoJitterAndCapsRetries() {
        let policy = RetryPolicy.fileWatch
        #expect(policy.baseDelay == 60)
        #expect(policy.maxDelay == 300)
        #expect(policy.jitterRange == nil)
        #expect(policy.maxAttempts == 10)
    }

    @Test func preset_rateLimit_capsRetryAfterAt30s() {
        let policy = RetryPolicy.rateLimit
        #expect(policy.maxDelay == 30)
        #expect(policy.delay(retryAfterHeader: "100") == 30)
    }

    // MARK: - Regression: parity with old hand-rolled formulas

    @Test func parity_oauthHistoricalFormula() {
        // OAuthManager pre-refactor: base * Double.random(in: 0.8...1.2)
        // where base = 1 << (attempt - 1). For attempt 1,2,3 → 1s, 2s, 4s.
        let policy = RetryPolicy.oauth
        // Test without jitter to confirm the exponential ladder
        let unjittered = RetryPolicy(
            baseDelay: policy.baseDelay,
            maxDelay: policy.maxDelay,
            multiplier: policy.multiplier,
            jitterRange: nil
        )
        #expect(unjittered.delay(forAttempt: 1) == 1)
        #expect(unjittered.delay(forAttempt: 2) == 2)
        #expect(unjittered.delay(forAttempt: 3) == 4)
    }

    @Test func parity_statusCheckHistoricalFormula() {
        // StatusChecker pre-refactor: 60 * pow(2, failureCount - 1) capped at 300
        let policy = RetryPolicy.statusCheck
        let unjittered = RetryPolicy(
            baseDelay: policy.baseDelay,
            maxDelay: policy.maxDelay,
            multiplier: policy.multiplier,
            jitterRange: nil
        )
        #expect(unjittered.delay(forAttempt: 1) == 60)
        #expect(unjittered.delay(forAttempt: 2) == 120)
        #expect(unjittered.delay(forAttempt: 3) == 240)
        #expect(unjittered.delay(forAttempt: 4) == 300) // 480 capped to 300
    }

    @Test func parity_fileWatchHistoricalFormula() {
        // FileWatcher pre-refactor: 60 * pow(2, statsCacheRetryCount) capped at 300
        // where statsCacheRetryCount is 0-indexed. So 0→60, 1→120, 2→240, 3→480 cap 300.
        // RetryPolicy is 1-indexed: count+1 maps directly.
        let policy = RetryPolicy.fileWatch
        #expect(policy.delay(forAttempt: 1) == 60) // was count=0
        #expect(policy.delay(forAttempt: 2) == 120) // was count=1
        #expect(policy.delay(forAttempt: 3) == 240) // was count=2
        #expect(policy.delay(forAttempt: 4) == 300) // was count=3, 480 capped to 300
    }
}

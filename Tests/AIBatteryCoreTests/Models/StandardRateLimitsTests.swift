import Testing
import Foundation
@testable import AIBatteryCore

@Suite("StandardRateLimits")
struct StandardRateLimitsTests {
    @Test func parse_validHeaders_returnsLimits() {
        let headers: [AnyHashable: Any] = [
            "anthropic-ratelimit-requests-limit": "50",
            "anthropic-ratelimit-requests-remaining": "45",
            "anthropic-ratelimit-requests-reset": "2026-04-03T12:00:00Z",
            "anthropic-ratelimit-tokens-limit": "80000",
            "anthropic-ratelimit-tokens-remaining": "75000",
            "anthropic-ratelimit-tokens-reset": "2026-04-03T12:00:00Z",
        ]
        let result = StandardRateLimits.parse(headers: headers)
        #expect(result != nil)
        #expect(result?.requestsLimit == 50)
        #expect(result?.requestsRemaining == 45)
        #expect(result?.tokensLimit == 80_000)
        #expect(result?.tokensRemaining == 75_000)
        #expect(result?.requestsReset != nil)
    }

    @Test func parse_missingRequestHeaders_returnsTokensOnly() {
        let headers: [AnyHashable: Any] = [
            "anthropic-ratelimit-tokens-limit": "80000",
            "anthropic-ratelimit-tokens-remaining": "75000",
        ]
        let result = StandardRateLimits.parse(headers: headers)
        #expect(result != nil)
        #expect(result?.requestsLimit == 0)
        #expect(result?.tokensLimit == 80_000)
        #expect(result?.tokensRemaining == 75_000)
        // 0/0 means "this response reported no request limit", not "the request limit is
        // exhausted". `requestsPercent` already guarded on `limit > 0`; the exhausted flag
        // did not, so an API-key account showed "Limit reached" beside a 0% bar.
        #expect(result?.isRequestsExhausted == false)
        #expect(result?.requestsPercent == 0)
    }

    @Test func parse_caseInsensitive_works() {
        let headers: [AnyHashable: Any] = [
            "Anthropic-Ratelimit-Requests-Limit": "50",
            "Anthropic-Ratelimit-Requests-Remaining": "10",
        ]
        let result = StandardRateLimits.parse(headers: headers)
        #expect(result != nil)
        #expect(result?.requestsLimit == 50)
        #expect(result?.requestsRemaining == 10)
    }

    @Test func requestsPercent_calculatesCorrectly() {
        let limits = StandardRateLimits(
            requestsLimit: 50,
            requestsRemaining: 30,
            requestsReset: nil,
            tokensLimit: 80_000,
            tokensRemaining: 60_000,
            tokensReset: nil
        )
        #expect(limits.requestsPercent == 40.0) // 20/50 = 40%
        #expect(limits.tokensPercent == 25.0) // 20000/80000 = 25%
    }

    /// The menu bar for an API-key account follows the tighter of the two per-minute
    /// limits — a 16-token probe barely moves the token bar while requests can bind.
    @Test func peakPercent_isTheTighterLimit() {
        let limits = StandardRateLimits(
            requestsLimit: 10, requestsRemaining: 2, requestsReset: nil,
            tokensLimit: 100_000, tokensRemaining: 99_000, tokensReset: nil
        )
        #expect(limits.peakPercent == 80.0)
    }

    @Test func requestsPercent_zeroLimit_returnsZero() {
        let limits = StandardRateLimits(
            requestsLimit: 0,
            requestsRemaining: 0,
            requestsReset: nil,
            tokensLimit: 0,
            tokensRemaining: 0,
            tokensReset: nil
        )
        #expect(limits.requestsPercent == 0)
        #expect(limits.tokensPercent == 0)
    }

    @Test func isExhausted_atLimit_returnsTrue() {
        let limits = StandardRateLimits(
            requestsLimit: 50,
            requestsRemaining: 0,
            requestsReset: nil,
            tokensLimit: 80_000,
            tokensRemaining: 0,
            tokensReset: nil
        )
        #expect(limits.isRequestsExhausted)
        #expect(limits.isTokensExhausted)
    }

    @Test func isExhausted_withRemaining_returnsFalse() {
        let limits = StandardRateLimits(
            requestsLimit: 50,
            requestsRemaining: 25,
            requestsReset: nil,
            tokensLimit: 80_000,
            tokensRemaining: 40_000,
            tokensReset: nil
        )
        #expect(!limits.isRequestsExhausted)
        #expect(!limits.isTokensExhausted)
    }

    @Test func parse_noPairs_returnsNil() {
        let headers: [AnyHashable: Any] = [
            "content-type": "application/json",
        ]
        #expect(StandardRateLimits.parse(headers: headers) == nil)
    }

    @Test func parse_inputTokensFallback_works() {
        let headers: [AnyHashable: Any] = [
            "anthropic-ratelimit-input-tokens-limit": "100000",
            "anthropic-ratelimit-input-tokens-remaining": "85000",
            "anthropic-ratelimit-output-tokens-limit": "50000",
            "anthropic-ratelimit-output-tokens-remaining": "48000",
        ]
        let result = StandardRateLimits.parse(headers: headers)
        #expect(result != nil)
        #expect(result?.requestsLimit == 100_000)
        #expect(result?.requestsRemaining == 85_000)
        #expect(result?.tokensLimit == 50_000)
        #expect(result?.tokensRemaining == 48_000)
    }

    @Test func parse_unixTimestamp_parsesDate() {
        let headers: [AnyHashable: Any] = [
            "anthropic-ratelimit-requests-limit": "50",
            "anthropic-ratelimit-requests-remaining": "45",
            "anthropic-ratelimit-requests-reset": "1775390400",
        ]
        let result = StandardRateLimits.parse(headers: headers)
        #expect(result?.requestsReset != nil)
    }

    @Test func parse_missingTokenHeaders_defaultsToZero() {
        let headers: [AnyHashable: Any] = [
            "anthropic-ratelimit-requests-limit": "50",
            "anthropic-ratelimit-requests-remaining": "45",
        ]
        let result = StandardRateLimits.parse(headers: headers)
        #expect(result != nil)
        #expect(result?.tokensLimit == 0)
        #expect(result?.tokensRemaining == 0)
    }

    /// Per-minute limits expire in seconds. A cached `remaining: 0` served while the next
    /// probe is offline / backing off must not keep an API-key account at 100% past its
    /// own reset — each exhausted window restores to its full allowance independently.
    @Test func withClearedExpiredWindows_restoresOnlyTheWindowsWhoseResetPassed() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let limits = StandardRateLimits(
            requestsLimit: 500, requestsRemaining: 0, requestsReset: now.addingTimeInterval(-1),
            tokensLimit: 30_000, tokensRemaining: 0, tokensReset: now.addingTimeInterval(20)
        )
        #expect(limits.peakPercent == 100)

        let cleared = limits.withClearedExpiredWindows(now: now)
        #expect(cleared.requestsRemaining == 500)
        #expect(cleared.requestsReset == nil)
        #expect(cleared.requestsPercent == 0)
        #expect(cleared.tokensRemaining == 0) // not yet reset
        #expect(cleared.tokensReset == now.addingTimeInterval(20))
        #expect(cleared.peakPercent == 100)

        let later = cleared.withClearedExpiredWindows(now: now.addingTimeInterval(21))
        #expect(later.tokensRemaining == 30_000)
        #expect(later.peakPercent == 0)

        // No resets known → nothing to age out, same value back.
        let resetless = StandardRateLimits(requestsLimit: 5, requestsRemaining: 0, requestsReset: nil, tokensLimit: 5, tokensRemaining: 0, tokensReset: nil)
        #expect(resetless.withClearedExpiredWindows(now: now) == resetless)
    }
}

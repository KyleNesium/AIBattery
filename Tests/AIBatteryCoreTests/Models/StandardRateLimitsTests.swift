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
}

import Foundation
import Testing
@testable import AIBatteryCore

/// OpenAI API-key accounts have no ChatGPT windows — per-minute limits come from the
/// `x-ratelimit-*` response headers (names + "6m0s"/"1s" reset format per
/// developers.openai.com/api/docs/guides/rate-limits, read 2026-09-25).
@Suite("StandardRateLimits — OpenAI headers")
struct OpenAIRateLimitHeadersTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    @Test func parsesOpenAIHeaders() throws {
        let headers: [AnyHashable: Any] = [
            "x-ratelimit-limit-requests": "60",
            "x-ratelimit-remaining-requests": "59",
            "x-ratelimit-reset-requests": "1s",
            "x-ratelimit-limit-tokens": "150000",
            "x-ratelimit-remaining-tokens": "149984",
            "x-ratelimit-reset-tokens": "6m0s",
            "x-ratelimit-limit-project-tokens": "999", // ignored
        ]
        let limits = try #require(StandardRateLimits.parse(openAIHeaders: headers, now: now))
        #expect(limits.requestsLimit == 60)
        #expect(limits.requestsRemaining == 59)
        #expect(limits.tokensLimit == 150_000)
        #expect(limits.tokensRemaining == 149_984)
        #expect(limits.requestsReset == now.addingTimeInterval(1))
        #expect(limits.tokensReset == now.addingTimeInterval(360))
    }

    @Test func caseInsensitive_andTokensOnly() throws {
        let headers: [AnyHashable: Any] = [
            "X-RateLimit-Limit-Tokens": "1000",
            "X-RateLimit-Remaining-Tokens": "0",
        ]
        let limits = try #require(StandardRateLimits.parse(openAIHeaders: headers, now: now))
        #expect(limits.isTokensExhausted)
        #expect(limits.requestsLimit == 0)
    }

    @Test func noOpenAIHeaders_returnsNil() {
        #expect(StandardRateLimits.parse(openAIHeaders: ["content-type": "application/json"], now: now) == nil)
    }

    @Test func durationParsing() {
        #expect(StandardRateLimits.parseGoDuration("1s") == 1)
        #expect(StandardRateLimits.parseGoDuration("6m0s") == 360)
        #expect(StandardRateLimits.parseGoDuration("1h2m3.5s") == 3_723.5)
        #expect(StandardRateLimits.parseGoDuration("20ms") == 0.02)
        #expect(StandardRateLimits.parseGoDuration("") == nil)
        #expect(StandardRateLimits.parseGoDuration("soon") == nil)
    }
}

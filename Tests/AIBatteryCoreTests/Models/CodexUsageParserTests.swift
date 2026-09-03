import Foundation
import Testing
@testable import AIBatteryCore

@Suite("CodexUsageParser")
struct CodexUsageParserTests {
    // Shape verified against chatgpt.com/backend-api/wham/usage via CodexBar's decoder.
    private let whamBody = Data("""
    {"plan_type":"team",
     "rate_limit":{
       "primary_window":{"used_percent":21,"reset_at":1788267090,"limit_window_seconds":18000},
       "secondary_window":{"used_percent":63.5,"reset_at":1788853890,"limit_window_seconds":604800}}}
    """.utf8)

    @Test func parsesWhamUsage() throws {
        let usage = try #require(CodexUsageParser.parseUsageResponse(whamBody))
        #expect(usage.provider == .codex)
        #expect(abs(usage.fiveHourUtilization - 0.21) < 0.0001)
        #expect(abs(usage.sevenDayUtilization - 0.635) < 0.0001)
        #expect(usage.fiveHourReset == Date(timeIntervalSince1970: 1_788_267_090))
        #expect(usage.fiveHourWindowMinutes == 300)
        #expect(usage.sevenDayWindowMinutes == 10_080)
        #expect(usage.representativeClaim == RateLimitUsage.sevenDayWindow) // 63.5 > 21
        #expect(usage.overallStatus == "allowed")
        #expect(CodexUsageParser.planType(whamBody) == "team")
    }

    @Test func hundredPercentWindowIsThrottled() throws {
        let body = Data("""
        {"rate_limit":{"primary_window":{"used_percent":100,"reset_at":1788267090,"limit_window_seconds":18000},
                       "secondary_window":{"used_percent":10,"reset_at":1788853890,"limit_window_seconds":604800}}}
        """.utf8)
        let usage = try #require(CodexUsageParser.parseUsageResponse(body))
        #expect(usage.fiveHourStatus == "throttled")
        #expect(usage.overallStatus == "throttled")
        #expect(usage.sevenDayStatus == "allowed")
    }

    // Shape verified against a live ~/.codex/sessions token_count event (2026-09-01).
    @Test func parsesSessionSnapshot() throws {
        let rateLimits: [String: Any] = [
            "limit_id": "codex",
            "primary": ["used_percent": 21.0, "window_minutes": 300, "resets_at": 1_788_267_090],
            "secondary": ["used_percent": 3.0, "window_minutes": 10_080, "resets_at": 1_788_853_890],
            "plan_type": "team",
        ]
        let usage = try #require(CodexUsageParser.parseSessionRateLimits(rateLimits))
        #expect(usage.provider == .codex)
        #expect(abs(usage.fiveHourUtilization - 0.21) < 0.0001)
        #expect(usage.sevenDayWindowMinutes == 10_080)
        #expect(usage.representativeClaim == RateLimitUsage.fiveHourWindow)
    }

    @Test func missingWindowsReturnNil() {
        #expect(CodexUsageParser.parseUsageResponse(Data("{}".utf8)) == nil)
        #expect(CodexUsageParser.parseSessionRateLimits([:]) == nil)
    }
}

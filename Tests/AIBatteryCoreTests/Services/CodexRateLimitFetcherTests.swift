import Foundation
import Testing
@testable import AIBatteryCore

@Suite("CodexRateLimitFetcher")
@MainActor
struct CodexRateLimitFetcherTests {
    private let goodBody = Data("""
    {"plan_type":"plus","rate_limit":{
      "primary_window":{"used_percent":30,"reset_at":1788267090,"limit_window_seconds":18000},
      "secondary_window":{"used_percent":5,"reset_at":1788853890,"limit_window_seconds":604800}}}
    """.utf8)

    @Test func interpret200IsFreshCodexResult() {
        guard case .success(let result) = CodexRateLimitFetcher.interpretUsageResponse(statusCode: 200, data: goodBody) else {
            Issue.record("expected success"); return
        }
        #expect(result.rateLimits?.provider == .codex)
        #expect(result.rateLimitSource == .codexUsageEndpoint)
        #expect(result.isCached == false)
        #expect(abs((result.rateLimits?.fiveHourUtilization ?? 0) - 0.30) < 0.0001)
    }

    @Test func interpret429MarksThrottled() {
        guard case .success(let result) = CodexRateLimitFetcher.interpretUsageResponse(statusCode: 429, data: goodBody) else {
            Issue.record("expected success"); return
        }
        #expect(result.rateLimits?.overallStatus == "throttled")
    }

    @Test func interpretAuthAndServerFailures() {
        guard case .authFailed = CodexRateLimitFetcher.interpretUsageResponse(statusCode: 401, data: Data()) else {
            Issue.record("401 must be authFailed"); return
        }
        guard case .unavailable = CodexRateLimitFetcher.interpretUsageResponse(statusCode: 503, data: Data()) else {
            Issue.record("503 must be unavailable"); return
        }
        guard case .unavailable = CodexRateLimitFetcher.interpretUsageResponse(statusCode: 200, data: Data("junk".utf8)) else {
            Issue.record("unparseable 200 must be unavailable"); return
        }
    }
}

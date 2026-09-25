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

    // MARK: - overrideCachedRateLimits

    //
    // F1c: spike-hold write-back must land in the CODEX cache/persisted blob, not
    // RateLimitFetcher's — mirrors RateLimitFetcher.overrideCachedRateLimits /
    // RateLimitFetcher+Persistence.swift.

    private static func makeSuiteDefaults() throws -> (UserDefaults, String) {
        let suiteName = "codexOverrideTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        return (defaults, suiteName)
    }

    @Test func overrideCachedRateLimits_replacesCacheAndPersistedBlob() throws {
        let (defaults, suiteName) = try Self.makeSuiteDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let accountId = "codex-override-\(UUID().uuidString)"

        // A raw fetch cached+persisted a fresh-but-wrong ~100% (glitch) before the
        // ViewModel's spike filter could hold it — same shape as the Claude wake bug,
        // but under the Codex cache/persist key this time.
        let glitch = RateLimitUsage(
            representativeClaim: "seven_day",
            fiveHourUtilization: 0.05, fiveHourReset: Date().addingTimeInterval(3_600), fiveHourStatus: "allowed",
            sevenDayUtilization: 1.0, sevenDayReset: Date().addingTimeInterval(604_800), sevenDayStatus: "allowed",
            overallStatus: "allowed", provider: .codex, fiveHourWindowMinutes: 300, sevenDayWindowMinutes: 10_080
        )
        let raw = APIFetchResult(rateLimits: glitch, rateLimitSource: .codexUsageEndpoint, profile: nil)
        let fetcher = CodexRateLimitFetcher()
        fetcher.cachedResults[accountId] = raw
        fetcher.persistRateLimits(raw, accountId: accountId, defaults: defaults)

        // The spike filter held the window at the previous real value — write it back.
        let held = RateLimitUsage(
            representativeClaim: "seven_day",
            fiveHourUtilization: 0.05, fiveHourReset: Date().addingTimeInterval(3_600), fiveHourStatus: "allowed",
            sevenDayUtilization: 0.02, sevenDayReset: Date().addingTimeInterval(604_800), sevenDayStatus: "allowed",
            overallStatus: "allowed", provider: .codex, fiveHourWindowMinutes: 300, sevenDayWindowMinutes: 10_080
        )
        fetcher.overrideCachedRateLimits(held, accountId: accountId, defaults: defaults)

        // In-memory cache corrected — and non-rate-limit fields preserved.
        let cached = fetcher.cachedOrEmpty(accountId: accountId)
        #expect(cached.rateLimits?.sevenDayUtilization == 0.02)
        #expect(cached.rateLimitSource == .codexUsageEndpoint)

        // Persisted blob corrected too — a later launch restore must not resurrect the glitch.
        let restorer = CodexRateLimitFetcher()
        restorer.restorePersistedRateLimits(defaults: defaults)
        #expect(restorer.cachedOrEmpty(accountId: accountId).rateLimits?.sevenDayUtilization == 0.02)
    }

    @Test func overrideCachedRateLimits_noCachedEntry_noOp() throws {
        let (defaults, suiteName) = try Self.makeSuiteDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let accountId = "codex-override-missing-\(UUID().uuidString)"

        let held = RateLimitUsage(
            representativeClaim: "five_hour",
            fiveHourUtilization: 0.02, fiveHourReset: nil, fiveHourStatus: "allowed",
            sevenDayUtilization: 0.10, sevenDayReset: nil, sevenDayStatus: "allowed",
            overallStatus: "allowed", provider: .codex
        )
        let fetcher = CodexRateLimitFetcher()
        // No cached entry for this account — nothing to correct, must not create one.
        fetcher.overrideCachedRateLimits(held, accountId: accountId, defaults: defaults)
        #expect(fetcher.cachedOrEmpty(accountId: accountId).rateLimits == nil)
    }
}

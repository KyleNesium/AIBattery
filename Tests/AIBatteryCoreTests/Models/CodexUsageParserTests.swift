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
        let usage = try #require(CodexUsageParser.parseUsage(whamBody).rateLimits)
        #expect(usage.provider == .codex)
        #expect(abs(usage.fiveHourUtilization - 0.21) < 0.0001)
        #expect(abs(usage.sevenDayUtilization - 0.635) < 0.0001)
        #expect(usage.fiveHourReset == Date(timeIntervalSince1970: 1_788_267_090))
        #expect(usage.fiveHourWindowMinutes == 300)
        #expect(usage.sevenDayWindowMinutes == 10_080)
        #expect(usage.representativeClaim == RateLimitUsage.sevenDayWindow) // 63.5 > 21
        #expect(usage.overallStatus == "allowed")
        #expect(CodexUsageParser.parseUsage(whamBody).planType == "team")
    }

    /// 100% without `rate_limit_reached_type` is "at capacity", never a synthesized
    /// throttle — the same contract as the Claude parsers, so a wrong ~100% reading
    /// goes through the near-full confirmation hold instead of alarming instantly.
    @Test func hundredPercentWindowIsAtCapacityNotThrottled() throws {
        let body = Data("""
        {"rate_limit":{"primary_window":{"used_percent":100,"reset_at":1788267090,"limit_window_seconds":18000},
                       "secondary_window":{"used_percent":10,"reset_at":1788853890,"limit_window_seconds":604800}}}
        """.utf8)
        let usage = try #require(CodexUsageParser.parseUsage(body).rateLimits)
        #expect(usage.fiveHourUtilization == 1.0)
        #expect(usage.fiveHourStatus == "allowed")
        #expect(usage.overallStatus == "allowed")
        #expect(usage.sevenDayStatus == "allowed")
        #expect(!usage.isThrottled)
    }

    /// The explicit signal still throttles, at any utilization.
    @Test func reachedTypeThrottlesNamedWindow() throws {
        let body = Data("""
        {"rate_limit":{"primary_window":{"used_percent":100,"reset_at":1788267090,"limit_window_seconds":18000},
                       "secondary_window":{"used_percent":10,"reset_at":1788853890,"limit_window_seconds":604800}},
         "rate_limit_reached_type":"five_hour"}
        """.utf8)
        let usage = try #require(CodexUsageParser.parseUsage(body).rateLimits)
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
        #expect(CodexUsageParser.parseUsage(Data("{}".utf8)).rateLimits == nil)
        #expect(CodexUsageParser.parseSessionRateLimits([:]) == nil)
    }

    @Test func parseUsage_returnsLimitsAndPlanInOnePass() {
        let parsed = CodexUsageParser.parseUsage(whamBody)
        #expect(parsed.planType == "team")
        #expect(abs((parsed.rateLimits?.fiveHourUtilization ?? 0) - 0.21) < 0.0001)
        let empty = CodexUsageParser.parseUsage(Data("{}".utf8))
        #expect(empty.rateLimits == nil && empty.planType == nil)
    }

    // MARK: - Session-log fallback, spend-control plans

    /// The real shape written by Codex CLI 0.160.1 for a Business workspace: both windows
    /// null, and the budget carried FLAT (`individual_limit`, `spend_control_reached`)
    /// rather than nested under `spend_control` as `wham/usage` writes it. Before this was
    /// handled, `assemble` failed on both null windows and the whole fallback returned nil —
    /// so a Business account showed empty bars for the entire duration of an endpoint
    /// outage, which is the one situation the fallback exists for.
    @Test func sessionRateLimits_spendControlPlan_producesCreditBudget() throws {
        let json = """
        {"limit_id":"codex","limit_name":null,"primary":null,"secondary":null,
         "credits":{"has_credits":true,"unlimited":false,"balance":"31629.767277359962"},
         "individual_limit":{"limit":"32768","used":"27852.8","unit":"credit"},
         "spend_control_reached":false,
         "plan_type":"business","rate_limit_reached_type":null}
        """
        let dict = try #require(
            try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        )
        let usage = try #require(CodexUsageParser.parseSessionRateLimits(dict))
        let budget = try #require(usage.creditBudget)

        #expect(budget.limit == 32_768)
        #expect(budget.planType == "business")
        #expect(budget.balance == 31_629.767277359962)
        #expect(!budget.isUncapped)
        // 27852.8 / 32768 = 85%, mirrored onto both windows.
        #expect(abs(budget.usedPercent - 85.0) < 0.01)
        #expect(abs(usage.fiveHourUtilization - 0.85) < 0.001)
        #expect(abs(usage.sevenDayUtilization - 0.85) < 0.001)
        #expect(!usage.isThrottled)
    }

    /// A workspace with no individual cap is healthy and unmetered, not an outage.
    @Test func sessionRateLimits_spendControlWithoutCap_readsUncapped() throws {
        let json = """
        {"primary":null,"secondary":null,
         "credits":{"has_credits":true,"unlimited":true,"balance":null},
         "individual_limit":null,"spend_control_reached":null,
         "plan_type":"enterprise","rate_limit_reached_type":null}
        """
        let dict = try #require(
            try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        )
        let usage = try #require(CodexUsageParser.parseSessionRateLimits(dict))
        let budget = try #require(usage.creditBudget)
        #expect(budget.isUncapped)
        #expect(budget.planType == "enterprise")
        #expect(!usage.isThrottled)
    }

    /// Windowed plans must keep taking the window path untouched, and a genuinely empty
    /// object must still read as "no data" rather than a fabricated uncapped budget.
    @Test func sessionRateLimits_windowedPlanAndEmptyObjectAreUnchanged() throws {
        let windowed = """
        {"primary":{"used_percent":42,"reset_at":4102444800},
         "secondary":{"used_percent":10,"reset_at":4102444800},
         "rate_limit_reached_type":null}
        """
        let dict = try #require(
            try JSONSerialization.jsonObject(with: Data(windowed.utf8)) as? [String: Any]
        )
        let usage = try #require(CodexUsageParser.parseSessionRateLimits(dict))
        #expect(usage.creditBudget == nil)
        #expect(abs(usage.fiveHourUtilization - 0.42) < 0.001)

        #expect(CodexUsageParser.parseSessionRateLimits([:]) == nil)
        #expect(CodexUsageParser.parseSessionRateLimits(["primary": NSNull(), "secondary": NSNull()]) == nil)
    }

    /// A subscription plan's rollout carries `plan_type` with both windows null — routine
    /// early in a session, before the server attaches window info. Treating `plan_type`
    /// alone as spend-control evidence fabricated an "uncapped, 0% used" credit budget for
    /// Plus/Pro accounts, which flips the popover to a single "no cap" Credits bar and
    /// hides the real 5h/weekly windows — asserting a false healthy 0% during exactly the
    /// outage this fallback exists to cover. Must be "no data" instead.
    @Test func sessionRateLimits_windowedPlanWithNullWindows_isNoDataNotABudget() throws {
        for plan in ["free", "plus", "pro", "team"] {
            let json = """
            {"limit_id":"codex","limit_name":null,"primary":null,"secondary":null,
             "plan_type":"\(plan)","rate_limit_reached_type":null}
            """
            let dict = try #require(
                try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
            )
            #expect(CodexUsageParser.parseSessionRateLimits(dict) == nil, "\(plan) must not fabricate a budget")
        }
    }

    /// A windowed shape whose windows are present but unparseable is also "no data" —
    /// never a budget. Mirrors the guard `parseUsageDict` applies to `rate_limit`.
    @Test func sessionRateLimits_unparseableWindows_areNotABudget() throws {
        let json = """
        {"primary":{"nonsense":true},"secondary":{"nonsense":true},
         "plan_type":"pro","credits":{"has_credits":true,"balance":"100"}}
        """
        let dict = try #require(
            try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        )
        #expect(CodexUsageParser.parseSessionRateLimits(dict) == nil)
    }

    @Test func parseCreditBudget_readsLimitName() throws {
        let dict: [String: Any] = [
            "plan_type": "business",
            "limit_name": "Engineering monthly cap",
            "spend_control": ["individual_limit": ["limit": 100, "used": 25, "remaining": 75, "used_percent": 25, "unit": "credit"], "reached": false],
        ]
        let budget = try #require(CodexUsageParser.parseCreditBudget(dict))
        #expect(budget.limitName == "Engineering monthly cap")
    }
}

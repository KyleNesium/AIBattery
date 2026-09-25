import Foundation
import Testing
@testable import AIBatteryCore

/// Business / Enterprise Codex plans report no 5h/weekly windows at all — the budget
/// lives in `spend_control.individual_limit` (credits). Payload shape captured live from
/// `chatgpt.com/backend-api/wham/usage` on 2026-09-25 (identity fields redacted).
@Suite("CodexCreditBudget")
struct CodexCreditBudgetTests {
    private let businessBody = Data("""
    {"plan_type":"business","rate_limit":null,"code_review_rate_limit":null,"additional_rate_limits":null,
     "model_usage":{"gpt-6-astra":{"available":true,"available_at":null,"credits_would_enable":false}},
     "credits":{"has_credits":true,"unlimited":false,"overage_limit_reached":false,"balance":null},
     "spend_control":{"reached":false,"individual_limit":{"source":"group_based_spend_controls","unit":"credit",
       "limit":"32768","used":"7006.296069383621","remaining":"25761.70393061638","used_percent":21,
       "remaining_percent":79,"reset_after_seconds":484869,"reset_at":1790812800}},
     "rate_limit_reached_type":null}
    """.utf8)

    @Test func parsesSpendControlBudgetIntoSingleWindowUsage() throws {
        let usage = try #require(CodexUsageParser.parseUsageResponse(businessBody))
        let budget = try #require(usage.creditBudget)
        #expect(usage.provider == .codex)
        #expect(usage.isCreditBudget)
        #expect(abs(budget.used - 7_006.296) < 0.01)
        #expect(budget.limit == 32_768)
        #expect(abs(budget.remaining - 25_761.70) < 0.01)
        #expect(budget.usedPercent == 21)
        #expect(budget.unit == "credit")
        #expect(budget.resetsAt == Date(timeIntervalSince1970: 1_790_812_800))
        #expect(budget.reached == false)
        #expect(budget.hasCredits)
        #expect(!budget.unlimited)
        #expect(budget.planType == "business")
        // Both windows mirror the budget so every metric mode / menu-bar path shows the credit %.
        #expect(abs(usage.fiveHourUtilization - 0.21) < 0.0001)
        #expect(abs(usage.sevenDayUtilization - 0.21) < 0.0001)
        #expect(usage.fiveHourReset == budget.resetsAt)
        #expect(usage.sevenDayReset == budget.resetsAt)
        #expect(usage.overallStatus == "allowed")
    }

    @Test func spendControlReached_isThrottled() throws {
        let body = try Data(#require(String(data: businessBody, encoding: .utf8)?
                .replacingOccurrences(of: "\"reached\":false", with: "\"reached\":true")
                .replacingOccurrences(of: "\"used_percent\":21", with: "\"used_percent\":100").utf8))
        let usage = try #require(CodexUsageParser.parseUsageResponse(body))
        #expect(usage.isThrottled)
        #expect(usage.creditBudget?.reached == true)
    }

    @Test func creditsDepletedReachedType_isThrottled() throws {
        let body = try Data(#require(String(data: businessBody, encoding: .utf8)?
                .replacingOccurrences(of: "\"rate_limit_reached_type\":null", with: "\"rate_limit_reached_type\":\"workspace_owner_credits_depleted\"").utf8))
        let usage = try #require(CodexUsageParser.parseUsageResponse(body))
        #expect(usage.isThrottled)
    }

    @Test func noWindowsNoSpendControl_returnsNil() {
        #expect(CodexUsageParser.parseUsageResponse(Data(#"{"plan_type":"business","rate_limit":null,"credits":{"has_credits":true}}"#.utf8)) == nil)
    }

    @Test func windowedPlan_hasNoCreditBudget() throws {
        let body = Data(#"{"plan_type":"plus","rate_limit":{"primary_window":{"used_percent":21,"reset_at":1788267090,"limit_window_seconds":18000},"secondary_window":{"used_percent":63.5,"reset_at":1788853890,"limit_window_seconds":604800}}}"#.utf8)
        let usage = try #require(CodexUsageParser.parseUsageResponse(body))
        #expect(usage.creditBudget == nil)
        #expect(!usage.isCreditBudget)
    }

    @Test func interpretUsageResponse_treatsCreditsBodyAsSuccess() {
        // A 200 with a credits-only body is a valid answer, not an outage — it must never
        // trigger endpoint backoff or the session-log fallback.
        guard case .success(let result) = CodexRateLimitFetcher.interpretUsageResponse(statusCode: 200, data: businessBody) else {
            Issue.record("credits body must be .success"); return
        }
        #expect(result.rateLimits?.isCreditBudget == true)
        #expect(result.rateLimitSource == .codexUsageEndpoint)
    }

    @Test func creditBudget_survivesCopiesAndPersistence() throws {
        let usage = try #require(CodexUsageParser.parseUsageResponse(businessBody))
        #expect(usage.markedThrottled().creditBudget == usage.creditBudget)
        #expect(usage.withClearedExpiredWindows(now: Date(timeIntervalSince1970: 1_790_000_000)).creditBudget == usage.creditBudget)
        #expect(usage.withClearedRolloverArtifacts(now: Date(timeIntervalSince1970: 1_790_000_000)).creditBudget == usage.creditBudget)
        let data = try JSONEncoder().encode(usage)
        let decoded = try JSONDecoder().decode(RateLimitUsage.self, from: data)
        #expect(decoded.creditBudget == usage.creditBudget)
        #expect(decoded.isCreditBudget)
    }

    @Test func creditBudget_vocabulary() throws {
        let usage = try #require(CodexUsageParser.parseUsageResponse(businessBody))
        #expect(usage.bindingWindowLabel == "Credits")
        #expect(usage.bindingWindowShortCode == "CR")
        #expect(usage.sevenDayDisplayLabel == "Credits")
        #expect(NotificationManager.windowLabels(for: usage) == ("Credits", "Credits"))
    }

    @Test func spikeFilter_preservesCreditBudget() throws {
        let fresh = try #require(CodexUsageParser.parseUsageResponse(businessBody))
        let result = UsageViewModel.spikeConfirmedRateLimits(fresh: fresh, previousDisplayed: nil, previouslyNearFull: [:])
        #expect(result.display.creditBudget == fresh.creditBudget)
    }

    @Test func compactCredits_formatting() {
        #expect(CodexCreditBudget.formatCredits(7_006.3) == "7.0K")
        #expect(CodexCreditBudget.formatCredits(32_768) == "32.8K")
        #expect(CodexCreditBudget.formatCredits(950) == "950")
        #expect(CodexCreditBudget.formatCredits(1_260_000) == "1.3M")
    }

    // MARK: - Subscription plans with purchased credits

    @Test func windowedPlanWithCreditsBalance_exposesBalanceNotBudget() throws {
        let body = Data("""
        {"plan_type":"plus","rate_limit":{"primary_window":{"used_percent":21,"reset_at":1788267090,"limit_window_seconds":18000},
          "secondary_window":{"used_percent":63.5,"reset_at":1788853890,"limit_window_seconds":604800}},
         "credits":{"has_credits":true,"unlimited":false,"balance":"3944.1197930574417"}}
        """.utf8)
        let usage = try #require(CodexUsageParser.parseUsageResponse(body))
        #expect(!usage.isCreditBudget) // windows still drive the bars
        #expect(abs((usage.creditBalance ?? 0) - 3_944.12) < 0.01)
        #expect(usage.creditBudget?.planType == "plus")
        #expect(usage.sevenDayDisplayLabel == "Weekly")
    }

    @Test func planType_surfacesOnFetchResult() {
        let body = Data(#"{"plan_type":"pro","rate_limit":{"primary_window":{"used_percent":1,"reset_at":1788267090,"limit_window_seconds":18000}}}"#.utf8)
        guard case .success(let result) = CodexRateLimitFetcher.interpretUsageResponse(statusCode: 200, data: body) else {
            Issue.record("expected success"); return
        }
        #expect(result.planType == "pro")
    }
}

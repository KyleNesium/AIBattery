import Testing
@testable import AIBatteryCore

@Suite("MetricMode")
struct MetricModeTests {
    // MARK: - Raw values

    @Test func rawValues() {
        #expect(MetricMode.fiveHour.rawValue == "5h")
        #expect(MetricMode.sevenDay.rawValue == "7d")
        #expect(MetricMode.contextHealth.rawValue == "context")
    }

    // MARK: - Init from raw value

    @Test func initFromValidRaw() {
        #expect(MetricMode(rawValue: "5h") == .fiveHour)
        #expect(MetricMode(rawValue: "7d") == .sevenDay)
        #expect(MetricMode(rawValue: "context") == .contextHealth)
    }

    @Test func initFromInvalidRaw() {
        #expect(MetricMode(rawValue: "invalid") == nil)
        #expect(MetricMode(rawValue: "") == nil)
    }

    // MARK: - Labels

    @Test func labels() {
        #expect(MetricMode.fiveHour.label == "5-Hour")
        #expect(MetricMode.sevenDay.label == "7-Day")
        #expect(MetricMode.contextHealth.label == "Context")
    }

    // MARK: - Short labels

    @Test func shortLabels() {
        #expect(MetricMode.fiveHour.shortLabel == "5 Hour")
        #expect(MetricMode.sevenDay.shortLabel == "7 Day")
        #expect(MetricMode.contextHealth.shortLabel == "Context")
    }

    // MARK: - CaseIterable

    @Test func allCases() {
        #expect(MetricMode.allCases.count == 3)
        #expect(MetricMode.allCases.contains(.fiveHour))
        #expect(MetricMode.allCases.contains(.sevenDay))
        #expect(MetricMode.allCases.contains(.contextHealth))
    }

    // MARK: - Provider-aware labels (Codex-native popover)

    @Test func shortLabel_codexWindowedPlan_saysWeekly() {
        #expect(MetricMode.sevenDay.shortLabel(provider: .codex, kind: .windows) == "Weekly")
        #expect(MetricMode.fiveHour.shortLabel(provider: .codex, kind: .windows) == "5 Hour")
        #expect(MetricMode.sevenDay.shortLabel(provider: .claude, kind: .windows) == "7 Day")
    }

    @Test func shortLabel_codexCreditBudget_collapsesToCredits() {
        #expect(MetricMode.fiveHour.shortLabel(provider: .codex, kind: .credits) == "Credits")
        #expect(MetricMode.sevenDay.shortLabel(provider: .codex, kind: .credits) == "Credits")
        #expect(MetricMode.contextHealth.shortLabel(provider: .codex, kind: .credits) == "Context")
    }

    @Test func shortLabel_codexAPIKey_collapsesToAPILimits() {
        #expect(MetricMode.fiveHour.shortLabel(provider: .codex, kind: .apiLimits) == "API Limits")
        #expect(MetricMode.sevenDay.shortLabel(provider: .codex, kind: .apiLimits) == "API Limits")
    }

    @Test func pickerModes_singleBudgetKinds_hideRedundantWindowTab() {
        #expect(MetricMode.pickerModes(provider: .codex, kind: .credits) == [.fiveHour, .contextHealth])
        #expect(MetricMode.pickerModes(provider: .codex, kind: .apiLimits) == [.fiveHour, .contextHealth])
        #expect(MetricMode.pickerModes(provider: .codex, kind: .windows) == MetricMode.allCases)
        #expect(MetricMode.pickerModes(provider: .claude, kind: .windows) == MetricMode.allCases)
    }

    @Test func displayKind_derivation() {
        #expect(CodexDisplayKind.of(rateLimits: nil, standardLimits: nil, apiKeyAccount: false) == .windows)
        #expect(CodexDisplayKind.of(rateLimits: nil, standardLimits: nil, apiKeyAccount: true) == .apiLimits)
        let std = StandardRateLimits(requestsLimit: 1, requestsRemaining: 1, requestsReset: nil, tokensLimit: 1, tokensRemaining: 1, tokensReset: nil)
        #expect(CodexDisplayKind.of(rateLimits: nil, standardLimits: std, apiKeyAccount: false) == .apiLimits)
    }
}

import Testing
@testable import AIBatteryCore

@Suite("LocalEstimateSection — provider labels")
struct LocalEstimateSectionLabelTests {
    @Test func fiveHour_isSameForBothProviders() {
        #expect(LocalEstimateSection.windowLabel(.fiveHour, provider: .claude) == "5-Hour")
        #expect(LocalEstimateSection.windowLabel(.fiveHour, provider: .codex) == "5-Hour")
    }

    @Test func secondaryWindow_followsProviderVocabulary() {
        #expect(LocalEstimateSection.windowLabel(.sevenDay, provider: .claude) == "7-Day")
        #expect(LocalEstimateSection.windowLabel(.sevenDay, provider: .codex) == "Weekly")
    }
}

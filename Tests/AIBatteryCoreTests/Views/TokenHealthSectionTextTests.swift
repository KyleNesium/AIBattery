import Testing
@testable import AIBatteryCore

@Suite("TokenHealthSection text")
struct TokenHealthSectionTextTests {
    @Test func codexRow_showsEffortAndReasoning() {
        let text = TokenHealthSection.detailTrailingText(
            turnCount: 12, model: "gpt-6-astra", effort: "xhigh", reasoningShare: 0.29, reasoningTokens: 36_226
        )
        #expect(text == "12 turns · GPT-6 Astra · xhigh · 29% reasoning")
    }

    @Test func claudeRow_showsThinkingAndFast() {
        let text = TokenHealthSection.detailTrailingText(
            turnCount: 3, model: "claude-opus-5", effort: "fast", reasoningShare: 0.615, reasoningTokens: 139
        )
        #expect(text.hasSuffix("· fast · 62% thinking"))
    }

    @Test func noExtras_matchesLegacyFormat() {
        let text = TokenHealthSection.detailTrailingText(
            turnCount: 3, model: "claude-opus-5", effort: nil, reasoningShare: nil, reasoningTokens: 0
        )
        #expect(text == "3 turns · \(ModelNameMapper.displayName(for: "claude-opus-5"))")
    }

    @Test func zeroReasoning_hidesShare() {
        let text = TokenHealthSection.detailTrailingText(
            turnCount: 1, model: "gpt-6-astra", effort: nil, reasoningShare: 0, reasoningTokens: 0
        )
        #expect(!text.contains("reasoning"))
    }
}

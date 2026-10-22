import Testing
@testable import AIBatteryCore

@Suite("ReasoningVocabulary")
struct ReasoningVocabularyTests {
    @Test func claudeModels_sayThinking() {
        #expect(ReasoningVocabulary.label(forModel: "claude-opus-5") == "thinking")
    }

    @Test func gptModels_sayReasoning() {
        #expect(ReasoningVocabulary.label(forModel: "gpt-6-astra") == "reasoning")
    }

    @Test func unknownModels_sayReasoning() {
        #expect(ReasoningVocabulary.label(forModel: "") == "reasoning")
    }
}

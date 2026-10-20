import Foundation

/// Provider vocabulary for the output-token subset spent before answering:
/// Anthropic calls it thinking, OpenAI calls it reasoning.
enum ReasoningVocabulary {
    nonisolated static func label(forModel model: String) -> String {
        model.hasPrefix("claude-") ? "thinking" : "reasoning"
    }
}

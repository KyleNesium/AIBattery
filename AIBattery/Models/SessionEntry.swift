import Foundation

struct SessionEntry: Codable {
    let type: String?
    let timestamp: String?
    let sessionId: String?
    let message: SessionMessage?
    let uuid: String?
    let cwd: String?
    let gitBranch: String?

    struct SessionMessage: Codable {
        let role: String?
        let model: String?
        let usage: TokenUsage?
        let id: String? // message ID for deduplication
        let content: [ContentBlock]?
    }

    struct ContentBlock: Codable {
        let type: String?
    }

    struct TokenUsage: Codable {
        let inputTokens: Int?
        let outputTokens: Int?
        let cacheCreationInputTokens: Int?
        let cacheReadInputTokens: Int?
        let serviceTier: String?
        /// `"standard"` or `"fast"` (Claude fast mode). Absent on older logs.
        let speed: String?
        /// `output_tokens_details.thinking_tokens` — a subset of `output_tokens`.
        let outputTokensDetails: OutputTokensDetails?

        struct OutputTokensDetails: Codable {
            let thinkingTokens: Int?

            private enum CodingKeys: String, CodingKey {
                case thinkingTokens = "thinking_tokens"
            }
        }

        private enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
            case cacheCreationInputTokens = "cache_creation_input_tokens"
            case cacheReadInputTokens = "cache_read_input_tokens"
            case serviceTier = "service_tier"
            case speed
            case outputTokensDetails = "output_tokens_details"
        }
    }
}

struct AssistantUsageEntry {
    let timestamp: Date
    let model: String
    let messageId: String
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let cacheWriteTokens: Int
    let sessionId: String
    let cwd: String?
    let gitBranch: String?
    let toolCallCount: Int
    /// Context window the provider reported for this turn (Codex `model_context_window`).
    /// nil → fall back to `TokenHealthConfig.contextWindow(for:)`.
    var contextWindow: Int? = nil
    /// Thinking (Claude) / reasoning (Codex) tokens — a SUBSET of `outputTokens`,
    /// never added to any total.
    var reasoningTokens: Int = 0
    /// Codex `turn_context.effort` (e.g. "xhigh") or Claude `usage.speed` when not
    /// "standard" (e.g. "fast"). nil when the provider reports nothing notable.
    var effortLabel: String? = nil
    /// Codex `session_meta.payload.creator_account_id` — nil for Claude and for
    /// Codex session_meta lines that omit or blank the field.
    var creatorAccountId: String? = nil
}

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
    }

    struct TokenUsage: Codable {
        let inputTokens: Int?
        let outputTokens: Int?
        let cacheCreationInputTokens: Int?
        let cacheReadInputTokens: Int?

        private enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
            case cacheCreationInputTokens = "cache_creation_input_tokens"
            case cacheReadInputTokens = "cache_read_input_tokens"
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
}

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
        let input_tokens: Int?
        let output_tokens: Int?
        let cache_creation_input_tokens: Int?
        let cache_read_input_tokens: Int?
        let service_tier: String?
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

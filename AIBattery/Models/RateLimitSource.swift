import Foundation

/// Describes where the app's displayed rate-limit values came from.
enum RateLimitSource: String, Equatable, Codable {
    case oauthUsageEndpoint
    case claudeCodeClientData
    case anthropicAPIHeaders
    case codexUsageEndpoint
    case codexSessionLog

    var shortLabel: String {
        switch self {
        case .oauthUsageEndpoint:
            "Via Anthropic API"
        case .claudeCodeClientData:
            "Via Claude Code"
        case .anthropicAPIHeaders:
            "Via Anthropic API"
        case .codexUsageEndpoint:
            "Via OpenAI API"
        case .codexSessionLog:
            "Via Codex CLI"
        }
    }

    var explanation: String {
        switch self {
        case .oauthUsageEndpoint:
            "Usage data from Anthropic OAuth usage endpoint."
        case .claudeCodeClientData:
            "Usage data from Claude Code account metadata."
        case .anthropicAPIHeaders:
            "Usage data from Anthropic API response headers."
        case .codexUsageEndpoint:
            "Usage data from OpenAI's ChatGPT usage endpoint."
        case .codexSessionLog:
            "Usage data from the newest Codex CLI session log on this Mac (endpoint unreachable)."
        }
    }
}

import Foundation

/// Describes where the app's displayed rate-limit values came from.
enum RateLimitSource: String, Equatable, Codable {
    case oauthUsageEndpoint
    case claudeCodeClientData
    case anthropicAPIHeaders

    var shortLabel: String {
        switch self {
        case .oauthUsageEndpoint:
            return "Via Anthropic API"
        case .claudeCodeClientData:
            return "Via Claude Code"
        case .anthropicAPIHeaders:
            return "Via Anthropic API"
        }
    }

    var explanation: String {
        switch self {
        case .oauthUsageEndpoint:
            return "Usage data from Anthropic OAuth usage endpoint."
        case .claudeCodeClientData:
            return "Usage data from Claude Code account metadata."
        case .anthropicAPIHeaders:
            return "Usage data from Anthropic API response headers."
        }
    }
}

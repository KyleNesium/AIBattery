import Foundation

/// Describes where the app's displayed rate-limit values came from.
enum RateLimitSource: String, Equatable, Codable {
    case oauthUsageEndpoint
    case claudeCodeClientData
    case anthropicAPIHeaders

    var shortLabel: String {
        switch self {
        case .oauthUsageEndpoint:
            "Via Anthropic API"
        case .claudeCodeClientData:
            "Via Claude Code"
        case .anthropicAPIHeaders:
            "Via Anthropic API"
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
        }
    }
}

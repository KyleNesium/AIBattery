import Foundation

/// Describes where the app's displayed rate-limit values came from.
enum RateLimitSource: String, Equatable, Codable {
    case claudeCodeClientData
    case anthropicAPIHeaders

    var shortLabel: String {
        switch self {
        case .claudeCodeClientData:
            return "Claude Code usage"
        case .anthropicAPIHeaders:
            return "Public API headers"
        }
    }

    var explanation: String {
        switch self {
        case .claudeCodeClientData:
            return "These values come from Claude Code account metadata and reflect the 5-hour and 7-day usage windows shown in Claude Code."
        case .anthropicAPIHeaders:
            return "These values come from public Anthropic API headers. They may not match Claude Code's 5-hour and 7-day usage windows."
        }
    }
}

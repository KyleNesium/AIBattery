import Foundation

/// Describes where the app's displayed rate-limit values came from.
enum RateLimitSource: String, Equatable, Codable {
    case anthropicAPIHeaders

    var shortLabel: String {
        switch self {
        case .anthropicAPIHeaders:
            return "API headers; may differ from /usage"
        }
    }

    var explanation: String {
        switch self {
        case .anthropicAPIHeaders:
            return "These values come from Anthropic API sliding-window headers and may differ from Claude Code /usage."
        }
    }
}

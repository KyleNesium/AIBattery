import Foundation

/// Which AI service an account belongs to. Drives auth routing, rate-limit
/// fetching, window labels, and UI glyphs. Exactly two providers by design
/// (spec: no plugin registry).
public enum AIProvider: String, Codable, CaseIterable, Sendable {
    case claude
    case codex

    public var displayName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        }
    }

    /// Menu-bar / picker glyph. Text characters (not SF Symbols) so they can be
    /// baked into the status-item string alongside percentages.
    public var glyph: String {
        switch self {
        case .claude: "\u{2726}" // ✦
        case .codex: "\u{2B21}" // ⬡
        }
    }

    /// Label for the long window: Anthropic calls it 7-day; OpenAI calls it weekly
    /// (it is 7 days for both — 10080 minutes in Codex payloads).
    var secondaryWindowLabel: String {
        switch self {
        case .claude: "7-Day"
        case .codex: "Weekly"
        }
    }

    /// Compact menu-bar code for the long window ("waiting on 7D/WK").
    var secondaryWindowShortCode: String {
        switch self {
        case .claude: "7D"
        case .codex: "WK"
        }
    }
}

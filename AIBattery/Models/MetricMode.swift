/// Which metric drives the menu bar icon percentage and color.
enum MetricMode: String, CaseIterable {
    case fiveHour = "5h"
    case sevenDay = "7d"
    case contextHealth = "context"

    var label: String {
        switch self {
        case .fiveHour: "5-Hour"
        case .sevenDay: "7-Day"
        case .contextHealth: "Context"
        }
    }

    /// Label for the 3-segment picker.
    var shortLabel: String {
        switch self {
        case .fiveHour: "5 Hour"
        case .sevenDay: "7 Day"
        case .contextHealth: "Context"
        }
    }

    /// Picker label in the active provider's vocabulary. A Codex credit budget or
    /// API-key account has no separate windows, so both rate-limit modes share one label.
    func shortLabel(provider: AIProvider, kind: CodexDisplayKind) -> String {
        switch self {
        case .fiveHour, .sevenDay:
            switch kind {
            case .credits: "Credits"
            case .apiLimits: "API Limits"
            case .windows: self == .fiveHour ? "5 Hour" : (provider == .codex ? "Weekly" : "7 Day")
            }
        case .contextHealth: "Context"
        }
    }

    /// Tabs to show in the picker. Single-budget kinds collapse 5h/Weekly into one tab
    /// (the `.fiveHour` slot) so there is no redundant second tab.
    static func pickerModes(provider: AIProvider, kind: CodexDisplayKind) -> [MetricMode] {
        kind == .windows ? allCases : [.fiveHour, .contextHealth]
    }

    /// Returns all modes ordered with `current` first, remaining in `allCases` order.
    static func orderedModes(current: MetricMode) -> [MetricMode] {
        [current] + allCases.filter { $0 != current }
    }
}

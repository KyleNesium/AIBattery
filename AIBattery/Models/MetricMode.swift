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

    /// Picker label in the active provider's vocabulary. A Codex credit budget has no
    /// separate windows, so both rate-limit modes read "Credits".
    func shortLabel(provider: AIProvider, creditBudget: Bool) -> String {
        switch self {
        case .fiveHour: creditBudget ? "Credits" : "5 Hour"
        case .sevenDay: creditBudget ? "Credits" : (provider == .codex ? "Weekly" : "7 Day")
        case .contextHealth: "Context"
        }
    }

    /// Tabs to show in the picker. A credit budget collapses 5h/Weekly into one
    /// "Credits" tab (the `.fiveHour` slot) so there is no redundant second tab.
    static func pickerModes(provider: AIProvider, creditBudget: Bool) -> [MetricMode] {
        creditBudget ? [.fiveHour, .contextHealth] : allCases
    }

    /// Returns all modes ordered with `current` first, remaining in `allCases` order.
    static func orderedModes(current: MetricMode) -> [MetricMode] {
        [current] + allCases.filter { $0 != current }
    }
}

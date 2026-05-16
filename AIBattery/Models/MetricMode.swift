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

    /// Returns all modes ordered with `current` first, remaining in `allCases` order.
    static func orderedModes(current: MetricMode) -> [MetricMode] {
        [current] + allCases.filter { $0 != current }
    }
}

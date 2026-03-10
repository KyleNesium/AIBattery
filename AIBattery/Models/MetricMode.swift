/// Which metric drives the menu bar icon percentage and color.
enum MetricMode: String, CaseIterable {
    case fiveHour = "5h"
    case sevenDay = "7d"
    case contextHealth = "context"

    var label: String {
        switch self {
        case .fiveHour: return "5-Hour"
        case .sevenDay: return "7-Day"
        case .contextHealth: return "Context"
        }
    }

    /// Label for the 3-segment picker.
    var shortLabel: String {
        switch self {
        case .fiveHour: return "5 Hour"
        case .sevenDay: return "7 Day"
        case .contextHealth: return "Context"
        }
    }
}

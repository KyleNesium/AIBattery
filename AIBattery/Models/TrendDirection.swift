/// Usage trend direction (this week vs last week).
enum TrendDirection {
    case up, down, flat

    var symbol: String {
        switch self {
        case .up: "\u{2191}" // ↑
        case .down: "\u{2193}" // ↓
        case .flat: "\u{2192}" // →
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .up: "increasing"
        case .down: "decreasing"
        case .flat: "stable"
        }
    }
}

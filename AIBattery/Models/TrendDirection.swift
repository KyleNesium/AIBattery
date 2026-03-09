/// Usage trend direction (this week vs last week).
enum TrendDirection {
    case up, down, flat

    var symbol: String {
        switch self {
        case .up: return "\u{2191}"    // ↑
        case .down: return "\u{2193}"  // ↓
        case .flat: return "\u{2192}"  // →
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .up: return "increasing"
        case .down: return "decreasing"
        case .flat: return "stable"
        }
    }
}

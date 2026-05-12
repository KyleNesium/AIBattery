import Foundation

enum TokenFormatter {
    static func format(_ count: Int) -> String {
        guard count >= 0 else { return "0" }
        switch count {
        case 0..<1_000:
            return "\(count)"
        case 1_000..<1_000_000:
            let k = Double(count) / 1_000.0
            // Avoid "1000K" — show "1.0M" instead when rounding pushes past 999
            if k >= 999.5 { return "1.0M" }
            return k < 10 ? String(format: "%.1fK", k) : String(format: "%.0fK", k)
        case 1_000_000..<1_000_000_000:
            let m = Double(count) / 1_000_000.0
            // Avoid "1000M" — show "1.0B" instead when rounding pushes past 999
            if m >= 999.5 { return "1.0B" }
            return m < 10 ? String(format: "%.1fM", m) : String(format: "%.0fM", m)
        default:
            let b = Double(count) / 1_000_000_000.0
            return b < 10 ? String(format: "%.1fB", b) : String(format: "%.0fB", b)
        }
    }
}

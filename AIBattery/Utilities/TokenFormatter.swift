import Foundation

enum TokenFormatter {
    static func format(_ count: Int) -> String {
        guard count >= 0 else { return "0" }
        switch count {
        case 0..<1_000:
            return "\(count)"
        case 1_000..<1_000_000:
            let k = Double(count) / 1_000.0
            return k < 10 ? String(format: "%.1fK", k) : String(format: "%.0fK", k)
        default:
            let m = Double(count) / 1_000_000.0
            return m < 10 ? String(format: "%.1fM", m) : String(format: "%.0fM", m)
        }
    }

}

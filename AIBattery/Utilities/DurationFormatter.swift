import Foundation

/// Formats a time interval into a compact human-readable string.
/// Used across rate limit countdowns, session durations, and reset timers.
enum DurationFormatter {
    /// Compact format: "2d 3h", "2h 15m", "45m", "soon".
    /// Clamps minutes to at least 1 when seconds > 0.
    static func compact(_ seconds: TimeInterval) -> String {
        guard seconds > 0 else { return "soon" }
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        if hours > 24 {
            let days = hours / 24
            return "\(days)d \(hours % 24)h"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(max(minutes, 1))m"
        }
    }
}

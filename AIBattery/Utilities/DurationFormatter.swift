import Foundation

/// Formats a time interval into a compact human-readable string.
/// Used across rate limit countdowns, session durations, and reset timers.
enum DurationFormatter {
    /// Compact format: "2d 3h", "2h 15m", "45m", "32s", "0s".
    /// Shows seconds when under 60s for countdown precision.
    static func compact(_ seconds: TimeInterval) -> String {
        guard seconds > 0 else { return "0s" }
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        if hours >= 24 {
            let days = hours / 24
            return "\(days)d \(hours % 24)h"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes >= 1 {
            return "\(minutes)m"
        } else {
            return "\(max(totalSeconds, 1))s"
        }
    }
}

import CoreGraphics
import Foundation

/// Pure idle-suspension policy — no side effects, fully testable.
/// Used by UsageViewModel to decide whether to skip a polling cycle.
enum IdleSuspendPolicy {
    /// Threshold used by the app: 5 minutes (300 seconds).
    static let defaultThreshold: TimeInterval = 300

    /// Returns true when the machine has been idle long enough to warrant timer suspension.
    nonisolated static func shouldSuspend(secondsIdle: TimeInterval, threshold: TimeInterval = defaultThreshold) -> Bool {
        secondsIdle >= threshold
    }

    /// Reads system HID idle seconds via CGEventSource.
    /// Returns 0 on any failure (safe — never suspends on error).
    nonisolated static func idleSeconds() -> TimeInterval {
        let raw = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .mouseMoved)
        return raw >= 0 ? raw : 0
    }
}

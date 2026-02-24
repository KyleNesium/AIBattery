import Foundation

/// Pure state machine for adaptive polling interval logic.
/// When data stops changing, the polling interval gradually doubles
/// up to a maximum, then resets when new data arrives.
struct AdaptivePollingState {
    var unchangedCycles = 0
    static let adaptiveThreshold = 3
    static let maxPollingInterval: TimeInterval = 300

    /// Evaluate whether the polling interval should change.
    /// Returns the interval to use for the next poll cycle.
    mutating func evaluate(dataChanged: Bool, baseInterval: TimeInterval) -> TimeInterval {
        if dataChanged {
            unchangedCycles = 0
            return baseInterval
        }
        unchangedCycles += 1
        if unchangedCycles >= Self.adaptiveThreshold {
            return min(baseInterval * 2, Self.maxPollingInterval)
        }
        return baseInterval
    }
}

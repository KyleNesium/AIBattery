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
            let doublings = Double(unchangedCycles - Self.adaptiveThreshold + 1)
            return min(baseInterval * pow(2.0, doublings), Self.maxPollingInterval)
        }
        return baseInterval
    }
}

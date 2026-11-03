import Foundation

/// The stops on the rate limit alert slider.
enum AlertThreshold {
    /// The slider used to run 50–95 in steps of 5: eleven stops, most of which nobody
    /// can tell apart. On a fast burn 85 and 90 fire within minutes of each other, and
    /// an alert at 50% is noise rather than a warning. Four stops covers the whole
    /// useful range — an early heads-up at 60, through 90 for "tell me when it's
    /// nearly over".
    static let steps: [Double] = [60, 70, 80, 90]

    /// The value a fresh install starts on.
    static let `default`: Double = 80

    /// Pull a stored value onto the nearest stop. Settings written before the slider
    /// shrank (50, 55, … 95) sit between the new stops, and an unsnapped 95 would keep
    /// firing at 95 while the slider showed 90.
    ///
    /// A value exactly between two stops (85) takes the lower one, because `min(by:)`
    /// keeps the first of equals — deliberate: the snap can then only make an alert
    /// arrive earlier than the user configured, never later.
    static func snapped(_ value: Double) -> Double {
        guard value > 0 else { return `default` }
        return steps.min(by: { abs($0 - value) < abs($1 - value) }) ?? `default`
    }

    /// Slider tick labels, derived from the stops so the two can't drift apart.
    static var labels: [String] { steps.map { "\(Int($0))%" } }
}

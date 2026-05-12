import Foundation

/// Claude subscription plan tiers with estimated 5h/7d token limits.
///
/// Absolute limits are not published by Anthropic — these are community-derived
/// estimates. They serve as defaults until auto-calibrated by a 429 event or
/// restored API utilization headers (see `LocalUsageEstimate.calibrate`).
enum PlanTier: String, CaseIterable, Codable {
    case pro
    case max5x
    case max20x
    case team

    /// User-facing label.
    var displayName: String {
        switch self {
        case .pro: "Pro"
        case .max5x: "Max 5×"
        case .max20x: "Max 20×"
        case .team: "Team"
        }
    }

    /// Estimated 5-hour token budget (all token types: input + output + cache).
    /// Community-derived estimates — auto-calibrated when a 429 is detected.
    var estimatedFiveHourLimit: Int {
        switch self {
        case .pro: 7_000_000
        case .max5x: 35_000_000
        case .max20x: 140_000_000
        case .team: 10_000_000
        }
    }

    /// Estimated 7-day token budget (all token types: input + output + cache).
    var estimatedSevenDayLimit: Int {
        switch self {
        case .pro: 35_000_000
        case .max5x: 175_000_000
        case .max20x: 700_000_000
        case .team: 50_000_000
        }
    }

    // MARK: - Persistence

    /// The user's selected plan tier (nil = not yet chosen).
    static var current: PlanTier? {
        get {
            guard let raw = UserDefaults.standard.string(forKey: UserDefaultsKeys.planTier) else { return nil }
            return PlanTier(rawValue: raw)
        }
        set {
            UserDefaults.standard.set(newValue?.rawValue, forKey: UserDefaultsKeys.planTier)
        }
    }
}

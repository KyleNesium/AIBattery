import SwiftUI

/// Centralized color theming with colorblind-safe palette support.
///
/// Standard mode: green → yellow → orange → red
/// Colorblind mode: blue → cyan → amber → purple (distinguishable for deuteranopia/protanopia)
enum ThemeColors {
    /// Cached colorblind flag — updated via KVO observer when the preference changes.
    private(set) static var isColorblind: Bool = UserDefaults.standard.bool(forKey: UserDefaultsKeys.colorblindMode)

    /// One-time KVO registration to keep isColorblind in sync with UserDefaults.
    private static let observer: NSObjectProtocol = {
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            isColorblind = UserDefaults.standard.bool(forKey: UserDefaultsKeys.colorblindMode)
        }
    }()

    /// Call once at app launch to ensure the observer is registered.
    static func registerObserver() { _ = observer }

    /// Re-read the colorblind flag from UserDefaults. Used by tests after changing the preference.
    static func refreshColorblindFlag() {
        isColorblind = UserDefaults.standard.bool(forKey: UserDefaultsKeys.colorblindMode)
    }

    /// Amber color constant used across both colorblind palettes.
    static let amber = Color(red: 1.0, green: 0.75, blue: 0.0)

    /// Color for a usage percentage (0–100).
    static func barColor(percent: Double) -> Color {
        if isColorblind {
            switch percent {
            case 0..<50: return .blue
            case 50..<80: return .cyan
            case 80..<95: return amber // amber
            default: return .purple
            }
        }
        switch percent {
        case 0..<50: return .green
        case 50..<80: return .yellow
        case 80..<95: return .orange
        default: return .red
        }
    }

    /// Color for a health band.
    static func bandColor(_ band: HealthBand) -> Color {
        if isColorblind {
            switch band {
            case .green: return .blue
            case .orange: return amber // amber
            case .red: return .purple
            case .unknown: return .gray
            }
        }
        switch band {
        case .green: return .green
        case .orange: return .orange
        case .red: return .red
        case .unknown: return .gray
        }
    }

    /// Color for a status indicator (system status page).
    static func statusColor(_ indicator: StatusIndicator) -> Color {
        if isColorblind {
            switch indicator {
            case .operational: return .blue
            case .degradedPerformance: return .cyan
            case .maintenance: return .blue
            case .partialOutage: return amber
            case .majorOutage: return .purple
            case .unknown: return .gray
            }
        }
        switch indicator {
        case .operational: return .green
        case .degradedPerformance: return .yellow
        case .maintenance: return .blue
        case .partialOutage: return .orange
        case .majorOutage: return .red
        case .unknown: return .gray
        }
    }

    /// Accent color for charts and data visualizations.
    static var chartAccent: Color {
        isColorblind ? .blue : .orange
    }

    /// Color for the "caution" semantic (idle badges, staleness, warnings).
    static var caution: Color {
        isColorblind ? amber : .orange
    }

    /// Color for trend direction arrows — brighter than standard bar colors for small text readability.
    static func trendColor(_ direction: TrendDirection) -> Color {
        switch direction {
        case .up: return isColorblind ? amber : Color(red: 1.0, green: 0.6, blue: 0.2)
        case .down: return isColorblind ? .cyan : Color(red: 0.3, green: 0.85, blue: 0.4)
        case .flat: return .primary.opacity(0.5)
        }
    }

    /// Color for danger/error states (throttled, auth errors, critical warnings).
    static var danger: Color {
        isColorblind ? .purple : .red
    }

    /// NSColor variant for menu bar icon.
    static func barNSColor(percent: Double) -> NSColor {
        if isColorblind {
            switch percent {
            case 0..<50: return .systemBlue
            case 50..<80: return .systemTeal
            case 80..<95: return NSColor(red: 1.0, green: 0.75, blue: 0.0, alpha: 1.0)
            default: return .systemPurple
            }
        }
        switch percent {
        case 0..<50: return .systemGreen
        case 50..<80: return .systemYellow
        case 80..<95: return .systemOrange
        default: return .systemRed
        }
    }
}

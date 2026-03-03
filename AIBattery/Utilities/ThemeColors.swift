import SwiftUI
import AppKit

/// Centralized color theming with colorblind-safe palette support.
///
/// Standard mode: green → gold → orange → red
/// Colorblind mode: blue → cyan → amber → purple (distinguishable for deuteranopia/protanopia)
///
/// All colors are tested against both light and dark backgrounds.
/// Custom colors use `adaptive(light:dark:)` to provide distinct variants per appearance.
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

    /// Gold color for the 50–80% bar range. Uses system yellow in both modes —
    /// the opaque light-mode background provides enough contrast for yellow to read clearly.
    private static let gold = Color(nsColor: .systemYellow)

    /// Creates a SwiftUI Color that adapts between light and dark appearance.
    static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }

    /// Orange for the 80–95% bar range. Uses system orange in both modes —
    /// the opaque light-mode background provides enough contrast.
    private static let deepOrange = Color(nsColor: .systemOrange)

    /// Color for a usage percentage (0–100).
    static func barColor(percent: Double) -> Color {
        if isColorblind {
            switch percent {
            case 0..<50: return .blue
            case 50..<80: return .cyan
            case 80..<95: return amber
            default: return .purple
            }
        }
        switch percent {
        case 0..<50: return .green
        case 50..<80: return gold
        case 80..<95: return deepOrange
        default: return .red
        }
    }

    /// Color for a health band.
    static func bandColor(_ band: HealthBand) -> Color {
        if isColorblind {
            switch band {
            case .green: return .blue
            case .orange: return amber
            case .red: return .purple
            case .unknown: return .gray
            }
        }
        switch band {
        case .green: return .green
        case .orange: return deepOrange
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
        case .degradedPerformance: return gold
        case .maintenance: return .blue
        case .partialOutage: return deepOrange
        case .majorOutage: return .red
        case .unknown: return .gray
        }
    }

    /// Accent color for charts and data visualizations.
    static var chartAccent: Color {
        isColorblind ? .blue : Color(nsColor: .systemOrange)
    }

    /// Color for the "caution" semantic (idle badges, staleness, warnings).
    static var caution: Color {
        if isColorblind { return amber }
        return deepOrange
    }

    /// Color for trend direction arrows.
    static func trendColor(_ direction: TrendDirection) -> Color {
        switch direction {
        case .up: return isColorblind ? amber : .orange
        case .down: return isColorblind ? .cyan : .green
        case .flat: return .primary.opacity(0.5)
        }
    }

    /// Color for danger/error states (throttled, auth errors, critical warnings).
    static var danger: Color {
        isColorblind ? .purple : .red
    }

    // MARK: - Text label colors

    /// Secondary-level text — darker than system `.secondary` in light mode for readability.
    static var secondaryLabel: Color {
        adaptive(
            light: NSColor(white: 0.0, alpha: 0.7),
            dark: NSColor(white: 1.0, alpha: 0.55)
        )
    }

    /// Tertiary-level text — much darker than system `.tertiary` in light mode.
    /// Replaces `.tertiary` / `.quaternary` foregroundStyle for readability on light backgrounds.
    static var tertiaryLabel: Color {
        adaptive(
            light: NSColor(white: 0.0, alpha: 0.55),
            dark: NSColor(white: 1.0, alpha: 0.35)
        )
    }

    // MARK: - Track & background colors

    /// Background for bar gauge tracks. Slightly higher contrast in light mode.
    static var trackFill: Color {
        adaptive(
            light: NSColor(white: 0.0, alpha: 0.14),
            dark: NSColor(white: 1.0, alpha: 0.1)
        )
    }

    /// Subtle badge background (e.g., "binding" label).
    static var badgeFill: Color {
        adaptive(
            light: NSColor(white: 0.0, alpha: 0.09),
            dark: NSColor(white: 1.0, alpha: 0.06)
        )
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

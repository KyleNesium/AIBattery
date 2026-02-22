import SwiftUI

/// Centralized color theming with colorblind-safe palette support.
///
/// Standard mode: green → yellow → orange → red
/// Colorblind mode: blue → cyan → amber → magenta (distinguishable for deuteranopia/protanopia)
enum ThemeColors {
    private static var isColorblind: Bool {
        UserDefaults.standard.bool(forKey: UserDefaultsKeys.colorblindMode)
    }

    /// Color for a usage percentage (0–100).
    static func barColor(percent: Double) -> Color {
        if isColorblind {
            switch percent {
            case 0..<50: return .blue
            case 50..<80: return .cyan
            case 80..<95: return Color(red: 1.0, green: 0.75, blue: 0.0) // amber
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
            case .orange: return Color(red: 1.0, green: 0.75, blue: 0.0) // amber
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
            case .degradedPerformance, .maintenance: return .cyan
            case .partialOutage: return Color(red: 1.0, green: 0.75, blue: 0.0)
            case .majorOutage: return .purple
            case .unknown: return .gray
            }
        }
        switch indicator {
        case .operational: return .green
        case .degradedPerformance, .maintenance: return .yellow
        case .partialOutage: return .orange
        case .majorOutage: return .red
        case .unknown: return .gray
        }
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

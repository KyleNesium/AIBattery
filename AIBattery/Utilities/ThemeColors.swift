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
    /// `nonisolated(unsafe)` is acceptable here: writes happen exclusively from the
    /// main-queue observer closure below, and reads are a Bool (atomic on aligned memory)
    /// used only as a UI palette hint.
    nonisolated(unsafe) private(set) static var isColorblind: Bool = UserDefaults.standard.bool(forKey: UserDefaultsKeys.colorblindMode)

    /// One-time KVO registration to keep isColorblind in sync with UserDefaults.
    /// `nonisolated(unsafe)` is fine — the value is set once at init and treated as
    /// an opaque token from then on.
    nonisolated(unsafe) private static let observer: NSObjectProtocol = NotificationCenter.default.addObserver(
        forName: UserDefaults.didChangeNotification,
        object: nil,
        queue: .main
    ) { _ in
        isColorblind = UserDefaults.standard.bool(forKey: UserDefaultsKeys.colorblindMode)
    }

    /// Call once at app launch to ensure the observer is registered.
    static func registerObserver() {
        _ = observer
    }

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

    /// System colors wrapped as SwiftUI Color — matches barNSColor exactly.
    private static let sysGreen = Color(nsColor: .systemGreen)
    private static let sysRed = Color(nsColor: .systemRed)
    private static let sysBlue = Color(nsColor: .systemBlue)
    private static let sysCyan = Color(nsColor: .systemTeal)
    private static let sysPurple = Color(nsColor: .systemPurple)

    /// Color for a usage percentage (0–100).
    static func barColor(percent: Double) -> Color {
        if isColorblind {
            switch percent {
            case 0..<50: return sysBlue
            case 50..<80: return sysCyan
            case 80..<95: return amber
            default: return sysPurple
            }
        }
        switch percent {
        case 0..<50: return sysGreen
        case 50..<80: return gold
        case 80..<95: return deepOrange
        default: return sysRed
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
        if isColorblind {
            return amber
        }
        return deepOrange
    }

    /// Color for trend direction arrows.
    static func trendColor(_ direction: TrendDirection) -> Color {
        switch direction {
        case .up: isColorblind ? amber : .orange
        case .down: isColorblind ? .cyan : .green
        case .flat: .primary.opacity(0.5)
        }
    }

    /// Color for danger/error states (throttled, auth errors, critical warnings).
    static var danger: Color {
        isColorblind ? .purple : .red
    }

    /// Color for interactive links and action buttons.
    static var action: Color { .accentColor }

    /// Color for update-available indicators and banners.
    static var updateAvailable: Color {
        isColorblind ? amber : Color(nsColor: .systemYellow)
    }

    /// Color for success confirmations (e.g. "Up to date", "Reset").
    static var success: Color {
        isColorblind ? .blue : .green
    }

    // MARK: - Text label colors

    /// Secondary-level text — darker than system `.secondary` in light mode for readability.
    static let secondaryLabel: Color = adaptive(
        light: NSColor(white: 0.0, alpha: 0.7),
        dark: NSColor(white: 1.0, alpha: 0.55)
    )

    /// Tertiary-level text — much darker than system `.tertiary` in light mode.
    /// Replaces `.tertiary` / `.quaternary` foregroundStyle for readability on light backgrounds.
    static let tertiaryLabel: Color = adaptive(
        light: NSColor(white: 0.0, alpha: 0.55),
        dark: NSColor(white: 1.0, alpha: 0.35)
    )

    /// Inactive stroke — the project's canonical "subtle secondary outline" used
    /// for unselected segmented-control borders, inactive auto-mode ring, etc.
    /// Centralizes the prior `Color.secondary.opacity(…)` pattern.
    static let inactiveStroke: Color = .secondary

    /// Shadow color for elevated controls (selected tab fill, hovered cards).
    /// Wraps the raw black-with-opacity pattern that was scattered across views.
    static let shadowColor: Color = .black

    // MARK: - Interactive state colors

    /// Hover highlight for interactive elements (buttons, chevrons, headers).
    static let hoverFill: Color = adaptive(
        light: NSColor(white: 0.0, alpha: 0.06),
        dark: NSColor(white: 1.0, alpha: 0.06)
    )

    /// Stronger hover highlight for copyable elements (signals "click to copy").
    static let copyableHoverFill: Color = adaptive(
        light: NSColor(white: 0.0, alpha: 0.15),
        dark: NSColor(white: 1.0, alpha: 0.15)
    )

    /// Divider opacity (StyledDivider).
    static let dividerOpacity: Double = 0.3

    /// Overlay backdrop opacity (tutorial, modal dimming).
    static let overlayBackdropOpacity: Double = 0.4

    /// Inactive dot/indicator opacity (step indicators, deselected controls).
    static let inactiveIndicatorOpacity: Double = 0.45

    /// Subtle border opacity for unhovered/inactive outlines.
    static let subtleBorderOpacity: Double = 0.2

    /// Medium border opacity for hovered outlines.
    static let hoverBorderOpacity: Double = 0.4

    /// Active-state label opacity for secondary text.
    static let activeLabelOpacity: Double = 0.5

    /// Focus ring opacity (keyboard focus indicators).
    static let focusRingOpacity: Double = 0.6

    /// Shadow opacity for raised elements (selected tab pill).
    static let shadowOpacity: Double = 0.25

    /// Disabled control opacity multiplier (picker, chevrons).
    static let disabledOpacity: Double = 0.55

    /// Deeply disabled control opacity (chevron arrows when at boundary).
    static let disabledDeepOpacity: Double = 0.25

    /// Subtle element fill opacity (banner backgrounds, auto mode fills).
    static let subtleElementOpacity: Double = 0.12

    /// Subtle border/stroke opacity (banner outlines).
    static let subtleStrokeOpacity: Double = 0.35

    /// Chart gradient start opacity.
    static let chartGradientStartOpacity: Double = 0.3

    /// Chart gradient end opacity.
    static let chartGradientEndOpacity: Double = 0.1

    /// Active element accent opacity (auto mode stroke, active glow).
    static let activeAccentOpacity: Double = 0.6

    /// Active element fill opacity (auto mode selected background).
    static let activeElementFillOpacity: Double = 0.15

    /// Enabled control opacity (chevron buttons, active controls).
    static let enabledControlOpacity: Double = 0.6

    // MARK: - Panel background

    /// Panel background that matches native macOS dark mode panels (Battery, Wi-Fi).
    /// Dark mode: rgb(28,28,30) — the standard system dark panel color.
    /// Light mode: rgb(246,246,246) — standard system light panel color.
    static let panelBackground: Color = adaptive(
        light: NSColor(white: 0.965, alpha: 1.0),
        dark: NSColor(red: 0.11, green: 0.11, blue: 0.118, alpha: 1.0)
    )

    // MARK: - Surface elevation (dark mode depth hierarchy)

    /// Level 1 surface — card/section background. Slightly raised from panel.
    static let surfaceLevel1: Color = adaptive(
        light: NSColor(white: 0.0, alpha: 0.03),
        dark: NSColor(white: 1.0, alpha: 0.03)
    )

    /// Level 2 surface — raised interactive elements (selected tabs, active controls).
    static let surfaceLevel2: Color = adaptive(
        light: NSColor(white: 1.0, alpha: 0.9),
        dark: NSColor(white: 1.0, alpha: 0.18)
    )

    // MARK: - Track & background colors

    /// Background for bar gauge tracks. Slightly higher contrast in light mode.
    static let trackFill: Color = adaptive(
        light: NSColor(white: 0.0, alpha: 0.14),
        dark: NSColor(white: 1.0, alpha: 0.1)
    )

    /// Subtle badge background (e.g., "binding" label).
    static let badgeFill: Color = adaptive(
        light: NSColor(white: 0.0, alpha: 0.09),
        dark: NSColor(white: 1.0, alpha: 0.06)
    )

    /// Deep gold for the menu bar star on light backgrounds where systemYellow washes out.
    static let menuBarGold = NSColor(red: 0.72, green: 0.56, blue: 0.0, alpha: 1.0)

    /// NSColor variant for menu bar icon — rate limit thresholds (50/80/95).
    /// When `isDarkMenuBar` is provided, the 50-79% band uses a darker gold on light
    /// backgrounds for contrast (systemYellow is nearly invisible on a light menu bar).
    static func barNSColor(percent: Double, isDarkMenuBar: Bool? = nil) -> NSColor {
        if isColorblind {
            switch percent {
            case 0..<50: return .systemBlue
            case 50..<80: return isDarkMenuBar == false ? menuBarGold : .systemTeal
            case 80..<95: return NSColor(red: 1.0, green: 0.75, blue: 0.0, alpha: 1.0)
            default: return .systemPurple
            }
        }
        switch percent {
        case 0..<50: return .systemGreen
        case 50..<80: return isDarkMenuBar == false ? menuBarGold : .systemYellow
        case 80..<95: return .systemOrange
        default: return .systemRed
        }
    }

    /// NSColor for context health — matches HealthBand thresholds (60/80).
    /// Green < 60%, orange 60–80%, red >= 80%.
    static func contextHealthNSColor(percent: Double) -> NSColor {
        if isColorblind {
            switch percent {
            case 0..<60: return .systemBlue
            case 60..<80: return NSColor(red: 1.0, green: 0.75, blue: 0.0, alpha: 1.0)
            default: return .systemPurple
            }
        }
        switch percent {
        case 0..<60: return .systemGreen
        case 60..<80: return .systemOrange
        default: return .systemRed
        }
    }
}

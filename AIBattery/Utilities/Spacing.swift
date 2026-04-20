import CoreGraphics
import SwiftUI

/// Spacing scale for the AI Battery menu bar app.
///
/// Use these named tokens instead of hardcoded numeric padding values.
/// Six tokens cover all dominant padding patterns found in the codebase audit
/// (52 `.padding()` calls across ~16 view files).
///
/// Pattern matches ThemeColors: caseless enum used as a pure namespace.
enum Spacing {
    /// 1pt — hairline vertical padding for badges and copyable highlights.
    static let micro: CGFloat = 1

    /// 3pt — compact horizontal padding for badges and hover backgrounds.
    static let xsmall: CGFloat = 3

    /// 2pt — divider micro-gap, dot gap between elements.
    static let tight: CGFloat = 2

    /// 4pt — padding inside elements (badge internal padding, minor inset offset).
    static let small: CGFloat = 4

    /// 4pt — spacing between sibling elements in a row/stack (header HStack, badge elements).
    static let inner: CGFloat = 4

    /// 6pt — VStack section spacing, header/footer vertical padding.
    static let gap: CGFloat = 6

    /// 8pt — standard section vertical outer padding.
    static let section: CGFloat = 8

    /// 16pt — standard section horizontal outer padding (12 uses in codebase).
    static let sectionHorizontal: CGFloat = 16

    /// 10pt — footer link row spacing.
    static let medium: CGFloat = 10

    /// 12pt — auth flow card outer spacing.
    static let authGap: CGFloat = 12

    /// 24pt — overlay and tutorial content padding.
    static let overlay: CGFloat = 24
}

/// Fixed frame dimensions for the AI Battery menu bar app.
///
/// Only contains values that define the outer UI skeleton and appear 2+ times
/// or are semantically significant. One-off column widths and computed frame
/// dimensions remain local to their views.
enum Layout {
    /// Popover panel width used in AuthView and StatusBarManager.
    static let popoverWidth: CGFloat = 275

    /// Activity/token health chart height (ActivityChartView — 4 uses).
    static let chartHeight: CGFloat = 50

    /// Progress bar height in UsageBar and TokenHealthSection.
    static let barHeight: CGFloat = 8

    /// Progress bar corner radius.
    static let barCornerRadius: CGFloat = 3

    /// Chevron button tap target frame (CollapsibleSectionHeader).
    static let chevronFrame: CGFloat = 22

    /// Health/model status dot diameter.
    static let dotSize: CGFloat = 8

    /// Token type/status component dot diameter (smaller variant).
    static let dotSizeSmall: CGFloat = 6

    /// Auto mode "A" button circle diameter.
    static let autoModeSize: CGFloat = 20

    /// Metric tab pill corner radius.
    static let tabCornerRadius: CGFloat = 4

    /// Small element corner radius (search field, tooltip, chevron highlight).
    static let smallCornerRadius: CGFloat = 4

    /// Banner corner radius (update banner, search field).
    static let bannerCornerRadius: CGFloat = 6

    /// Auth app icon clip radius.
    static let iconClipRadius: CGFloat = 10

    /// Card/overlay corner radius (tutorial card, dialogs).
    static let cardCornerRadius: CGFloat = 12

    /// Column width for compact cost values (e.g. "~$4.0K").
    static let costColumn: CGFloat = 46

    /// Column width for token values (e.g. "1.2M").
    static let tokenColumn: CGFloat = 42

    /// Settings label column width (e.g. "Refresh", "Alerts", "Display").
    static let settingsLabel: CGFloat = 50

    /// Settings slider value label width (e.g. "60s", "30m", "80%").
    static let sliderValueLabel: CGFloat = 28

    /// Insight row label column width (e.g. "Period", "Longest", "All Time").
    static let insightLabel: CGFloat = 55

    /// Marquee text line height.
    static let marqueeHeight: CGFloat = 14

    /// Inline spinner size (footer, loading indicators).
    static let spinnerSize: CGFloat = 10

    /// Loading state placeholder height.
    static let stateHeightLoading: CGFloat = 40

    /// Empty state placeholder height.
    static let stateHeightEmpty: CGFloat = 80

    /// Error state placeholder height.
    static let stateHeightError: CGFloat = 100

    /// Menu bar icon canvas size.
    static let iconSize: CGFloat = 22

    /// Chart data point symbol size.
    static let chartSymbolSize: CGFloat = 12

    /// Subtle raised-element shadow (selected tab pill).
    static let shadowSmall: CGFloat = 1

    /// Glow radius for active indicator (auto mode button).
    static let glowRadius: CGFloat = 4

    /// Standard stroke width for borders and focus rings.
    static let borderWidth: CGFloat = 1.5
}

/// Animation duration constants for the AI Battery popover.
///
/// Centralizes the two dominant animation durations found across the codebase.
/// Pattern matches ThemeColors/Typography/Spacing: caseless enum as namespace.
enum MotionConstants {
    /// Standard section expand/collapse and metric value animation: 0.15s easeOut.
    static let standard: Animation = .easeOut(duration: 0.15)

    /// Snappy gesture-driven animation (session swipe, nav): 0.1s easeOut.
    static let snappy: Animation = .easeOut(duration: 0.1)

    /// Smooth data-driven animation (gauge fill, chart transition): 0.4s easeInOut.
    static let smooth: Animation = .easeInOut(duration: 0.4)

    /// Cross-fade text transition (marquee): 0.3s easeOut.
    static let fadeOut: Animation = .easeOut(duration: 0.3)

    /// Dialog/overlay enter/exit: 0.2s easeInOut.
    static let dialog: Animation = .easeInOut(duration: 0.2)

    /// Full-rotation spin (refresh button): 0.5s easeInOut.
    static let spin: Animation = .easeInOut(duration: 0.5)

    /// Section expand/collapse transition — fade + slide from top.
    static var expandTransition: AnyTransition {
        .opacity.combined(with: .move(edge: .top))
    }
}

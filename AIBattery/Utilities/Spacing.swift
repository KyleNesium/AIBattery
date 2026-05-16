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

    /// Subtle stroke width for banner borders and chart ticks.
    static let subtleBorderWidth: CGFloat = 1

    /// App icon size in auth view.
    static let appIconSize: CGFloat = 48

    /// Activity mode segmented picker width.
    static let activityModePickerWidth: CGFloat = 120

    /// Project list index column width.
    static let indexColumn: CGFloat = 14

    /// Tutorial card max width.
    static let tutorialCardMaxWidth: CGFloat = 280

    /// Account picker max width in header.
    static let accountPickerMaxWidth: CGFloat = 100

    /// Clipboard icon trailing offset (negative for overlay positioning).
    static let clipboardIconOffset: CGFloat = 13

    /// Panel initial height (overwritten by resize observer on first layout).
    static let panelInitialHeight: CGFloat = 700

    /// Panel minimum height (prevents collapsed state from disappearing).
    static let panelMinHeight: CGFloat = 100

    /// Menu bar inset subtracted from screen height for panel max height.
    static let menuBarInset: CGFloat = 40

    /// Fallback screen height when panel.screen is nil.
    static let fallbackScreenHeight: CGFloat = 900

    /// Chart axis tick stroke width.
    static let chartTickWidth: CGFloat = 0.5
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

    /// Cross-fade text out (marquee): 0.3s easeOut.
    static let fadeOut: Animation = .easeOut(duration: 0.3)

    /// Cross-fade text in (marquee): 0.3s easeIn.
    static let fadeIn: Animation = .easeIn(duration: 0.3)

    /// Dialog/overlay enter/exit: 0.2s easeInOut.
    static let dialog: Animation = .easeInOut(duration: 0.2)

    /// Full-rotation spin (refresh button): 0.5s easeInOut.
    static let spin: Animation = .easeInOut(duration: 0.5)

    // MARK: - Marquee (footer incident ticker)

    /// Pause at each end of a marquee scroll, and the initial geometry-settle
    /// delay before the first scroll. Short so the leading text isn't mistaken
    /// for a static, truncated message on first reveal.
    static let marqueePauseSeconds: Double = 0.5

    /// Hold duration for a non-scrolling text before cycling to the next.
    static let marqueeHoldSeconds: Double = 3.0

    /// Restart delay after the `texts` array changes — lets new geometry settle.
    static let marqueeRestartSeconds: Double = 0.1

    /// Wait between fade-in completing and the next scroll cycle starting,
    /// so geometry has time to remeasure under the new text.
    static let marqueeFadeSettleSeconds: Double = 0.6

    /// Points per second a marquee scrolls horizontally.
    static let marqueeScrollSpeed: Double = 30.0

    /// Linear animation for a marquee scroll of `travel` points at `marqueeScrollSpeed`.
    static func marqueeScroll(travelPoints: Double) -> Animation {
        .linear(duration: max(0.0, travelPoints / marqueeScrollSpeed))
    }

    /// Section expand/collapse transition.
    ///
    /// Plain opacity — never .move(edge:) inside the popover. The panel is
    /// an NSPanel that re-anchors its top to the menu bar and grows/shrinks
    /// to fit SwiftUI's content height. A .move transition translates the
    /// inserting/removing view while the panel is simultaneously resizing,
    /// which reads as a "jump" rather than a smooth expand. Cross-fade
    /// hides the resize boundary cleanly.
    static var expandTransition: AnyTransition {
        .opacity
    }

    // MARK: - State timing (non-animation durations)

    /// Clipboard "copied" feedback icon display duration (nanoseconds).
    static let clipboardFeedbackNs: UInt64 = 1_500_000_000

    /// Logout confirmation revert timeout (nanoseconds).
    static let logoutConfirmNs: UInt64 = 3_000_000_000

    /// Update check success message display duration (nanoseconds).
    static let updateCheckMessageNs: UInt64 = 2_500_000_000
}

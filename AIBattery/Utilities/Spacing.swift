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
    /// 2pt — divider micro-gap, dot gap between elements.
    static let tight: CGFloat = 2

    /// 4pt — badge internal padding, minor offset.
    static let small: CGFloat = 4

    /// 4pt — internal element spacing within a section (header HStack, badge elements).
    static let inner: CGFloat = 4

    /// 6pt — VStack section spacing, header/footer vertical padding.
    static let gap: CGFloat = 6

    /// 8pt — standard section vertical outer padding.
    static let section: CGFloat = 8

    /// 16pt — standard section horizontal outer padding (12 uses in codebase).
    static let sectionHorizontal: CGFloat = 16

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

    /// Banner corner radius (update banner, search field).
    static let bannerCornerRadius: CGFloat = 6

    /// Column width for compact cost values (e.g. "~$4.0K").
    static let costColumn: CGFloat = 46

    /// Column width for token values (e.g. "1.2M").
    static let tokenColumn: CGFloat = 42
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

    /// Section expand/collapse transition — fade + slide from top.
    static var expandTransition: AnyTransition {
        .opacity.combined(with: .move(edge: .top))
    }
}

import SwiftUI

/// Centralized typography constants for the AI Battery menu bar app.
///
/// **Type scale** (minor third ratio ~1.2×, anchored at 10pt base):
///   9pt (icons) → 10pt (base) → 11pt (body) → 12pt (emphasis) → 14pt (hero)
///   System text styles (caption, caption2, subheadline, headline) are used
///   where Dynamic Type scaling is desirable.
///
/// Use these named tokens instead of inline `.font()` calls to ensure consistency
/// and enable design-wide changes from a single location.
///
/// Pattern matches ThemeColors: caseless enum used as a pure namespace.
enum Typography {

    // MARK: - Scale anchors (fixed pt)

    /// Icon-only minimum — 9pt. Not for text; only SF Symbols.
    static let iconSmall: Font = .system(size: 9)

    /// Base size for compact labels and monospaced values — 10pt.
    static let base: Font = .system(size: 10)

    /// Body labels in settings and auth — 11pt medium.
    static let bodyLabel: Font = .system(size: 11, weight: .medium)

    /// Emphasized metric value — 12pt bold.
    static let heroValue: Font = .system(size: 12, weight: .bold)

    /// Hero display — 14pt. Largest fixed size in the popover.
    static let heroTitle: Font = .system(size: 14)

    // MARK: - Section headers (system text styles — scale with Dynamic Type)

    /// CollapsibleSectionHeader title text — subheadline bold.
    static let sectionHeader: Font = .subheadline.bold()

    /// Button and action label text (e.g. "Install Update").
    static let buttonLabel: Font = .subheadline.weight(.medium)

    /// Section sub-labels and footer text.
    static let caption: Font = .caption

    /// Small auxiliary text and timestamps.
    static let tinyLabel: Font = .caption2

    // MARK: - Monospaced (for numeric alignment)

    /// Primary monospaced numeric display (rate limit %, large values).
    static let monoValue: Font = .system(.headline, design: .monospaced, weight: .semibold)

    /// Medium monospaced value (project names, session token counts).
    static let monoValueMedium: Font = .system(.subheadline, design: .monospaced, weight: .semibold)

    /// Standard monospaced caption (model IDs, small token counts).
    static let monoCaption: Font = .system(.caption, design: .monospaced)

    /// Small monospaced caption (byte counts, secondary metrics).
    static let monoCaptionSmall: Font = .system(.caption2, design: .monospaced)

    /// Compact monospaced label (session IDs, footer icons) — 10pt base.
    static let monoTiny: Font = .system(size: 10, design: .monospaced)

    // MARK: - Semantic aliases

    /// Chevron icon inside CollapsibleSectionHeader — compact bold glyph.
    static let chevronIcon: Font = .system(size: 9, weight: .bold)

    /// Badge/tag label text (e.g. "binding" pill in session views).
    static let badgeLabel: Font = .system(size: 10, weight: .medium, design: .monospaced)

    /// Decorative SF Symbol — 9pt icon floor.
    static let decorativeIcon: Font = iconSmall

    /// Clipboard feedback icon in copyable modifier.
    static let clipboardIcon: Font = iconSmall

    /// Trend change symbol (↑/↓) — semibold monospaced for visual weight.
    static let trendSymbol: Font = .system(size: 11, weight: .semibold, design: .monospaced)

    /// Collapsed trend label — compact monospaced at 10pt.
    static let trendLabelSmall: Font = .system(size: 10, weight: .semibold, design: .monospaced)

    /// Auto mode "A" button label — heavy rounded for icon-like feel.
    static let autoModeLabel: Font = .system(size: 10, weight: .heavy, design: .rounded)
}

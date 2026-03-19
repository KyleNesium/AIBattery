import SwiftUI

/// Centralized typography constants for the AI Battery menu bar app.
///
/// Use these named tokens instead of inline `.font()` calls to ensure consistency
/// and enable design-wide changes from a single location.
///
/// Pattern matches ThemeColors: caseless enum used as a pure namespace.
enum Typography {

    // MARK: - Section headers

    /// CollapsibleSectionHeader title text — subheadline bold.
    static let sectionHeader: Font = .subheadline.bold()

    /// Chevron icon inside CollapsibleSectionHeader — compact bold glyph.
    static let chevronIcon: Font = .system(size: 9, weight: .bold)

    // MARK: - Hero / large values

    /// Large numeric or percentage display (e.g. rate limit %, session count).
    static let heroTitle: Font = .system(size: 14)

    /// Primary bold metric value (e.g. token count in UsagePopoverView).
    static let heroValue: Font = .system(size: 12, weight: .bold)

    // MARK: - Body text

    /// Standard body label in settings rows and auth view.
    static let bodyLabel: Font = .system(size: 11, weight: .medium)

    /// Section sub-labels and footer text.
    static let caption: Font = .caption

    /// Small auxiliary text and timestamps.
    static let tinyLabel: Font = .caption2

    // MARK: - Monospaced values

    /// Primary monospaced numeric display (rate limit %, large values).
    static let monoValue: Font = .system(.headline, design: .monospaced, weight: .semibold)

    /// Medium monospaced value (project names, session token counts).
    static let monoValueMedium: Font = .system(.subheadline, design: .monospaced, weight: .semibold)

    /// Standard monospaced caption (model IDs, small token counts).
    static let monoCaption: Font = .system(.caption, design: .monospaced)

    /// Small monospaced caption (byte counts, secondary metrics).
    static let monoCaptionSmall: Font = .system(.caption2, design: .monospaced)

    /// Tiny monospaced label (inline session dot labels, 9pt).
    static let monoTiny: Font = .system(size: 9, design: .monospaced)

    // MARK: - Badges & labels

    /// Badge/tag label text (e.g. "binding" pill in session views).
    static let badgeLabel: Font = .system(size: 9, weight: .medium, design: .monospaced)

    /// Button and action label text (e.g. "Install Update").
    static let buttonLabel: Font = .subheadline.weight(.medium)

    /// Minimum decorative icon — 8pt floor enforcing UI-05.
    /// Replaces all `size: 6` calls (FooterLink arrow, UsagePopoverView badge arrow).
    static let decorativeIcon: Font = .system(size: 8)
}

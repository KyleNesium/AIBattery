import SwiftUI

/// A plain text-styled button that reads as a link rather than a control —
/// used for inline secondary actions like "Add Account", "Test", "Download",
/// "Install Update". Standardizes color (`ThemeColors.action`), font scale,
/// and icon-to-text spacing across what used to be four ad-hoc variants.
///
/// Use `.standard` for in-flow settings actions (e.g. Add Account) and
/// `.compact` for in-banner actions (Test, Download, Install Update).
struct LinkActionButton: View {
    enum Size {
        case standard
        case compact
    }

    let label: String
    var icon: String?
    var size: Size = .standard
    var help: String?
    var accessibilityLabel: String?
    var accessibilityHint: String = ""
    let action: () -> Void

    private var labelFont: Font { Self.labelFont(for: size) }
    private var iconFont: Font { Self.iconFont(for: size) }

    /// Label font for the given size variant. Exposed for unit tests so the
    /// scaling contract is pinned outside of view-body introspection.
    static func labelFont(for size: Size) -> Font {
        size == .compact ? Typography.tinyLabel : Typography.caption
    }

    /// Icon font for the given size variant.
    static func iconFont(for size: Size) -> Font {
        size == .compact ? Typography.monoTiny : Typography.tinyLabel
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.xsmall) {
                if let icon {
                    Image(systemName: icon)
                        .font(iconFont)
                }
                Text(label)
                    .font(labelFont)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(ThemeColors.action)
        .modifier(OptionalHelp(text: help))
        .accessibilityLabel(accessibilityLabel ?? label)
        .accessibilityHint(accessibilityHint)
    }
}

/// `.help(_)` always renders a tooltip — even with an empty string — and
/// SwiftUI doesn't ship an "apply only if non-nil" overload. Wrap it.
private struct OptionalHelp: ViewModifier {
    let text: String?
    func body(content: Content) -> some View {
        if let text {
            content.help(text)
        } else {
            content
        }
    }
}

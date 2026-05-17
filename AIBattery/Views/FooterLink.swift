import SwiftUI

/// Footer link button with hover underline effect.
///
/// By default renders a trailing arrow.up.right suggesting "opens in browser".
/// Set `showsExternalArrow: false` for inline actions like Logout / Quit.
/// Set `foregroundOverride` when the action communicates state (e.g. destructive
/// confirm) that the default .primary/.secondary palette can't express.
struct FooterLink<Leading: View>: View {
    let icon: String?
    let label: String
    var tooltip: String = ""
    var accessibilityLabel: String?
    var accessibilityHint: String = "Opens in browser"
    var showsExternalArrow: Bool = true
    var foregroundOverride: Color?
    let action: () -> Void
    let leading: () -> Leading

    @State private var isHovered = false
    @FocusState private var isFocused: Bool

    init(
        icon: String? = nil,
        label: String,
        tooltip: String = "",
        accessibilityLabel: String? = nil,
        accessibilityHint: String = "Opens in browser",
        showsExternalArrow: Bool = true,
        foregroundOverride: Color? = nil,
        action: @escaping () -> Void,
        @ViewBuilder leading: @escaping () -> Leading = { EmptyView() }
    ) {
        self.icon = icon
        self.label = label
        self.tooltip = tooltip
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityHint = accessibilityHint
        self.showsExternalArrow = showsExternalArrow
        self.foregroundOverride = foregroundOverride
        self.action = action
        self.leading = leading
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.tight) {
                if Leading.self != EmptyView.self {
                    leading()
                } else if let icon {
                    Image(systemName: icon)
                        .font(Typography.monoTiny)
                }
                Text(label)
                    .font(Typography.tinyLabel)
                    .underline(isHovered || isFocused)
                if showsExternalArrow {
                    Image(systemName: "arrow.up.right")
                        .font(Typography.decorativeIcon)
                }
            }
            .fixedSize()
        }
        .buttonStyle(.plain)
        .foregroundStyle(foregroundOverride ?? (isHovered || isFocused ? .primary : .secondary))
        .focused($isFocused)
        .onHover { isHovered = $0 }
        .help(tooltip)
        .accessibilityLabel(accessibilityLabel ?? label)
        .accessibilityHint(accessibilityHint)
    }
}

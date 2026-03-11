import SwiftUI

/// Footer link button with hover underline effect and external link arrow.
struct FooterLink<Leading: View>: View {
    let icon: String?
    let label: String
    var tooltip: String = ""
    var accessibilityLabel: String?
    var accessibilityHint: String = "Opens in browser"
    let action: () -> Void
    let leading: () -> Leading

    @State private var isHovered = false

    init(
        icon: String? = nil,
        label: String,
        tooltip: String = "",
        accessibilityLabel: String? = nil,
        accessibilityHint: String = "Opens in browser",
        action: @escaping () -> Void,
        @ViewBuilder leading: @escaping () -> Leading = { EmptyView() }
    ) {
        self.icon = icon
        self.label = label
        self.tooltip = tooltip
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityHint = accessibilityHint
        self.action = action
        self.leading = leading
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 2) {
                if Leading.self != EmptyView.self {
                    leading()
                } else if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 9))
                }
                Text(label)
                    .font(.caption2)
                    .underline(isHovered)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 6))
            }
            .fixedSize()
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .onHover { isHovered = $0 }
        .help(tooltip)
        .accessibilityLabel(accessibilityLabel ?? label)
        .accessibilityHint(accessibilityHint)
    }
}

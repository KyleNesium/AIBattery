import SwiftUI

/// Shared collapsible section header with rotating chevron and bold title.
/// Used by Context Health, Tokens, Activity, and Insights sections.
struct CollapsibleSectionHeader: View {
    let title: String
    @Binding var collapsed: Bool
    var tooltip: String = ""
    @State private var isHovered = false
    @FocusState private var isFocused: Bool

    var body: some View {
        Button {
            withAnimation(MotionConstants.standard) { collapsed.toggle() }
        } label: {
            HStack(spacing: Spacing.inner) {
                Image(systemName: "chevron.right")
                    .font(Typography.chevronIcon)
                    .rotationEffect(.degrees(collapsed ? 0 : 90))
                    .foregroundStyle(ThemeColors.tertiaryLabel)
                Text(title)
                    .font(Typography.sectionHeader)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .padding(.horizontal, Spacing.xsmall)
            .padding(.vertical, Spacing.micro)
            .background(
                RoundedRectangle(cornerRadius: Spacing.xsmall)
                    .fill(isHovered ? ThemeColors.hoverFill : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.xsmall)
                    .stroke(isFocused ? Color.accentColor.opacity(ThemeColors.focusRingOpacity) : Color.clear, lineWidth: 1.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focused($isFocused)
        .onHover { isHovered = $0 }
        .help(tooltip)
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel("\(title), \(collapsed ? "collapsed" : "expanded")")
        .accessibilityHint(collapsed ? "Double-tap to expand" : "Double-tap to collapse")
    }
}

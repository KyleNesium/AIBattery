import SwiftUI

/// Shared collapsible section header with rotating chevron and bold title.
/// Used by Context Health, Tokens, Activity, and Insights sections.
struct CollapsibleSectionHeader: View {
    let title: String
    @Binding var collapsed: Bool
    var tooltip: String = ""

    var body: some View {
        Button {
            withAnimation(MotionConstants.standard) { collapsed.toggle() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.right")
                    .font(Typography.chevronIcon)
                    .rotationEffect(.degrees(collapsed ? 0 : 90))
                    .foregroundStyle(ThemeColors.tertiaryLabel)
                Text(title)
                    .font(Typography.sectionHeader)
                    .foregroundStyle(.primary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tooltip)
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel("\(title), \(collapsed ? "collapsed" : "expanded")")
        .accessibilityHint(collapsed ? "Double-tap to expand" : "Double-tap to collapse")
    }
}

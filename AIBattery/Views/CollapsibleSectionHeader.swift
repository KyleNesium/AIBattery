import SwiftUI

/// Shared collapsible section header with rotating chevron and bold title.
/// Used by Context Health, Tokens, Activity, and Insights sections.
struct CollapsibleSectionHeader: View {
    let title: String
    @Binding var collapsed: Bool
    var tooltip: String = ""

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { collapsed.toggle() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .rotationEffect(.degrees(collapsed ? 0 : 90))
                    .foregroundStyle(ThemeColors.tertiaryLabel)
                Text(title)
                    .font(.subheadline.bold())
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

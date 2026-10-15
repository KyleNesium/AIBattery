import SwiftUI

/// Marks a section whose numbers are not yet trustworthy enough to read as fact.
///
/// Deliberately the quietest label in the popover — smaller than a value badge and
/// dimmed well below the section title, so it qualifies the heading without competing
/// with it. The tooltip is where the actual caveat lives.
struct BetaBadge: View {
    var tooltip: String = "This feature is still being refined — treat its numbers as approximate."

    var body: some View {
        Text("beta")
            .font(Typography.betaBadge)
            .foregroundStyle(ThemeColors.tertiaryLabel.opacity(ThemeColors.betaBadgeOpacity))
            .help(tooltip)
            .accessibilityLabel("Beta")
            .accessibilityHint(tooltip)
    }
}

import SwiftUI

/// Standardized divider for AI Battery popover sections.
/// Opacity 0.3 with Spacing.tight (2pt) vertical padding — matches ActivityChartView baseline.
struct StyledDivider: View {
    var body: some View {
        Divider()
            .opacity(0.3)
            .padding(.vertical, Spacing.tight)
    }
}

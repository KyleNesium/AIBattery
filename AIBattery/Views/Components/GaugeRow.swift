import SwiftUI

/// Shared shell for the "labelled gauge" row used by every rate-limit section
/// in the popover: a header HStack, a `GaugeBar`, and a `TimelineView` footer.
///
/// The header content (label, badges, trailing value) and footer content (state
/// text on the left, reset countdown on the right) vary between call sites, so
/// they're supplied as ViewBuilder closures. The wrapper owns the VStack
/// spacing, the gauge wiring, the accessibility plumbing, and the timeline
/// schedule.
struct GaugeRow<HeaderLeading: View, HeaderTrailing: View, Footer: View>: View {
    let percent: Double
    let barColor: Color
    let accessibilityLabel: String
    let accessibilityValue: String
    var tickInterval: TimeInterval = 10
    @ViewBuilder var headerLeading: () -> HeaderLeading
    @ViewBuilder var headerTrailing: () -> HeaderTrailing
    @ViewBuilder var footer: (Date) -> Footer

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.inner) {
            HStack {
                headerLeading()
                Spacer()
                headerTrailing()
            }

            GaugeBar(percent: percent, barColor: barColor)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityLabel)
                .accessibilityValue(accessibilityValue)

            TimelineView(.periodic(from: .now, by: tickInterval)) { context in
                footer(context.date)
            }
        }
    }
}

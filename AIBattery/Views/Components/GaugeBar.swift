import SwiftUI

/// A reusable progress gauge bar that fills proportionally to `percent`.
///
/// Uses a single `GeometryReader` to measure available width, renders a
/// background track and a colored fill bar. Values outside 0–100 are clamped.
///
/// Usage:
/// ```swift
/// GaugeBar(percent: 75, barColor: .blue)
/// ```
struct GaugeBar: View {
    let percent: Double
    let barColor: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: Layout.barCornerRadius)
                    .fill(ThemeColors.trackFill)
                    .frame(height: Layout.barHeight)

                RoundedRectangle(cornerRadius: Layout.barCornerRadius)
                    .fill(barColor)
                    .frame(
                        width: geometry.size.width * Self.clampedPercent(percent),
                        height: Layout.barHeight
                    )
            }
        }
        .frame(height: Layout.barHeight)
    }

    /// Returns a normalized fill fraction in `0.0...1.0` for the given percentage.
    /// Values below 0 clamp to 0; values above 100 clamp to 1.
    static func clampedPercent(_ percent: Double) -> CGFloat {
        CGFloat(min(max(percent, 0), 100) / 100.0)
    }
}

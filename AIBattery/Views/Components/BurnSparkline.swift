import SwiftUI

/// Token spend across the current 5-hour window as one quiet line: twenty 15-minute
/// buckets, oldest on the left. The bars say how much of the window is used; this says
/// what shape the spending has — a line climbing at the right edge is why "~1h to limit"
/// is on the card, and a flat one is why it isn't.
///
/// Drawn with a `Path`, not Swift Charts: a card is laid out on every popover open and
/// the chart framework is deliberately gated behind the deferred heavy sections.
struct BurnSparkline: View {
    /// Tokens per bucket, oldest first. Zero-filled to a fixed count by the caller.
    let counts: [Int]
    /// Stroke colour — the card's headline bar colour, so the line and the gauges agree.
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let points = Self.points(counts: counts, in: geo.size)
            ZStack {
                // Soft area under the line: gives the shape weight without a second hue.
                Self.area(points, height: geo.size.height)
                    .fill(color.opacity(ThemeColors.sparklineFillOpacity))
                Self.line(points)
                    .stroke(color, style: StrokeStyle(lineWidth: Layout.sparklineLineWidth, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(height: Layout.sparklineHeight)
        .accessibilityHidden(true) // the bars and the state line carry the numbers
    }

    /// Map buckets to points, normalised to the tallest bucket so every card uses its
    /// full height. A flat series sits on the baseline rather than mid-height.
    nonisolated static func points(counts: [Int], in size: CGSize) -> [CGPoint] {
        guard counts.count > 1 else { return [] }
        let peak = Double(counts.max() ?? 0)
        let stepX = size.width / Double(counts.count - 1)
        // Keep the stroke inside the frame at the top; the baseline is the frame's bottom.
        let inset = Layout.sparklineLineWidth
        let usable = max(size.height - inset, 0)
        return counts.enumerated().map { index, count in
            let y = peak > 0 ? size.height - (Double(count) / peak) * usable : size.height
            return CGPoint(x: Double(index) * stepX, y: y)
        }
    }

    nonisolated static func line(_ points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        return path
    }

    nonisolated static func area(_ points: [CGPoint], height: CGFloat) -> Path {
        var path = line(points)
        guard let first = points.first, let last = points.last else { return path }
        path.addLine(to: CGPoint(x: last.x, y: height))
        path.addLine(to: CGPoint(x: first.x, y: height))
        path.closeSubpath()
        return path
    }
}

import SwiftUI
import AppKit

/// Renders a tiny 24-hour activity sparkline as a menu bar image.
struct MenuBarSparkline: View {
    let hourCounts: [String: Int]

    var body: some View {
        Image(nsImage: Self.cachedSparkline(for: hourCounts))
            .renderingMode(.template)
            .accessibilityLabel("24-hour activity")
    }

    // MARK: - Cache

    private static var cachedImage: NSImage?
    private static var cachedHash: Int = 0

    private static func cachedSparkline(for hourCounts: [String: Int]) -> NSImage {
        let hash = dataHash(hourCounts)
        if let cached = cachedImage, cachedHash == hash {
            return cached
        }
        let image = renderSparkline(hourCounts: hourCounts)
        cachedImage = image
        cachedHash = hash
        return image
    }

    static func dataHash(_ hourCounts: [String: Int]) -> Int {
        var hasher = Hasher()
        for hour in 0..<24 {
            hasher.combine(hourCounts[String(hour)] ?? 0)
        }
        return hasher.finalize()
    }

    // MARK: - Render

    private static func renderSparkline(hourCounts: [String: Int]) -> NSImage {
        let width: CGFloat = 36
        let height: CGFloat = 11
        let barCount = 24
        let gap: CGFloat = 0.25
        let barWidth: CGFloat = (width - gap * CGFloat(barCount - 1)) / CGFloat(barCount)

        let counts = (0..<barCount).map { hourCounts[String($0)] ?? 0 }
        let maxCount = counts.max() ?? 0

        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            let color = NSColor.labelColor

            for (i, count) in counts.enumerated() {
                let x = CGFloat(i) * (barWidth + gap)
                let barHeight: CGFloat
                if maxCount > 0 && count > 0 {
                    barHeight = max(1, (CGFloat(count) / CGFloat(maxCount)) * height)
                } else {
                    barHeight = 0
                }
                if barHeight > 0 {
                    let barRect = NSRect(x: x, y: rect.height - barHeight, width: barWidth, height: barHeight)
                    color.setFill()
                    NSBezierPath(rect: barRect).fill()
                }
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}

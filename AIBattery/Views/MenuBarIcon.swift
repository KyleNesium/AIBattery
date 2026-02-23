import SwiftUI
import AppKit

struct MenuBarIcon: View {
    let requestsPercent: Double

    /// Cache key: which color band the percentage falls into.
    /// Only re-renders the icon when the band changes (4 bands total).
    private var colorBand: Int {
        switch requestsPercent {
        case ..<50: return 0
        case ..<80: return 1
        case ..<95: return 2
        default: return 3
        }
    }

    var body: some View {
        Image(nsImage: Self.cachedIcon(for: requestsPercent, band: colorBand))
    }

    // MARK: - Icon cache

    /// Cached icons keyed by (band, colorblindMode) — at most 8 entries.
    private static var iconCache: [Int: NSImage] = [:]
    private static var cachedColorblindFlag: Bool = ThemeColors.isColorblind

    private static func cachedIcon(for percent: Double, band: Int) -> NSImage {
        // Invalidate cache if colorblind mode changed
        if cachedColorblindFlag != ThemeColors.isColorblind {
            iconCache.removeAll()
            cachedColorblindFlag = ThemeColors.isColorblind
        }
        if let cached = iconCache[band] { return cached }
        let icon = renderIcon(percent: percent)
        iconCache[band] = icon
        return icon
    }

    private static func renderIcon(percent: Double) -> NSImage {
        let size: CGFloat = 16
        let image = NSImage(size: NSSize(width: size, height: size))

        image.lockFocus()

        let color = ThemeColors.barNSColor(percent: percent)

        // Draw a small AI sparkle/star icon — 4-pointed star
        let center = NSPoint(x: size / 2, y: size / 2)
        let outerRadius: CGFloat = 6.5
        let innerRadius: CGFloat = 2.0

        let path = NSBezierPath()

        // 4-pointed star: alternate outer and inner points
        for i in 0..<8 {
            let angle = (CGFloat(i) * .pi / 4) - (.pi / 2) // Start from top
            let radius = i % 2 == 0 ? outerRadius : innerRadius
            let point = NSPoint(
                x: center.x + radius * cos(angle),
                y: center.y + radius * sin(angle)
            )
            if i == 0 {
                path.move(to: point)
            } else {
                path.line(to: point)
            }
        }
        path.close()

        // Fill the star with the usage color
        color.setFill()
        path.fill()

        // Subtle outline for definition
        color.withAlphaComponent(0.6).setStroke()
        path.lineWidth = 0.5
        path.stroke()

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

}

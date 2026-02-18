import SwiftUI
import AppKit

struct MenuBarIcon: View {
    let requestsPercent: Double

    var body: some View {
        Image(nsImage: renderIcon())
    }

    private func renderIcon() -> NSImage {
        let size: CGFloat = 16
        let image = NSImage(size: NSSize(width: size, height: size))

        image.lockFocus()

        let color = colorForPercent(requestsPercent)

        // Draw a small AI sparkle/star icon — 4-pointed star
        // This mimics the AI sparkle icons used by Apple and others
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

    private func colorForPercent(_ percent: Double) -> NSColor {
        switch percent {
        case 0..<50: return NSColor.systemGreen
        case 50..<80: return NSColor.systemYellow
        case 80..<95: return NSColor.systemOrange
        default: return NSColor.systemRed
        }
    }
}

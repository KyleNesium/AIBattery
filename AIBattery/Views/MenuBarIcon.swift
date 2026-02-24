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

    /// Cached icons keyed by (band, colorblindMode, highContrast, appearance) — bounded.
    private static var iconCache: [Int: NSImage] = [:]
    private static var cachedColorblindFlag: Bool = ThemeColors.isColorblind
    private static var cachedHighContrastFlag: Bool = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    private static var cachedAppearanceName: String = NSApp.effectiveAppearance.name.rawValue

    private static func cachedIcon(for percent: Double, band: Int) -> NSImage {
        let highContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        let appearance = NSApp.effectiveAppearance.name.rawValue

        // Invalidate cache if accessibility or appearance state changed
        if cachedColorblindFlag != ThemeColors.isColorblind
            || cachedHighContrastFlag != highContrast
            || cachedAppearanceName != appearance {
            iconCache.removeAll()
            cachedColorblindFlag = ThemeColors.isColorblind
            cachedHighContrastFlag = highContrast
            cachedAppearanceName = appearance
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
        let highContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        let isDarkMode = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

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

        // Outline for definition — stronger in high contrast or light mode
        // to ensure the colored icon remains visible against any menu bar background.
        if highContrast {
            NSColor.black.withAlphaComponent(0.8).setStroke()
            path.lineWidth = 1.0
        } else if !isDarkMode {
            NSColor.black.withAlphaComponent(0.3).setStroke()
            path.lineWidth = 0.75
        } else {
            color.withAlphaComponent(0.6).setStroke()
            path.lineWidth = 0.5
        }
        path.stroke()

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

}

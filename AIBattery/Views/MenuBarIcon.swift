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

    /// Returns the cached status bar NSImage for a given percentage.
    /// Used by StatusBarManager for native AppKit button rendering.
    static func statusBarImage(for percent: Double) -> NSImage {
        let band: Int
        switch percent {
        case ..<50: band = 0
        case ..<80: band = 1
        case ..<95: band = 2
        default: band = 3
        }
        return cachedIcon(for: percent, band: band)
    }

    private static func cachedIcon(for percent: Double, band: Int) -> NSImage {
        let highContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        let currentAppearance = NSApp.effectiveAppearance
        let appearanceName = currentAppearance.name.rawValue

        // Invalidate cache if accessibility or appearance state changed
        if cachedColorblindFlag != ThemeColors.isColorblind
            || cachedHighContrastFlag != highContrast
            || cachedAppearanceName != appearanceName {
            iconCache.removeAll()
            cachedColorblindFlag = ThemeColors.isColorblind
            cachedHighContrastFlag = highContrast
            cachedAppearanceName = appearanceName
        }
        if let cached = iconCache[band] { return cached }
        let isDarkMode = currentAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let icon = renderIcon(percent: percent, highContrast: highContrast, isDarkMode: isDarkMode)
        iconCache[band] = icon
        return icon
    }

    private static func renderIcon(percent: Double, highContrast: Bool, isDarkMode: Bool) -> NSImage {
        let size: CGFloat = 16
        let color = ThemeColors.barNSColor(percent: percent)

        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
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

            // Subtle glow behind the star
            let glowColor = color.withAlphaComponent(0.35)
            let shadow = NSShadow()
            shadow.shadowColor = glowColor
            shadow.shadowBlurRadius = 2.5
            shadow.shadowOffset = .zero

            NSGraphicsContext.saveGraphicsState()
            shadow.set()
            color.setFill()
            path.fill()
            NSGraphicsContext.restoreGraphicsState()

            // Fill the star with the usage color (crisp, on top of glow)
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

            return true
        }
        image.isTemplate = false
        return image
    }

}

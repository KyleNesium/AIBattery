import SwiftUI
import AppKit

struct MenuBarIcon: View {
    let requestsPercent: Double

    var body: some View {
        Image(nsImage: Self.cachedIcon(for: requestsPercent))
    }

    // MARK: - Icon cache

    /// Cached icons keyed by quantized percent (every 5%, 21 entries max per appearance state).
    private static var iconCache: [Int: NSImage] = [:]
    private static var cachedColorblindFlag: Bool = ThemeColors.isColorblind
    private static var cachedHighContrastFlag: Bool = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    private static var cachedAppearanceName: String = NSApp.effectiveAppearance.name.rawValue

    /// Returns the cached status bar NSImage for a given percentage.
    /// Used by StatusBarManager for native AppKit button rendering.
    static func statusBarImage(for percent: Double) -> NSImage {
        cachedIcon(for: percent)
    }

    /// Quantize percent to nearest 5% for cache key (0, 5, 10, ... 100).
    static func quantizedPercent(for percent: Double) -> Int {
        min(Int((percent / 5).rounded()) * 5, 100)
    }

    private static func cachedIcon(for percent: Double) -> NSImage {
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
        let key = quantizedPercent(for: percent)
        if let cached = iconCache[key] { return cached }
        let isDarkMode = currentAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let icon = renderIcon(percent: percent, highContrast: highContrast, isDarkMode: isDarkMode)
        iconCache[key] = icon
        return icon
    }

    private static func renderIcon(percent: Double, highContrast: Bool, isDarkMode: Bool) -> NSImage {
        let size: CGFloat = 16
        let color = ThemeColors.barNSColor(percent: percent)

        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
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

            // Fill height: maps percentage to star's vertical extent.
            // In flipped=false coordinates, y increases upward.
            let starBottom: CGFloat = center.y - outerRadius  // 1.5
            let starTop: CGFloat = center.y + outerRadius      // 14.5
            let fillY = starBottom + (starTop - starBottom) * CGFloat(min(max(percent, 0), 100) / 100)

            // 1. Track star — dim outline showing the "empty" portion
            let trackColor: NSColor = isDarkMode
                ? NSColor.white.withAlphaComponent(0.15)
                : NSColor.black.withAlphaComponent(0.10)
            trackColor.setFill()
            path.fill()

            // 2. Clipped fill — liquid gauge rising from bottom
            if percent > 0 {
                NSGraphicsContext.saveGraphicsState()
                path.addClip()

                // Glow behind the filled portion
                let glowColor = color.withAlphaComponent(0.35)
                let shadow = NSShadow()
                shadow.shadowColor = glowColor
                shadow.shadowBlurRadius = 2.5
                shadow.shadowOffset = .zero
                shadow.set()

                let fillRect = NSRect(x: 0, y: 0, width: size, height: fillY)
                color.setFill()
                fillRect.fill()

                NSGraphicsContext.restoreGraphicsState()

                // Crisp fill on top (no shadow, within clip)
                NSGraphicsContext.saveGraphicsState()
                path.addClip()
                color.setFill()
                fillRect.fill()
                NSGraphicsContext.restoreGraphicsState()
            }

            // 3. Outline stroke for definition
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

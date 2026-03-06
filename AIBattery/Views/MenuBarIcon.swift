import SwiftUI
import AppKit

struct MenuBarIcon: View {
    let requestsPercent: Double
    let isBroken: Bool
    let pulseStep: Int

    init(requestsPercent: Double, isBroken: Bool = false, pulseStep: Int = 0) {
        self.requestsPercent = requestsPercent
        self.isBroken = isBroken
        self.pulseStep = pulseStep
    }

    var body: some View {
        Image(nsImage: Self.cachedIcon(for: requestsPercent, isBroken: isBroken, pulseStep: pulseStep))
    }

    // MARK: - Glow parameters

    /// Glow blur radius interpolated from usage percentage.
    static func glowBlur(for percent: Double) -> CGFloat {
        switch percent {
        case ..<30: return 1.0
        case ..<60: return 1.5
        case ..<80: return 2.5
        case ..<95: return 3.5
        default: return 4.5
        }
    }

    /// Glow alpha interpolated from usage percentage.
    static func glowAlpha(for percent: Double) -> CGFloat {
        switch percent {
        case ..<30: return 0.15
        case ..<60: return 0.25
        case ..<80: return 0.35
        case ..<95: return 0.45
        default: return 0.55
        }
    }

    // MARK: - Cache key

    /// Quantized percent for cache key (every 5%, 0–100 → 21 buckets).
    static func quantizedPercent(_ percent: Double) -> Int {
        let clamped = min(max(percent, 0), 100)
        return Int((clamped / 5).rounded(.down)) * 5
    }

    /// Composite cache key encoding quantized percent, broken flag, and pulse step.
    /// Normal: 21 entries (0, 5, 10, ..., 100). Broken: 8 pulse steps × 1 = 8 entries.
    /// Total max: 29 entries per accessibility/appearance state.
    static func cacheKey(quantizedPercent: Int, isBroken: Bool, pulseStep: Int) -> Int {
        if isBroken {
            return 1000 + pulseStep  // 1000–1007
        }
        return quantizedPercent  // 0–100 in steps of 5
    }

    // MARK: - Icon cache

    private static var iconCache: [Int: NSImage] = [:]
    private static var cachedColorblindFlag: Bool = ThemeColors.isColorblind
    private static var cachedHighContrastFlag: Bool = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    private static var cachedAppearanceName: String = NSApp.effectiveAppearance.name.rawValue

    /// Returns the cached status bar NSImage for a given percentage.
    /// Used by StatusBarManager for native AppKit button rendering.
    static func statusBarImage(for percent: Double, isBroken: Bool = false, pulseStep: Int = 0) -> NSImage {
        cachedIcon(for: percent, isBroken: isBroken, pulseStep: pulseStep)
    }

    static func cachedIcon(for percent: Double, isBroken: Bool, pulseStep: Int) -> NSImage {
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

        let qPercent = quantizedPercent(percent)
        let key = cacheKey(quantizedPercent: qPercent, isBroken: isBroken, pulseStep: pulseStep)
        if let cached = iconCache[key] { return cached }

        let isDarkMode = currentAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let icon: NSImage
        if isBroken {
            icon = renderBrokenIcon(pulseStep: pulseStep, highContrast: highContrast, isDarkMode: isDarkMode)
        } else {
            icon = renderIcon(percent: percent, highContrast: highContrast, isDarkMode: isDarkMode)
        }
        iconCache[key] = icon
        return icon
    }

    // MARK: - Normal star rendering

    static func renderIcon(percent: Double, highContrast: Bool, isDarkMode: Bool) -> NSImage {
        let size: CGFloat = 16
        let color = ThemeColors.barNSColor(percent: percent)
        let blur = glowBlur(for: percent)
        let alpha = glowAlpha(for: percent)

        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            let center = NSPoint(x: size / 2, y: size / 2)
            let outerRadius: CGFloat = 6.5
            let innerRadius: CGFloat = 2.0

            let path = starPath(center: center, outerRadius: outerRadius, innerRadius: innerRadius)

            // Glow behind the star — intensity scales with usage
            let glowColor = color.withAlphaComponent(alpha)
            let shadow = NSShadow()
            shadow.shadowColor = glowColor
            shadow.shadowBlurRadius = blur
            shadow.shadowOffset = .zero

            NSGraphicsContext.saveGraphicsState()
            shadow.set()
            color.setFill()
            path.fill()
            NSGraphicsContext.restoreGraphicsState()

            // Fill the star with the usage color (crisp, on top of glow)
            color.setFill()
            path.fill()

            // Outline for definition
            drawStroke(path: path, color: color, highContrast: highContrast, isDarkMode: isDarkMode)

            return true
        }
        image.isTemplate = false
        return image
    }

    // MARK: - Broken star rendering (throttled)

    static func renderBrokenIcon(pulseStep: Int, highContrast: Bool, isDarkMode: Bool) -> NSImage {
        let size: CGFloat = 16
        let color = ThemeColors.barNSColor(percent: 100) // Always red/critical band

        // Pulse modulation from step (0–7 → 0.0–1.0 sine wave)
        let phase = CGFloat(pulseStep) / 8.0
        let sine = (sin(phase * 2 * .pi - .pi / 2) + 1) / 2 // 0.0–1.0
        let pulseAlpha: CGFloat = 0.25 + sine * 0.40    // 0.25–0.65
        let pulseBlur: CGFloat = 2.5 + sine * 2.5       // 2.5–5.0

        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            let center = NSPoint(x: size / 2, y: size / 2)
            let outerRadius: CGFloat = 6.5
            let innerRadius: CGFloat = 2.0
            let fragmentOffset: CGFloat = 1.5

            let fragments = brokenStarFragments(
                center: center,
                outerRadius: outerRadius,
                innerRadius: innerRadius,
                offset: fragmentOffset
            )

            // Draw each fragment with pulsing glow
            let glowColor = color.withAlphaComponent(pulseAlpha)
            let shadow = NSShadow()
            shadow.shadowColor = glowColor
            shadow.shadowBlurRadius = pulseBlur
            shadow.shadowOffset = .zero

            for fragment in fragments {
                NSGraphicsContext.saveGraphicsState()
                shadow.set()
                color.setFill()
                fragment.fill()
                NSGraphicsContext.restoreGraphicsState()

                color.setFill()
                fragment.fill()

                drawStroke(path: fragment, color: color, highContrast: highContrast, isDarkMode: isDarkMode)
            }

            return true
        }
        image.isTemplate = false
        return image
    }

    // MARK: - Geometry helpers

    /// 4-pointed star path: 8 vertices alternating outer/inner radius.
    static func starPath(center: NSPoint, outerRadius: CGFloat, innerRadius: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        for i in 0..<8 {
            let angle = (CGFloat(i) * .pi / 4) - (.pi / 2)
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
        return path
    }

    /// 4 triangular fragments of the star, each offset outward from center.
    /// Each point of the 4-pointed star forms a triangle: the outer tip + the two adjacent inner vertices.
    static func brokenStarFragments(
        center: NSPoint,
        outerRadius: CGFloat,
        innerRadius: CGFloat,
        offset: CGFloat
    ) -> [NSBezierPath] {
        // Star has 4 outer points at indices 0, 2, 4, 6 (angles: -π/2, 0, π/2, π)
        // and 4 inner points at indices 1, 3, 5, 7
        var vertices: [NSPoint] = []
        for i in 0..<8 {
            let angle = (CGFloat(i) * .pi / 4) - (.pi / 2)
            let radius = i % 2 == 0 ? outerRadius : innerRadius
            vertices.append(NSPoint(
                x: center.x + radius * cos(angle),
                y: center.y + radius * sin(angle)
            ))
        }

        var fragments: [NSBezierPath] = []
        // Each fragment: outer vertex at index 2*k, inner vertices at 2*k-1 and 2*k+1
        for k in 0..<4 {
            let outerIdx = k * 2
            let prevInner = (outerIdx + 7) % 8 // wraps around
            let nextInner = (outerIdx + 1) % 8

            // Direction from center to outer point — offset along this
            let outerAngle = (CGFloat(outerIdx) * .pi / 4) - (.pi / 2)
            let dx = offset * cos(outerAngle)
            let dy = offset * sin(outerAngle)

            let path = NSBezierPath()
            path.move(to: NSPoint(x: vertices[outerIdx].x + dx, y: vertices[outerIdx].y + dy))
            path.line(to: NSPoint(x: vertices[prevInner].x + dx, y: vertices[prevInner].y + dy))
            path.line(to: NSPoint(x: vertices[nextInner].x + dx, y: vertices[nextInner].y + dy))
            path.close()
            fragments.append(path)
        }

        return fragments
    }

    /// Shared stroke drawing for consistent outline across normal and broken states.
    private static func drawStroke(path: NSBezierPath, color: NSColor, highContrast: Bool, isDarkMode: Bool) {
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
    }

}

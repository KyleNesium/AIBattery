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
        Image(nsImage: Self.cachedIcon(
            for: requestsPercent,
            color: ThemeColors.barNSColor(percent: requestsPercent),
            isBroken: isBroken,
            isSparkle: false,
            pulseStep: pulseStep
        ))
    }

    // MARK: - Constants

    /// Icon canvas size — larger than the star to give the glow room to breathe.
    static let iconSize: CGFloat = 22

    /// Number of discrete pulse steps per breathing cycle.
    /// 8 steps at 4s cycle = 500ms per tick — smooth enough to appear fluid
    /// while halving CPU usage from timer wakeups and image generation.
    static let pulseSteps = 8

    // MARK: - Glow breath parameters

    /// Star scale range (min, max) for the breathing animation.
    /// The star itself grows and shrinks. Higher usage = bigger breath.
    /// Only called for percent >= 30 (below that, sparkle mode is used instead).
    static func starScaleRange(for percent: Double) -> (min: CGFloat, max: CGFloat) {
        switch percent {
        case ..<60:  return (1.00, 1.08)
        case ..<80:  return (1.00, 1.10)
        case ..<95:  return (1.00, 1.12)
        default:     return (1.00, 1.14)
        }
    }

    /// Glow halo alpha range (min, max) for the soft aura behind the star.
    /// Only called for percent >= 30 (below that, sparkle mode is used instead).
    static func glowAlphaRange(for percent: Double) -> (min: CGFloat, max: CGFloat) {
        switch percent {
        case ..<60:  return (0.0, 0.12)
        case ..<80:  return (0.05, 0.18)
        case ..<95:  return (0.08, 0.25)
        default:     return (0.12, 0.32)
        }
    }

    /// Sine-wave breath factor (0.0–1.0) from a discrete pulse step.
    static func breathFactor(for step: Int) -> CGFloat {
        let phase = CGFloat(step) / CGFloat(pulseSteps)
        return (sin(phase * 2 * .pi - .pi / 2) + 1) / 2
    }

    // MARK: - Cache key

    /// Quantized percent for cache key (every 5%, 0–100 → 21 buckets).
    static func quantizedPercent(_ percent: Double) -> Int {
        let clamped = min(max(percent, 0), 100)
        return Int((clamped / 5).rounded(.down)) * 5
    }

    /// Composite cache key: quantized percent × 100 + pulseStep for normal,
    /// 10_100 + pulseStep for broken, 10_200 + pulseStep for sparkle.
    /// Max entries: 21×8 + 8 + 8 = 184.
    static func cacheKey(quantizedPercent: Int, isBroken: Bool, isSparkle: Bool, pulseStep: Int) -> Int {
        if isBroken {
            return 10_100 + pulseStep
        }
        if isSparkle {
            return 10_200 + pulseStep
        }
        return quantizedPercent * 100 + pulseStep
    }

    // MARK: - Icon cache

    private static let cacheLock = NSLock()
    private static var iconCache: [Int: NSImage] = [:]
    private static var cachedColorblindFlag: Bool = ThemeColors.isColorblind
    private static var cachedHighContrastFlag: Bool = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    private static var cachedAppearanceName: String = NSApp?.effectiveAppearance.name.rawValue ?? ""

    /// Observe accessibility changes instead of polling every frame.
    /// Registered lazily on first icon render. Appearance (light/dark) is already
    /// checked per-call via `cachedAppearanceName` (cheap string compare).
    private static var accessibilityObserverRegistered = false

    private static func registerAccessibilityObserverIfNeeded() {
        guard !accessibilityObserverRegistered else { return }
        accessibilityObserverRegistered = true

        let ws = NSWorkspace.shared
        ws.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil, queue: .main
        ) { _ in
            cacheLock.withLock {
                cachedHighContrastFlag = ws.accessibilityDisplayShouldIncreaseContrast
                iconCache.removeAll()
            }
        }
    }

    /// Returns the cached status bar NSImage. Color is provided by the caller so it can
    /// match the active metric mode (rate limit thresholds vs context health thresholds).
    /// `isSparkle` triggers the recovery sparkle effect (30s after throttle clears).
    static func statusBarImage(for percent: Double, color: NSColor, isBroken: Bool = false, isSparkle: Bool = false, pulseStep: Int = 0) -> NSImage {
        cachedIcon(for: percent, color: color, isBroken: isBroken, isSparkle: isSparkle, pulseStep: pulseStep)
    }

    static func cachedIcon(for percent: Double, color: NSColor, isBroken: Bool, isSparkle: Bool, pulseStep: Int) -> NSImage {
        registerAccessibilityObserverIfNeeded()

        let currentAppearance = NSApp?.effectiveAppearance
        let appearanceName = currentAppearance?.name.rawValue ?? ""

        return cacheLock.withLock {
            if cachedColorblindFlag != ThemeColors.isColorblind
                || cachedAppearanceName != appearanceName {
                iconCache.removeAll()
                cachedColorblindFlag = ThemeColors.isColorblind
                cachedAppearanceName = appearanceName
            }

            let qPercent = quantizedPercent(percent)
            let key = cacheKey(quantizedPercent: qPercent, isBroken: isBroken, isSparkle: isSparkle, pulseStep: pulseStep)
            if let cached = iconCache[key] { return cached }

            let highContrast = cachedHighContrastFlag
            let isDarkMode = currentAppearance?.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let icon: NSImage
            if isBroken {
                icon = renderBrokenIcon(color: color, pulseStep: pulseStep, highContrast: highContrast, isDarkMode: isDarkMode)
            } else if isSparkle {
                icon = renderSparkleIcon(color: color, pulseStep: pulseStep, highContrast: highContrast, isDarkMode: isDarkMode)
            } else {
                icon = renderIcon(percent: percent, color: color, pulseStep: pulseStep, highContrast: highContrast, isDarkMode: isDarkMode)
            }
            iconCache[key] = icon
            return icon
        }
    }

    // MARK: - Normal star rendering

    static func renderIcon(percent: Double, color: NSColor, pulseStep: Int, highContrast: Bool, isDarkMode: Bool) -> NSImage {
        let size = iconSize
        let breath = breathFactor(for: pulseStep)
        let scaleRange = starScaleRange(for: percent)
        let alphaRange = glowAlphaRange(for: percent)

        let starScale = scaleRange.min + (scaleRange.max - scaleRange.min) * breath
        let haloAlpha = alphaRange.min + (alphaRange.max - alphaRange.min) * breath

        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let center = NSPoint(x: size / 2, y: size / 2)
            let outerRadius: CGFloat = 6.5
            let innerRadius: CGFloat = 2.0

            // Soft halo — faint circle just behind the star tips
            if haloAlpha > 0.01 {
                let haloR = outerRadius * starScale * 1.15
                let rect = CGRect(x: center.x - haloR, y: center.y - haloR, width: haloR * 2, height: haloR * 2)
                ctx.setFillColor(color.withAlphaComponent(haloAlpha).cgColor)
                ctx.fillEllipse(in: rect)
            }

            // Breathing star — the star itself scales up and down
            let path = starPath(
                center: center,
                outerRadius: outerRadius * starScale,
                innerRadius: innerRadius * starScale
            )
            ctx.setFillColor(color.cgColor)
            ctx.addPath(path.asCGPath)
            ctx.fillPath()

            // Outline
            drawStroke(ctx: ctx, path: path.asCGPath, color: color, highContrast: highContrast, isDarkMode: isDarkMode)

            return true
        }
        image.isTemplate = false
        return image
    }

    // MARK: - Broken star rendering (throttled)

    static func renderBrokenIcon(color: NSColor, pulseStep: Int, highContrast: Bool, isDarkMode: Bool) -> NSImage {
        let size = iconSize
        let breath = breathFactor(for: pulseStep)

        // Broken star breathes more dramatically
        let fragmentScale: CGFloat = 1.0 + breath * 0.14  // 1.0–1.14
        let haloAlpha: CGFloat = 0.15 + breath * 0.30     // 0.15–0.45

        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let center = NSPoint(x: size / 2, y: size / 2)
            let outerRadius: CGFloat = 6.5
            let innerRadius: CGFloat = 2.0
            let fragmentOffset: CGFloat = 1.5

            // Soft halo behind fragments
            let haloR = outerRadius * fragmentScale * 1.15
            let rect = CGRect(x: center.x - haloR, y: center.y - haloR, width: haloR * 2, height: haloR * 2)
            ctx.setFillColor(color.withAlphaComponent(haloAlpha).cgColor)
            ctx.fillEllipse(in: rect)

            // Broken fragments on top — also breathe
            let fragments = brokenStarFragments(
                center: center,
                outerRadius: outerRadius * fragmentScale,
                innerRadius: innerRadius * fragmentScale,
                offset: fragmentOffset
            )

            for fragment in fragments {
                let cgPath = fragment.asCGPath
                ctx.setFillColor(color.cgColor)
                ctx.addPath(cgPath)
                ctx.fillPath()
                drawStroke(ctx: ctx, path: cgPath, color: color, highContrast: highContrast, isDarkMode: isDarkMode)
            }

            return true
        }
        image.isTemplate = false
        return image
    }

    // MARK: - Sparkle star rendering (green / healthy)

    /// Pre-computed sparkle positions: angle (radians) and distance from center.
    /// 8 sparkles arranged around the star — close enough to be visible at menu bar size.
    private static let sparklePositions: [(angle: CGFloat, dist: CGFloat)] = [
        (0.0,   8.2),   // right
        (0.8,   8.8),   // upper right
        (1.57,  8.0),   // top
        (2.4,   8.6),   // upper left
        (3.14,  8.2),   // left
        (3.9,   8.8),   // lower left
        (4.71,  8.0),   // bottom
        (5.5,   8.6),   // lower right
    ]

    /// Each pulse step shows a different subset of sparkles (indices into sparklePositions).
    /// 8 unique frames with 2-3 sparkles each — celebratory twinkling for recovery.
    /// 8 frames with 2-3 sparkles each — celebratory twinkling for recovery.
    private static let sparkleFrames: [[Int]] = [
        [0, 4],     [1, 5],     [2, 6],     [3, 7],
        [0, 3, 6],  [1, 5],     [2, 4, 7],  [0, 6],
    ]

    static func renderSparkleIcon(color: NSColor, pulseStep: Int, highContrast: Bool, isDarkMode: Bool) -> NSImage {
        let size = iconSize

        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let center = NSPoint(x: size / 2, y: size / 2)
            let outerRadius: CGFloat = 6.5
            let innerRadius: CGFloat = 2.0

            // Draw the star at normal size (no breathing — green is calm)
            let path = starPath(center: center, outerRadius: outerRadius, innerRadius: innerRadius)
            ctx.setFillColor(color.cgColor)
            ctx.addPath(path.asCGPath)
            ctx.fillPath()
            drawStroke(ctx: ctx, path: path.asCGPath, color: color, highContrast: highContrast, isDarkMode: isDarkMode)

            // Draw sparkles — subtle cross shapes that slowly twinkle around the star
            let frameIndex = (pulseStep / 2) % sparkleFrames.count
            let activeIndices = sparkleFrames[frameIndex]

            for idx in activeIndices {
                let pos = sparklePositions[idx]
                let sx = center.x + pos.dist * cos(pos.angle)
                let sy = center.y + pos.dist * sin(pos.angle)

                // Draw a simple + cross (2 perpendicular lines) — renders crisply at small sizes
                let arm: CGFloat = 1.6
                ctx.setStrokeColor(color.withAlphaComponent(0.7).cgColor)
                ctx.setLineWidth(0.7)
                ctx.move(to: CGPoint(x: sx - arm, y: sy))
                ctx.addLine(to: CGPoint(x: sx + arm, y: sy))
                ctx.move(to: CGPoint(x: sx, y: sy - arm))
                ctx.addLine(to: CGPoint(x: sx, y: sy + arm))
                ctx.strokePath()
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
    static func brokenStarFragments(
        center: NSPoint,
        outerRadius: CGFloat,
        innerRadius: CGFloat,
        offset: CGFloat
    ) -> [NSBezierPath] {
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
        for k in 0..<4 {
            let outerIdx = k * 2
            let prevInner = (outerIdx + 7) % 8
            let nextInner = (outerIdx + 1) % 8

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

    /// Shared stroke drawing via CGContext.
    private static func drawStroke(ctx: CGContext, path: CGPath, color: NSColor, highContrast: Bool, isDarkMode: Bool) {
        if highContrast {
            ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.8).cgColor)
            ctx.setLineWidth(1.0)
        } else if !isDarkMode {
            ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.3).cgColor)
            ctx.setLineWidth(0.75)
        } else {
            ctx.setStrokeColor(color.withAlphaComponent(0.6).cgColor)
            ctx.setLineWidth(0.5)
        }
        ctx.addPath(path)
        ctx.strokePath()
    }

}

// MARK: - NSBezierPath → CGPath

extension NSBezierPath {
    /// Converts an NSBezierPath to a CGPath for use with CGContext drawing.
    /// macOS 14+ has a native `.cgPath` — this provides the same for macOS 13.
    var asCGPath: CGPath {
        if #available(macOS 14.0, *) {
            return cgPath
        }
        let path = CGMutablePath()
        var points = [CGPoint](repeating: .zero, count: 3)
        for i in 0..<elementCount {
            let type = element(at: i, associatedPoints: &points)
            switch type {
            case .moveTo: path.move(to: points[0])
            case .lineTo: path.addLine(to: points[0])
            case .curveTo: path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .closePath: path.closeSubpath()
            case .cubicCurveTo: path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .quadraticCurveTo: path.addQuadCurve(to: points[1], control: points[0])
            @unknown default: break
            }
        }
        return path
    }
}

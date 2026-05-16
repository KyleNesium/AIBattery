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
    static let iconSize: CGFloat = Layout.iconSize

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
        case ..<60: (1.00, 1.08)
        case ..<80: (1.00, 1.10)
        case ..<95: (1.00, 1.12)
        default: (1.00, 1.14)
        }
    }

    /// Glow halo alpha range (min, max) for the soft aura behind the star.
    /// Below 80% no halo is drawn (timer is stopped, static icon only).
    static func glowAlphaRange(for percent: Double) -> (min: CGFloat, max: CGFloat) {
        switch percent {
        case ..<80: (0.0, 0.0)
        case ..<95: (0.08, 0.25)
        default: (0.12, 0.32)
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

    /// Composite cache key incorporating percent, color, state, and pulse step.
    /// Color hash distinguishes the same percent across metric modes
    /// (e.g. rate limit green vs context health yellow at 75%).
    /// Max entries: 21×8 + 8 + 8 = 184 per color variant.
    static func cacheKey(quantizedPercent: Int, colorHash: Int, isBroken: Bool, isSparkle: Bool, pulseStep: Int) -> Int {
        if isBroken {
            return 10_100 + pulseStep + colorHash &* 100_000
        }
        if isSparkle {
            return 10_200 + pulseStep + colorHash &* 100_000
        }
        return quantizedPercent * 100 + pulseStep + colorHash &* 100_000
    }

    // MARK: - Icon cache

    private static let cacheLock = NSLock()
    private static var iconCache: [Int: NSImage] = [:]
    private static var cachedColorblindFlag: Bool = ThemeColors.isColorblind
    private static var cachedAppearanceName: String = ""

    /// Returns the cached status bar NSImage. Color is provided by the caller so it can
    /// match the active metric mode (rate limit thresholds vs context health thresholds).
    /// `isSparkle` triggers the recovery sparkle effect (30s after throttle clears).
    /// Inset to trim left-side canvas padding so the icon sits tight against the title text.
    /// macOS battery has ~1pt between text and icon; our 22pt canvas has ~4pt whitespace on each side.
    private static let iconAlignmentInsets = NSEdgeInsets(top: 0, left: 1, bottom: 0, right: 5)

    static func statusBarImage(for percent: Double, color: NSColor, isBroken: Bool = false, isSparkle: Bool = false, pulseStep: Int = 0, menuBarAppearance: NSAppearance? = nil) -> NSImage {
        cachedIcon(for: percent, color: color, isBroken: isBroken, isSparkle: isSparkle, pulseStep: pulseStep, menuBarAppearance: menuBarAppearance)
    }

    /// Horizontal whitespace trimmed from each side of the `iconSize` canvas when
    /// compositing into `combinedStatusBarImage`. Larger value = narrower visible icon.
    /// The star's outer vertex (including max breathing) sits at ~center ± 7.5pt, and
    /// the halo at 95%+ reaches ~center ± 8.6pt. Trimming 4pt on each side keeps the
    /// star fully visible and only cuts ~0.6pt off the outer ring of the red-band halo,
    /// which is drawn at < 15% alpha and thus imperceptible.
    private static let iconCanvasPadding: CGFloat = 4

    /// Renders the percentage/countdown text and the star into a single tightly-packed
    /// `NSImage`. Assigning this to `NSStatusBarButton.image` (with `title = ""`) avoids
    /// the bezel padding that AppKit applies around a title + image button layout, giving
    /// the menu bar pill a width matching other system items like Battery and WiFi.
    static func combinedStatusBarImage(
        text: String,
        percent: Double,
        color: NSColor,
        isBroken: Bool = false,
        isSparkle: Bool = false,
        menuBarAppearance: NSAppearance? = nil
    ) -> NSImage {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        // Use the status bar button's appearance — it reflects the actual menu bar
        // backdrop (wallpaper tint, translucency) rather than NSApp.effectiveAppearance
        // which only tracks the system-wide Light/Dark setting.
        let appearance = menuBarAppearance ?? NSApp?.effectiveAppearance
        let isDarkMenuBar = appearance?.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let textColor: NSColor = isDarkMenuBar ? .white : .black
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributed.size()
        let textWidth = ceil(textSize.width)

        let icon = statusBarImage(for: percent, color: color, isBroken: isBroken, isSparkle: isSparkle, pulseStep: 0, menuBarAppearance: menuBarAppearance)
        let canvasSize = icon.size.width // 22pt, contains star + halo with ~3pt padding each side
        let iconVisibleWidth = canvasSize - 2 * iconCanvasPadding
        let gap: CGFloat = 2

        // Total width = text + gap + visible icon. We shift the icon left by its own
        // leading canvas padding so the visible star begins right after `gap`, and
        // trim the trailing canvas padding from the right side the same way.
        let totalWidth = ceil(textWidth + gap + iconVisibleWidth)
        let height = canvasSize

        let image = NSImage(size: NSSize(width: totalWidth, height: height), flipped: false) { _ in
            let textY = (height - ceil(textSize.height)) / 2
            attributed.draw(at: NSPoint(x: 0, y: textY))

            let iconX = textWidth + gap - iconCanvasPadding
            icon.draw(
                at: NSPoint(x: iconX, y: 0),
                from: .zero,
                operation: .sourceOver,
                fraction: 1.0
            )
            return true
        }
        image.isTemplate = false
        return image
    }

    static func cachedIcon(for percent: Double, color: NSColor, isBroken: Bool, isSparkle: Bool, pulseStep: Int, menuBarAppearance: NSAppearance? = nil) -> NSImage {
        let currentAppearance = menuBarAppearance ?? NSApp?.effectiveAppearance
        let appearanceName = currentAppearance?.name.rawValue ?? ""
        let currentColorblind = ThemeColors.isColorblind

        // Check cache under lock; render outside lock to avoid holding it during image creation
        let colorHash = color.hash
        let (key, cached): (Int, NSImage?) = cacheLock.withLock {
            if cachedColorblindFlag != currentColorblind
                || cachedAppearanceName != appearanceName {
                iconCache.removeAll()
                cachedColorblindFlag = currentColorblind
                cachedAppearanceName = appearanceName
            }

            let qPercent = quantizedPercent(percent)
            let k = cacheKey(quantizedPercent: qPercent, colorHash: colorHash, isBroken: isBroken, isSparkle: isSparkle, pulseStep: pulseStep)
            return (k, iconCache[k])
        }

        if let cached { return cached }

        // Render without holding the lock — NSImage creation is thread-safe
        // but can be slow; no need to serialize rendering across threads.
        let icon: NSImage = if isBroken {
            // Throttled: static multi-pointed star at peak intensity (no animation)
            renderThrottledIcon(color: color)
        } else if isSparkle {
            renderSparkleIcon(color: color, pulseStep: pulseStep)
        } else {
            renderIcon(percent: percent, color: color, pulseStep: pulseStep)
        }

        // Bake alignment rect into the icon so statusBarImage can return
        // the cached instance directly without copying on every call.
        icon.alignmentRect = NSRect(
            x: iconAlignmentInsets.left,
            y: iconAlignmentInsets.bottom,
            width: icon.size.width - iconAlignmentInsets.left - iconAlignmentInsets.right,
            height: icon.size.height - iconAlignmentInsets.top - iconAlignmentInsets.bottom
        )
        cacheLock.withLock { iconCache[key] = icon }
        return icon
    }

    // MARK: - Normal star rendering

    static func renderIcon(percent: Double, color: NSColor, pulseStep: Int) -> NSImage {
        let size = iconSize
        let outerRadius: CGFloat = 6.5
        let innerRadius: CGFloat = 2.0

        // Orange band (80–95%): static glow, no breathing animation.
        // Red band (≥95%): breathing pulse continues.
        let isOrangeBand = percent >= 80 && percent < 95
        let breath = isOrangeBand ? CGFloat(0.5) : breathFactor(for: pulseStep)
        let scaleRange = starScaleRange(for: percent)
        let alphaRange = glowAlphaRange(for: percent)

        let starScale = isOrangeBand ? CGFloat(1.0) : scaleRange.min + (scaleRange.max - scaleRange.min) * breath
        let haloAlpha = alphaRange.min + (alphaRange.max - alphaRange.min) * breath

        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let center = NSPoint(x: size / 2, y: size / 2)

            // Glow behind the star — shape depends on severity
            if isOrangeBand {
                // Orange: star-shaped glow directly around the star (no separate halo)
                let glowPath = starPath(
                    center: center,
                    outerRadius: outerRadius * 1.25,
                    innerRadius: innerRadius * 1.25
                )
                ctx.setFillColor(color.withAlphaComponent(0.18).cgColor)
                ctx.addPath(glowPath.asCGPath)
                ctx.fillPath()
            } else if haloAlpha > 0.01 {
                let haloR = outerRadius * starScale * 1.15
                ctx.setFillColor(color.withAlphaComponent(haloAlpha).cgColor)
                if percent >= 95 {
                    // Red band: many-pointed star glow (spiky, aggressive)
                    let glowPath = multiPointStarPath(
                        center: center,
                        outerRadius: haloR,
                        innerRadius: haloR * 0.55,
                        points: 12
                    )
                    ctx.addPath(glowPath.asCGPath)
                    ctx.fillPath()
                } else {
                    // Normal: soft circular halo
                    let rect = CGRect(x: center.x - haloR, y: center.y - haloR, width: haloR * 2, height: haloR * 2)
                    ctx.fillEllipse(in: rect)
                }
            }

            // Star — static for orange band, breathing for others
            let path = starPath(
                center: center,
                outerRadius: outerRadius * starScale,
                innerRadius: innerRadius * starScale
            )
            ctx.setFillColor(color.cgColor)
            ctx.addPath(path.asCGPath)
            ctx.fillPath()

            return true
        }
        image.isTemplate = false
        return image
    }

    // MARK: - Throttled star rendering (static, many-pointed)

    /// Static many-pointed star for throttled state — no animation, no fragments.
    /// Uses a 12-pointed star shape with the normal 4-pointed star overlaid for depth.
    static func renderThrottledIcon(color: NSColor) -> NSImage {
        let size = iconSize
        let outerRadius: CGFloat = 6.5
        let innerRadius: CGFloat = 2.0

        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let center = NSPoint(x: size / 2, y: size / 2)

            // 12-pointed star glow behind (spiky, aggressive)
            let spikyPath = multiPointStarPath(
                center: center,
                outerRadius: outerRadius * 1.3,
                innerRadius: outerRadius * 0.65,
                points: 12
            )
            ctx.setFillColor(color.withAlphaComponent(0.35).cgColor)
            ctx.addPath(spikyPath.asCGPath)
            ctx.fillPath()

            // Normal 4-pointed star on top (solid fill)
            let starFill = starPath(center: center, outerRadius: outerRadius * 1.14, innerRadius: innerRadius * 1.14)
            ctx.setFillColor(color.cgColor)
            ctx.addPath(starFill.asCGPath)
            ctx.fillPath()

            return true
        }
        image.isTemplate = false
        return image
    }

    // MARK: - Sparkle star rendering (green / healthy)

    /// Pre-computed sparkle positions: angle (radians) and distance from center.
    /// 8 sparkles arranged around the star — close enough to be visible at menu bar size.
    private static let sparklePositions: [(angle: CGFloat, dist: CGFloat)] = [
        (0.0, 8.2), // right
        (0.8, 8.8), // upper right
        (1.57, 8.0), // top
        (2.4, 8.6), // upper left
        (3.14, 8.2), // left
        (3.9, 8.8), // lower left
        (4.71, 8.0), // bottom
        (5.5, 8.6), // lower right
    ]

    /// Each pulse step shows a different subset of sparkles (indices into sparklePositions).
    /// 8 frames with 2-3 sparkles each — celebratory twinkling for recovery.
    private static let sparkleFrames: [[Int]] = [
        [0, 4], [1, 5], [2, 6], [3, 7],
        [0, 3, 6], [1, 5], [2, 4, 7], [0, 6],
    ]

    static func renderSparkleIcon(color: NSColor, pulseStep: Int) -> NSImage {
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

    // Geometry helpers and NSBezierPath extension in MenuBarIconGeometry.swift
}

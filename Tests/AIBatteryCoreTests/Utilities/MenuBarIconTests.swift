import Testing
import AppKit
@testable import AIBatteryCore

@Suite("MenuBarIcon")
struct MenuBarIconTests {

    private let testColor: NSColor = .systemGreen

    // MARK: - Breath parameters

    @Test func breathFactor_rangeIsZeroToOne() {
        for step in 0..<MenuBarIcon.pulseSteps {
            let factor = MenuBarIcon.breathFactor(for: step)
            #expect(factor >= 0.0)
            #expect(factor <= 1.0)
        }
    }

    @Test func starScaleRange_increasesWithPercent() {
        let low = MenuBarIcon.starScaleRange(for: 35)
        let high = MenuBarIcon.starScaleRange(for: 99)
        // Min is always 1.0 (base size), max grows with usage
        #expect(low.min == 1.0)
        #expect(high.max > low.max)
    }

    @Test func glowAlphaRange_increasesWithPercent() {
        let low = MenuBarIcon.glowAlphaRange(for: 35)
        let high = MenuBarIcon.glowAlphaRange(for: 99)
        #expect(high.min > low.min)
        #expect(high.max > low.max)
    }

    // MARK: - Quantized percent

    @Test func quantizedPercent_roundsDown() {
        #expect(MenuBarIcon.quantizedPercent(0) == 0)
        #expect(MenuBarIcon.quantizedPercent(4.9) == 0)
        #expect(MenuBarIcon.quantizedPercent(5) == 5)
        #expect(MenuBarIcon.quantizedPercent(7.5) == 5)
        #expect(MenuBarIcon.quantizedPercent(50) == 50)
        #expect(MenuBarIcon.quantizedPercent(99) == 95)
        #expect(MenuBarIcon.quantizedPercent(100) == 100)
    }

    @Test func quantizedPercent_clampsOutOfRange() {
        #expect(MenuBarIcon.quantizedPercent(-5) == 0)
        #expect(MenuBarIcon.quantizedPercent(150) == 100)
    }

    // MARK: - Cache key

    @Test func cacheKey_normalDistinctFromBroken() {
        let normalKey = MenuBarIcon.cacheKey(quantizedPercent: 50, colorHash: 0, isBroken: false, isSparkle: false, pulseStep: 0)
        let brokenKey = MenuBarIcon.cacheKey(quantizedPercent: 50, colorHash: 0, isBroken: true, isSparkle: false, pulseStep: 0)
        #expect(normalKey != brokenKey)
    }

    @Test func cacheKey_normalEncodesPulseStep() {
        let step0 = MenuBarIcon.cacheKey(quantizedPercent: 50, colorHash: 0, isBroken: false, isSparkle: false, pulseStep: 0)
        let step3 = MenuBarIcon.cacheKey(quantizedPercent: 50, colorHash: 0, isBroken: false, isSparkle: false, pulseStep: 3)
        #expect(step0 != step3)
    }

    @Test func cacheKey_differentPercentsAreDistinct() {
        let key0 = MenuBarIcon.cacheKey(quantizedPercent: 0, colorHash: 0, isBroken: false, isSparkle: false, pulseStep: 0)
        let key50 = MenuBarIcon.cacheKey(quantizedPercent: 50, colorHash: 0, isBroken: false, isSparkle: false, pulseStep: 0)
        #expect(key0 != key50)
    }

    @Test func cacheKey_brokenPulseStepsAreDistinct() {
        let step0 = MenuBarIcon.cacheKey(quantizedPercent: 0, colorHash: 0, isBroken: true, isSparkle: false, pulseStep: 0)
        let step4 = MenuBarIcon.cacheKey(quantizedPercent: 0, colorHash: 0, isBroken: true, isSparkle: false, pulseStep: 4)
        let step7 = MenuBarIcon.cacheKey(quantizedPercent: 0, colorHash: 0, isBroken: true, isSparkle: false, pulseStep: 7)
        #expect(step0 != step4)
        #expect(step4 != step7)
    }

    @Test func cacheKey_noCollisionAt100Percent() {
        // 100% normal and broken must not collide (was a bug with *10 + 1000 base)
        for step in 0..<MenuBarIcon.pulseSteps {
            let normalKey = MenuBarIcon.cacheKey(quantizedPercent: 100, colorHash: 0, isBroken: false, isSparkle: false, pulseStep: step)
            let brokenKey = MenuBarIcon.cacheKey(quantizedPercent: 100, colorHash: 0, isBroken: true, isSparkle: false, pulseStep: step)
            #expect(normalKey != brokenKey)
        }
    }

    @Test func cacheKey_sparkleDistinctFromNormalAndBroken() {
        let normalKey = MenuBarIcon.cacheKey(quantizedPercent: 0, colorHash: 0, isBroken: false, isSparkle: false, pulseStep: 0)
        let brokenKey = MenuBarIcon.cacheKey(quantizedPercent: 0, colorHash: 0, isBroken: true, isSparkle: false, pulseStep: 0)
        let sparkleKey = MenuBarIcon.cacheKey(quantizedPercent: 0, colorHash: 0, isBroken: false, isSparkle: true, pulseStep: 0)
        #expect(normalKey != sparkleKey)
        #expect(brokenKey != sparkleKey)
    }

    @Test func cacheKey_differentColorsAreDistinct() {
        let greenKey = MenuBarIcon.cacheKey(quantizedPercent: 75, colorHash: 42, isBroken: false, isSparkle: false, pulseStep: 0)
        let orangeKey = MenuBarIcon.cacheKey(quantizedPercent: 75, colorHash: 99, isBroken: false, isSparkle: false, pulseStep: 0)
        #expect(greenKey != orangeKey)
    }

    // MARK: - Star geometry

    @Test func starPath_has8Vertices() {
        let path = MenuBarIcon.starPath(
            center: NSPoint(x: 8, y: 8),
            outerRadius: 6.5,
            innerRadius: 2.0
        )
        // 1 move + 7 lines + 1 close = 9 elements (macOS 14+: close may add implicit lineTo = 10)
        #expect(path.elementCount >= 9)
        #expect(!path.isEmpty)
    }

    // MARK: - NSBezierPath CGPath conversion

    @Test func asCGPath_convertsCorrectly() {
        let bezier = NSBezierPath()
        bezier.move(to: NSPoint(x: 0, y: 0))
        bezier.line(to: NSPoint(x: 10, y: 0))
        bezier.line(to: NSPoint(x: 5, y: 10))
        bezier.close()
        let cg = bezier.asCGPath
        #expect(!cg.isEmpty)
        #expect(cg.boundingBox.width > 0)
    }

    // MARK: - Rendered icon properties

    @Test func normalIcon_isCorrectSizeNonTemplate() {
        let icon = MenuBarIcon.statusBarImage(for: 50, color: testColor, pulseStep: 0)
        #expect(icon.size.width == MenuBarIcon.iconSize)
        #expect(icon.size.height == MenuBarIcon.iconSize)
        #expect(icon.isTemplate == false)
    }

    @Test func brokenIcon_isCorrectSizeNonTemplate() {
        let icon = MenuBarIcon.statusBarImage(for: 100, color: .systemRed, isBroken: true, pulseStep: 0)
        #expect(icon.size.width == MenuBarIcon.iconSize)
        #expect(icon.size.height == MenuBarIcon.iconSize)
        #expect(icon.isTemplate == false)
    }

    @Test func differentPulseSteps_produceDifferentInstances() {
        let step0 = MenuBarIcon.statusBarImage(for: 50, color: testColor, pulseStep: 0)
        let step4 = MenuBarIcon.statusBarImage(for: 50, color: testColor, pulseStep: 4)
        #expect(step0 !== step4)
    }

    @Test func samePulseStep_returnsSameCachedInstance() {
        let first = MenuBarIcon.statusBarImage(for: 50, color: testColor, pulseStep: 2)
        let second = MenuBarIcon.statusBarImage(for: 50, color: testColor, pulseStep: 2)
        #expect(first === second)
    }

    // MARK: - Sparkle icon (recovery effect)

    @Test func sparkleIcon_isCorrectSizeNonTemplate() {
        let icon = MenuBarIcon.statusBarImage(for: 10, color: .systemGreen, isSparkle: true, pulseStep: 0)
        #expect(icon.size.width == MenuBarIcon.iconSize)
        #expect(icon.size.height == MenuBarIcon.iconSize)
        #expect(icon.isTemplate == false)
    }

    @Test func sparkleIcon_differentStepsProduceDifferentInstances() {
        let step0 = MenuBarIcon.statusBarImage(for: 10, color: .systemGreen, isSparkle: true, pulseStep: 0)
        let step3 = MenuBarIcon.statusBarImage(for: 10, color: .systemGreen, isSparkle: true, pulseStep: 3)
        #expect(step0 !== step3)
    }

    // MARK: - Context health color

    @Test func contextHealthColor_matchesHealthBandThresholds() {
        let green = ThemeColors.contextHealthNSColor(percent: 50)
        let orange = ThemeColors.contextHealthNSColor(percent: 70)
        let red = ThemeColors.contextHealthNSColor(percent: 85)
        #expect(green != orange)
        #expect(orange != red)
        #expect(green == .systemGreen)
        #expect(red == .systemRed)
    }
}

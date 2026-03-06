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
        let low = MenuBarIcon.starScaleRange(for: 10)
        let high = MenuBarIcon.starScaleRange(for: 99)
        // Min is always 1.0 (base size), max grows with usage
        #expect(low.min == 1.0)
        #expect(high.max > low.max)
    }

    @Test func glowAlphaRange_increasesWithPercent() {
        let low = MenuBarIcon.glowAlphaRange(for: 10)
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
        let normalKey = MenuBarIcon.cacheKey(quantizedPercent: 50, isBroken: false, pulseStep: 0)
        let brokenKey = MenuBarIcon.cacheKey(quantizedPercent: 50, isBroken: true, pulseStep: 0)
        #expect(normalKey != brokenKey)
    }

    @Test func cacheKey_normalEncodesPulseStep() {
        let step0 = MenuBarIcon.cacheKey(quantizedPercent: 50, isBroken: false, pulseStep: 0)
        let step3 = MenuBarIcon.cacheKey(quantizedPercent: 50, isBroken: false, pulseStep: 3)
        #expect(step0 != step3)
    }

    @Test func cacheKey_differentPercentsAreDistinct() {
        let key0 = MenuBarIcon.cacheKey(quantizedPercent: 0, isBroken: false, pulseStep: 0)
        let key50 = MenuBarIcon.cacheKey(quantizedPercent: 50, isBroken: false, pulseStep: 0)
        #expect(key0 != key50)
    }

    @Test func cacheKey_brokenPulseStepsAreDistinct() {
        let step0 = MenuBarIcon.cacheKey(quantizedPercent: 0, isBroken: true, pulseStep: 0)
        let step4 = MenuBarIcon.cacheKey(quantizedPercent: 0, isBroken: true, pulseStep: 4)
        let step7 = MenuBarIcon.cacheKey(quantizedPercent: 0, isBroken: true, pulseStep: 7)
        #expect(step0 != step4)
        #expect(step4 != step7)
        #expect(step0 == 1000)
        #expect(step7 == 1007)
    }

    // MARK: - Star geometry

    @Test func starPath_has8Vertices() {
        let path = MenuBarIcon.starPath(
            center: NSPoint(x: 8, y: 8),
            outerRadius: 6.5,
            innerRadius: 2.0
        )
        #expect(path.elementCount == 9) // 1 move + 7 lines + 1 close
    }

    @Test func brokenStarFragments_returns4Pieces() {
        let fragments = MenuBarIcon.brokenStarFragments(
            center: NSPoint(x: 8, y: 8),
            outerRadius: 6.5,
            innerRadius: 2.0,
            offset: 1.5
        )
        #expect(fragments.count == 4)
        for fragment in fragments {
            #expect(fragment.elementCount == 4) // move + 2 lines + close
        }
    }

    // MARK: - NSBezierPath CGPath conversion

    @Test func cgPath_convertsCorrectly() {
        let bezier = NSBezierPath()
        bezier.move(to: NSPoint(x: 0, y: 0))
        bezier.line(to: NSPoint(x: 10, y: 0))
        bezier.line(to: NSPoint(x: 5, y: 10))
        bezier.close()
        let cg = bezier.cgPath
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

    // MARK: - Sparkle icon (green / healthy)

    @Test func sparkleIcon_isCorrectSizeNonTemplate() {
        let icon = MenuBarIcon.statusBarImage(for: 10, color: .systemGreen, pulseStep: 0)
        #expect(icon.size.width == MenuBarIcon.iconSize)
        #expect(icon.size.height == MenuBarIcon.iconSize)
        #expect(icon.isTemplate == false)
    }

    @Test func sparkleIcon_differentStepsProduceDifferentInstances() {
        let step0 = MenuBarIcon.statusBarImage(for: 10, color: .systemGreen, pulseStep: 0)
        let step3 = MenuBarIcon.statusBarImage(for: 10, color: .systemGreen, pulseStep: 3)
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

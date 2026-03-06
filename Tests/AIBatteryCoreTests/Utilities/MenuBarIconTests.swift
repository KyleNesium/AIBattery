import Testing
import AppKit
@testable import AIBatteryCore

@Suite("MenuBarIcon")
struct MenuBarIconTests {

    // MARK: - Glow parameters

    @Test func glowBlur_scalesWithPercent() {
        #expect(MenuBarIcon.glowBlur(for: 0) == 1.0)
        #expect(MenuBarIcon.glowBlur(for: 29) == 1.0)
        #expect(MenuBarIcon.glowBlur(for: 30) == 1.5)
        #expect(MenuBarIcon.glowBlur(for: 59) == 1.5)
        #expect(MenuBarIcon.glowBlur(for: 60) == 2.5)
        #expect(MenuBarIcon.glowBlur(for: 79) == 2.5)
        #expect(MenuBarIcon.glowBlur(for: 80) == 3.5)
        #expect(MenuBarIcon.glowBlur(for: 94) == 3.5)
        #expect(MenuBarIcon.glowBlur(for: 95) == 4.5)
        #expect(MenuBarIcon.glowBlur(for: 100) == 4.5)
    }

    @Test func glowAlpha_scalesWithPercent() {
        #expect(MenuBarIcon.glowAlpha(for: 0) == 0.15)
        #expect(MenuBarIcon.glowAlpha(for: 29) == 0.15)
        #expect(MenuBarIcon.glowAlpha(for: 30) == 0.25)
        #expect(MenuBarIcon.glowAlpha(for: 60) == 0.35)
        #expect(MenuBarIcon.glowAlpha(for: 80) == 0.45)
        #expect(MenuBarIcon.glowAlpha(for: 95) == 0.55)
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

    @Test func cacheKey_normalUsesQuantizedPercent() {
        let key0 = MenuBarIcon.cacheKey(quantizedPercent: 0, isBroken: false, pulseStep: 0)
        let key50 = MenuBarIcon.cacheKey(quantizedPercent: 50, isBroken: false, pulseStep: 0)
        let key100 = MenuBarIcon.cacheKey(quantizedPercent: 100, isBroken: false, pulseStep: 0)
        #expect(key0 == 0)
        #expect(key50 == 50)
        #expect(key100 == 100)
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
        // Each fragment is a triangle: move + 2 lines + close = 4 elements
        for fragment in fragments {
            #expect(fragment.elementCount == 4)
        }
    }

    // MARK: - Rendered icon properties

    @Test func normalIcon_is16x16NonTemplate() {
        let icon = MenuBarIcon.statusBarImage(for: 50)
        #expect(icon.size.width == 16)
        #expect(icon.size.height == 16)
        #expect(icon.isTemplate == false)
    }

    @Test func brokenIcon_is16x16NonTemplate() {
        let icon = MenuBarIcon.statusBarImage(for: 100, isBroken: true, pulseStep: 0)
        #expect(icon.size.width == 16)
        #expect(icon.size.height == 16)
        #expect(icon.isTemplate == false)
    }

    @Test func differentPercents_produceDifferentCachedIcons() {
        let low = MenuBarIcon.statusBarImage(for: 10)
        let high = MenuBarIcon.statusBarImage(for: 90)
        // Different quantized percents should produce different instances
        #expect(low !== high)
    }

    @Test func samePulseStep_returnsSameCachedInstance() {
        let first = MenuBarIcon.statusBarImage(for: 100, isBroken: true, pulseStep: 3)
        let second = MenuBarIcon.statusBarImage(for: 100, isBroken: true, pulseStep: 3)
        #expect(first === second)
    }

    @Test func differentPulseSteps_produceDifferentInstances() {
        let step0 = MenuBarIcon.statusBarImage(for: 100, isBroken: true, pulseStep: 0)
        let step4 = MenuBarIcon.statusBarImage(for: 100, isBroken: true, pulseStep: 4)
        #expect(step0 !== step4)
    }
}

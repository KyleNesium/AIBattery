import Testing
import AppKit
@testable import AIBatteryCore

@Suite("MenuBarIcon")
@MainActor
struct MenuBarIconTests {

    // MARK: - statusBarImage basic output

    @Test("statusBarImage returns 16x16 non-template image at 0%")
    func statusBarImageAtZero() {
        let image = MenuBarIcon.statusBarImage(for: 0)
        #expect(image.size == NSSize(width: 16, height: 16))
        #expect(image.isTemplate == false)
    }

    @Test("statusBarImage returns 16x16 non-template image at 50%")
    func statusBarImageAtFifty() {
        let image = MenuBarIcon.statusBarImage(for: 50)
        #expect(image.size == NSSize(width: 16, height: 16))
        #expect(image.isTemplate == false)
    }

    @Test("statusBarImage returns 16x16 non-template image at 100%")
    func statusBarImageAtHundred() {
        let image = MenuBarIcon.statusBarImage(for: 100)
        #expect(image.size == NSSize(width: 16, height: 16))
        #expect(image.isTemplate == false)
    }

    // MARK: - Quantized percent cache key

    @Test("quantizedPercent rounds to nearest 5", arguments: [
        (0.0, 0), (2.0, 0), (3.0, 5), (7.0, 5), (8.0, 10),
        (47.0, 45), (48.0, 50), (97.0, 95), (98.0, 100), (100.0, 100),
    ])
    func quantizedPercent(input: Double, expected: Int) {
        #expect(MenuBarIcon.quantizedPercent(for: input) == expected)
    }

    @Test("quantizedPercent clamps above 100 to 100")
    func quantizedPercentClamp() {
        #expect(MenuBarIcon.quantizedPercent(for: 120) == 100)
    }

    // MARK: - Cache behavior

    @Test("same quantized percent returns same cached instance")
    func cacheSameInstance() {
        let a = MenuBarIcon.statusBarImage(for: 42)
        let b = MenuBarIcon.statusBarImage(for: 43)
        // Both quantize to 40 or 45 — same bucket
        #expect(a === b)
    }

    @Test("different quantized buckets return different instances")
    func cacheDifferentInstances() {
        let low = MenuBarIcon.statusBarImage(for: 10)
        let high = MenuBarIcon.statusBarImage(for: 90)
        #expect(low !== high)
    }
}

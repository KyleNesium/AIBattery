import Testing
import AppKit
@testable import AIBatteryCore

/// Pins the render-skip key for the menu bar image: `updateButton` only rebuilds
/// the NSImage when this key changes, so its equality semantics ARE the skip
/// behavior — a field wrongly excluded would freeze the menu bar on stale pixels,
/// a too-precise field (raw Double percent) would defeat the skip entirely.
///
/// `@MainActor` + component-based colors: comparing *dynamic* system NSColors
/// off the main thread wedged the whole parallel test runner on the headless CI
/// machine (AppKit's lazy appearance machinery). Production compares on the
/// MainActor inside a real app, where dynamic colors are fine.
@Suite("MenuBarRenderKey")
@MainActor
struct MenuBarRenderKeyTests {
    private static let green = NSColor(srgbRed: 0, green: 0.8, blue: 0, alpha: 1)
    private static let red = NSColor(srgbRed: 0.9, green: 0.1, blue: 0, alpha: 1)

    private func makeKey(
        text: String = "2h 15m",
        percent: Double = 42.0,
        color: NSColor = MenuBarRenderKeyTests.green,
        isBroken: Bool = false,
        isSparkle: Bool = false,
        appearanceName: NSAppearance.Name = .aqua
    ) -> MenuBarRenderKey {
        MenuBarRenderKey(
            text: text,
            percent: percent,
            color: color,
            isBroken: isBroken,
            isSparkle: isSparkle,
            appearanceName: appearanceName
        )
    }

    @Test("identical inputs produce equal keys — the redundant-tick skip case")
    func identicalInputs_equal() {
        #expect(makeKey() == makeKey())
    }

    @Test("sub-1% percent jitter stays in the same bucket and still skips")
    func percentJitter_sameBucket_equal() {
        // 42.1 and 42.4 both round to bucket 42 — float jitter between polls
        // must not defeat the skip.
        #expect(makeKey(percent: 42.1) == makeKey(percent: 42.4))
    }

    @Test("a whole-percent change crosses the bucket and re-renders")
    func percentWholeChange_differs() {
        #expect(makeKey(percent: 42.0) != makeKey(percent: 43.0))
    }

    @Test("each visible field change re-renders")
    func visibleFieldChanges_differ() {
        #expect(makeKey(text: "2h 15m") != makeKey(text: "2h 14m"))
        #expect(makeKey(color: Self.green) != makeKey(color: Self.red))
        #expect(makeKey(isBroken: false) != makeKey(isBroken: true))
        #expect(makeKey(isSparkle: false) != makeKey(isSparkle: true))
        #expect(makeKey(appearanceName: .aqua) != makeKey(appearanceName: .darkAqua))
    }
}

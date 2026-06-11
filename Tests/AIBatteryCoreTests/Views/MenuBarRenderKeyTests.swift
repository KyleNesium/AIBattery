import Testing
import AppKit
@testable import AIBatteryCore

/// Pins the render-skip key for the menu bar image: `updateButton` only rebuilds
/// the NSImage when this key changes, so its equality semantics ARE the skip
/// behavior — a field wrongly excluded would freeze the menu bar on stale pixels,
/// a too-precise field (raw Double percent) would defeat the skip entirely.
@Suite("MenuBarRenderKey")
struct MenuBarRenderKeyTests {
    private func makeKey(
        text: String = "2h 15m",
        percent: Double = 42.0,
        color: NSColor = .systemGreen,
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
        #expect(makeKey(color: .systemGreen) != makeKey(color: .systemRed))
        #expect(makeKey(isBroken: false) != makeKey(isBroken: true))
        #expect(makeKey(isSparkle: false) != makeKey(isSparkle: true))
        #expect(makeKey(appearanceName: .aqua) != makeKey(appearanceName: .darkAqua))
    }
}

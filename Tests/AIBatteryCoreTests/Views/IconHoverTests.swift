import AppKit
import SwiftUI
import Testing
@testable import AIBatteryCore

private let presets: [IconHover] = [.turn, .pop, .outward, .drop, .rise, .forward]

@Suite("IconHover")
struct IconHoverTests {
    @Test func resolved_isIdentityWhileInactive() {
        for effect in presets {
            #expect(effect.resolved(active: false, reduceMotion: false) == .identity)
        }
    }

    /// Reduce Motion drops the movement; the control's colour change still says "hovered".
    @Test func resolved_isIdentityUnderReduceMotion() {
        for effect in presets {
            #expect(effect.resolved(active: true, reduceMotion: true) == .identity)
        }
    }

    @Test func resolved_isThePresetWhileActive() {
        for effect in presets {
            #expect(effect.resolved(active: true, reduceMotion: false) == effect)
        }
    }

    @Test func everyPreset_actuallyMoves() {
        for effect in presets {
            #expect(effect != .identity)
        }
    }

    /// `gearshape` has eight teeth, so a 45° turn lands the gear on its own silhouette.
    @Test func turn_advancesTheGearOneTooth() {
        #expect(IconHover.turn.rotationDegrees == 360.0 / 8)
    }

    /// Each directional preset moves its glyph the way the glyph points (+y is down).
    @Test func directionalPresets_pointWhereTheirGlyphLeads() {
        #expect(IconHover.outward.offset.width > 0)
        #expect(IconHover.outward.offset.height < 0)
        #expect(IconHover.drop.offset == CGSize(width: 0, height: IconHover.drop.offset.height))
        #expect(IconHover.drop.offset.height > 0)
        #expect(IconHover.rise.offset == CGSize(width: 0, height: IconHover.rise.offset.height))
        #expect(IconHover.rise.offset.height < 0)
        #expect(IconHover.forward.offset.width > 0)
        #expect(IconHover.forward.offset.height == 0)
    }
}

/// The performance contract: hover motion is render-only. If a preset ever changed a
/// control's fitting size, every hover would invalidate the hosting view's intrinsic size
/// and refit the panel, which is the expensive path this design avoids.
@MainActor
@Suite("IconHover layout", .serialized)
struct IconHoverLayoutTests {
    @Test func hoverMotion_neverChangesFittingSize() {
        _ = NSApplication.shared
        // Run AppKit's one-time menu-system initializer on main before any hosting view
        // exists (see TransparentHostingViewIntrinsicSizeTests for the deadlock).
        _ = NSImage(size: NSSize(width: 1, height: 1)).cgImage(forProposedRect: nil, context: nil, hints: nil)
        for effect in presets {
            #expect(fittingSize(effect, active: true) == fittingSize(effect, active: false))
        }
    }

    private func fittingSize(_ effect: IconHover, active: Bool) -> CGSize {
        NSHostingView(rootView: HoverProbe(effect: effect, active: active)).fittingSize
    }
}

/// An icon beside a label, the shape of every control that uses `iconHover`.
private struct HoverProbe: View {
    let effect: IconHover
    let active: Bool

    var body: some View {
        HStack(spacing: Spacing.tight) {
            Image(systemName: "gearshape")
                .font(Typography.headerGear)
                .iconHover(effect, active: active)
            Text("Settings")
                .font(Typography.caption)
        }
    }
}

import AppKit
import SwiftUI
import Testing
@testable import AIBatteryCore

/// `.copyable(_:bleed:)` gives up its 3pt inset on the edges named, so an edge-aligned
/// value lines up with the bar beside it, while every other edge keeps the inset.
@Suite("Copyable bleed", .serialized)
@MainActor
struct CopyableBleedTests {
    @Test func bleedEdges_loseTheInset_othersKeepIt() {
        _ = NSApplication.shared
        // Run AppKit's one-time menu-system initializer on main before any hosting view
        // exists (see TransparentHostingViewIntrinsicSizeTests for the deadlock).
        _ = NSImage(size: NSSize(width: 1, height: 1)).cgImage(forProposedRect: nil, context: nil, hints: nil)

        let plain = width(Text("Resets in 3h").font(Typography.tinyLabel))
        let inset = width(Text("Resets in 3h").font(Typography.tinyLabel).copyable("x"))
        let trailing = width(Text("Resets in 3h").font(Typography.tinyLabel).copyable("x", bleed: .trailing))
        let both = width(Text("Resets in 3h").font(Typography.tinyLabel).copyable("x", bleed: .horizontal))

        #expect(inset == plain + 2 * Spacing.xsmall)
        #expect(trailing == plain + Spacing.xsmall)
        #expect(both == plain, "bleeding both edges lays out exactly like the bare text")
    }

    private func width(_ view: some View) -> CGFloat {
        NSHostingView(rootView: view).fittingSize.width
    }
}

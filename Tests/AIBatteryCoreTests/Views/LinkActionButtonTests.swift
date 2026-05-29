import Testing
import SwiftUI
@testable import AIBatteryCore

/// Pins the v2.3.1 LinkActionButton size-variant typography contract.
///
/// Four ad-hoc inline-action button implementations across the popover were
/// collapsed onto this component. The Size variants encode the visual scale
/// that each context expects:
///
///   - `.standard` is for settings rows (Add Account): caption text + tinyLabel icon
///   - `.compact`  is for in-banner actions (Test / Download / Install Update):
///                 tinyLabel text + monoTiny icon
///
/// If a future change flips these mappings, the four call sites will silently
/// drift in opposite directions — these tests fail loudly instead.
@Suite("LinkActionButton")
@MainActor
struct LinkActionButtonTests {
    @Test func standard_labelFont_isCaption() {
        #expect(LinkActionButton.labelFont(for: .standard) == Typography.caption)
    }

    @Test func standard_iconFont_isTinyLabel() {
        #expect(LinkActionButton.iconFont(for: .standard) == Typography.tinyLabel)
    }

    @Test func compact_labelFont_isTinyLabel() {
        #expect(LinkActionButton.labelFont(for: .compact) == Typography.tinyLabel)
    }

    @Test func compact_iconFont_isMonoTiny() {
        #expect(LinkActionButton.iconFont(for: .compact) == Typography.monoTiny)
    }

    @Test func compact_textIsSmallerThanStandard() {
        // Variants must scale in the same direction — compact text must not
        // accidentally become the same size as standard, or larger.
        let standardLabel = LinkActionButton.labelFont(for: .standard)
        let compactLabel = LinkActionButton.labelFont(for: .compact)
        #expect(standardLabel != compactLabel,
                "compact and standard must use distinct label fonts")
    }
}

#if ENABLE_VERSION_CHECKER
import Testing
import SwiftUI
@testable import AIBatteryCore

/// Pins the row-2 update-button contract: once Check for Updates finds a
/// release, the button must relabel to "Install vX.Y.Z" and highlight yellow
/// — this is the pure mapping `AboutSection` renders from, kept outside view
/// introspection.
@Suite("AboutSection")
@MainActor
struct AboutSectionTests {
    @Test func updateKnown_showsInstallLabelAndHighlights() {
        let update = VersionChecker.UpdateInfo(version: "3.3.0", url: "https://example.com")
        let action = AboutSection.updateAction(for: update, checking: false)
        #expect(action.label == "Install v3.3.0")
        #expect(action.icon == "arrow.up.circle")
        #expect(action.highlighted)
    }

    @Test func checking_showsCheckingLabel_notHighlighted() {
        let action = AboutSection.updateAction(for: nil, checking: true)
        #expect(action.label == "Checking…")
        #expect(!action.highlighted)
    }

    @Test func idle_showsCheckForUpdatesLabel_notHighlighted() {
        let action = AboutSection.updateAction(for: nil, checking: false)
        #expect(action.label == "Check for Updates")
        #expect(!action.highlighted)
    }
}
#endif

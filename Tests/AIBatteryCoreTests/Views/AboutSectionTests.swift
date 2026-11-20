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
    /// GPL v3 requires an interactive program to show its copyright, that there is no
    /// warranty, and how to see the licence. Settings → About is that place.
    @Test func legalNotice_namesTheCopyrightTheLicenceAndNoWarranty() {
        #expect(AboutSection.legalNotice.contains("KyleNesium"))
        #expect(AboutSection.legalNotice.contains("GNU GPL v3"))
        #expect(AboutSection.legalNotice.contains("no warranty"))
        #expect(AboutSection.licenseURL.hasSuffix("/NOTICE"))
    }

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

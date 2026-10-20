import SwiftUI
import Testing
@testable import AIBatteryCore

@Suite("UpdateArrowButton")
struct UpdateArrowButtonTests {
    @Test func helpText_namesTheVersionAndTheAction() {
        #expect(UpdateArrowButton.helpText(version: "3.3.0") == "v3.3.0 available — click to update")
    }

    @Test func accessibilityLabel_namesTheVersion() {
        #expect(UpdateArrowButton.accessibilityLabel(version: "3.3.0") == "Update available, version 3.3.0")
    }

    @Test func menuTitles_areStable() {
        #expect(UpdateArrowButton.releaseNotesTitle == "Release notes")
        #expect(UpdateArrowButton.checkForUpdatesTitle == "Check for Updates")
    }

    /// Reduce Motion stops the breathing; the arrow itself stays.
    @Test func breatheAnimation_isNilUnderReduceMotion() {
        #expect(UpdateArrowButton.breatheAnimation(reduceMotion: true) == nil)
        #expect(UpdateArrowButton.breatheAnimation(reduceMotion: false) != nil)
    }
}

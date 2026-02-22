import Testing
@testable import AIBatteryCore

@Suite("VersionChecker")
struct VersionCheckerTests {

    // MARK: - Semver comparison

    @Test func isNewer_majorBump() {
        #expect(VersionChecker.isNewer("2.0.0", than: "1.0.0"))
    }

    @Test func isNewer_minorBump() {
        #expect(VersionChecker.isNewer("1.2.0", than: "1.1.0"))
    }

    @Test func isNewer_patchBump() {
        #expect(VersionChecker.isNewer("1.1.1", than: "1.1.0"))
    }

    @Test func isNewer_same() {
        #expect(!VersionChecker.isNewer("1.1.0", than: "1.1.0"))
    }

    @Test func isNewer_older() {
        #expect(!VersionChecker.isNewer("1.0.0", than: "1.1.0"))
    }

    @Test func isNewer_differentLengths_latest_shorter() {
        #expect(!VersionChecker.isNewer("1.0", than: "1.0.1"))
    }

    @Test func isNewer_differentLengths_latest_longer() {
        #expect(VersionChecker.isNewer("1.0.1", than: "1.0"))
    }

    @Test func isNewer_zeroPadding() {
        #expect(VersionChecker.isNewer("2.0", than: "1.9.9"))
    }

    // MARK: - Tag stripping

    @Test func stripTag_withV() {
        #expect(VersionChecker.stripTag("v1.2.0") == "1.2.0")
    }

    @Test func stripTag_withCapitalV() {
        #expect(VersionChecker.stripTag("V1.2.0") == "1.2.0")
    }

    @Test func stripTag_noPrefix() {
        #expect(VersionChecker.stripTag("1.2.0") == "1.2.0")
    }

    @Test func stripTag_empty() {
        #expect(VersionChecker.stripTag("") == "")
    }

    @Test func stripTag_justV() {
        #expect(VersionChecker.stripTag("v") == "")
    }
}

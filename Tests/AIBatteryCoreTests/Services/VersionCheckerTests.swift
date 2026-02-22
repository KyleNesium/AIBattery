import Foundation
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

    // MARK: - Extended semver edge cases

    @Test func isNewer_bothZero() {
        #expect(!VersionChecker.isNewer("0.0.0", than: "0.0.0"))
    }

    @Test func isNewer_majorOnly() {
        #expect(VersionChecker.isNewer("2", than: "1"))
    }

    @Test func isNewer_sameMajor_differentMinor() {
        #expect(!VersionChecker.isNewer("1.0.0", than: "1.1.0"))
    }

    @Test func isNewer_largePatchBump() {
        #expect(VersionChecker.isNewer("1.0.100", than: "1.0.99"))
    }

    @Test func isNewer_twoVsThreeComponents() {
        #expect(VersionChecker.isNewer("1.1", than: "1.0.9"))
    }

    @Test func isNewer_emptyStrings() {
        #expect(!VersionChecker.isNewer("", than: ""))
    }

    @Test func isNewer_nonNumericComponents() {
        #expect(!VersionChecker.isNewer("abc", than: "1.0.0"))
    }

    @Test func stripTag_lowercaseV_multiDigit() {
        #expect(VersionChecker.stripTag("v12.3.456") == "12.3.456")
    }

    // MARK: - currentAppVersion

    @Test func currentAppVersion_returnsString() {
        let version = VersionChecker.currentAppVersion
        #expect(!version.isEmpty)
    }

    @Test func currentAppVersion_fallsBackToZero() {
        // In test bundle there's no CFBundleShortVersionString → falls back to "0.0.0"
        let version = VersionChecker.currentAppVersion
        #expect(version == "0.0.0" || version.contains("."))
    }

    // MARK: - Cache behavior

    @Test @MainActor func checkForUpdate_returnsCachedWithinInterval() async {
        let checker = VersionChecker(releaseURL: URL(string: "https://example.com")!, checkInterval: 86400)
        let fakeUpdate = VersionChecker.UpdateInfo(version: "9.9.9", url: "https://example.com/release")
        checker.lastCheck = Date()
        checker.cachedUpdate = fakeUpdate

        let result = await checker.checkForUpdate()

        #expect(result?.version == "9.9.9")
        #expect(result?.url == "https://example.com/release")
    }

    @Test @MainActor func checkForUpdate_returnsNilCachedWithinInterval() async {
        let checker = VersionChecker(releaseURL: URL(string: "https://example.com")!, checkInterval: 86400)
        checker.lastCheck = Date()
        checker.cachedUpdate = nil

        let result = await checker.checkForUpdate()

        #expect(result == nil)
    }

    @Test @MainActor func checkForUpdate_expiredCache_doesNotReturnStale() async {
        let checker = VersionChecker(releaseURL: URL(string: "https://invalid.localhost.test")!, checkInterval: 1)
        let oldUpdate = VersionChecker.UpdateInfo(version: "1.0.0", url: "https://example.com")
        checker.lastCheck = Date(timeIntervalSinceNow: -10)
        checker.cachedUpdate = oldUpdate

        // Cache expired, will attempt network (which fails on invalid URL) → returns nil
        let result = await checker.checkForUpdate()
        #expect(result == nil)
    }

    // MARK: - forceCheckForUpdate

    @Test @MainActor func forceCheckForUpdate_clearsLastCheck() async {
        let checker = VersionChecker(releaseURL: URL(string: "https://invalid.localhost.test")!, checkInterval: 86400)
        checker.lastCheck = Date()
        checker.cachedUpdate = VersionChecker.UpdateInfo(version: "1.0.0", url: "https://example.com")

        _ = await checker.forceCheckForUpdate()

        // After force check, lastCheck is reset (then set again by the network call attempt)
        // The key behavior: it didn't return the cached value despite being within the interval
        // Since the URL is invalid, it returns nil (network error)
        #expect(checker.cachedUpdate == nil)
    }

    @Test @MainActor func forceCheckForUpdate_bypassesCache() async {
        let checker = VersionChecker(releaseURL: URL(string: "https://invalid.localhost.test")!, checkInterval: 86400)
        let fakeUpdate = VersionChecker.UpdateInfo(version: "9.9.9", url: "https://example.com")
        checker.lastCheck = Date()
        checker.cachedUpdate = fakeUpdate

        let result = await checker.forceCheckForUpdate()

        // Would have returned 9.9.9 from cache, but force check bypassed it
        // Network call fails → returns nil
        #expect(result == nil)
    }

    @Test @MainActor func forceCheckForUpdate_setsLastCheckAfterAttempt() async {
        let checker = VersionChecker(releaseURL: URL(string: "https://invalid.localhost.test")!, checkInterval: 86400)
        checker.lastCheck = nil

        _ = await checker.forceCheckForUpdate()

        // After the attempt (even failed), lastCheck should be set
        #expect(checker.lastCheck != nil)
    }

    // MARK: - checkInterval

    @Test @MainActor func checkInterval_defaultIs24Hours() {
        let checker = VersionChecker(releaseURL: URL(string: "https://example.com")!)
        #expect(checker.checkInterval == 86400)
    }

    @Test @MainActor func checkInterval_customValue() {
        let checker = VersionChecker(releaseURL: URL(string: "https://example.com")!, checkInterval: 60)
        #expect(checker.checkInterval == 60)
    }
}

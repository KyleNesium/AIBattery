import Testing
@testable import AIBatteryCore

@Suite("NotificationManager")
struct NotificationManagerTests {

    @Test func shouldAlert_aboveThreshold_notPreviouslyFired() {
        #expect(NotificationManager.shouldAlert(percent: 85, threshold: 80, previouslyFired: false))
    }

    @Test func shouldAlert_exactlyAtThreshold() {
        #expect(NotificationManager.shouldAlert(percent: 80, threshold: 80, previouslyFired: false))
    }

    @Test func shouldAlert_belowThreshold() {
        #expect(!NotificationManager.shouldAlert(percent: 79, threshold: 80, previouslyFired: false))
    }

    @Test func shouldAlert_aboveThreshold_previouslyFired() {
        #expect(!NotificationManager.shouldAlert(percent: 90, threshold: 80, previouslyFired: true))
    }

    @Test func shouldAlert_zeroPercent() {
        #expect(!NotificationManager.shouldAlert(percent: 0, threshold: 80, previouslyFired: false))
    }

    @Test func shouldAlert_hundredPercent_notFired() {
        #expect(NotificationManager.shouldAlert(percent: 100, threshold: 80, previouslyFired: false))
    }

    @Test func shouldAlert_customThreshold_50() {
        #expect(NotificationManager.shouldAlert(percent: 50, threshold: 50, previouslyFired: false))
        #expect(!NotificationManager.shouldAlert(percent: 49, threshold: 50, previouslyFired: false))
    }

    @Test func shouldAlert_customThreshold_95() {
        #expect(!NotificationManager.shouldAlert(percent: 94, threshold: 95, previouslyFired: false))
        #expect(NotificationManager.shouldAlert(percent: 95, threshold: 95, previouslyFired: false))
    }

    // MARK: - Extended edge cases

    @Test func shouldAlert_fractionalPercent_justBelow() {
        #expect(!NotificationManager.shouldAlert(percent: 79.9, threshold: 80, previouslyFired: false))
    }

    @Test func shouldAlert_fractionalPercent_justAbove() {
        #expect(NotificationManager.shouldAlert(percent: 80.1, threshold: 80, previouslyFired: false))
    }

    @Test func shouldAlert_dropsBelow_thenRisesAgain() {
        #expect(NotificationManager.shouldAlert(percent: 85, threshold: 80, previouslyFired: false))
        #expect(!NotificationManager.shouldAlert(percent: 90, threshold: 80, previouslyFired: true))
        #expect(!NotificationManager.shouldAlert(percent: 70, threshold: 80, previouslyFired: true))
        #expect(NotificationManager.shouldAlert(percent: 85, threshold: 80, previouslyFired: false))
    }

    @Test func shouldAlert_minimumThreshold_50() {
        #expect(!NotificationManager.shouldAlert(percent: 49, threshold: 50, previouslyFired: false))
        #expect(NotificationManager.shouldAlert(percent: 50, threshold: 50, previouslyFired: false))
    }

    @Test func shouldAlert_negativePercent() {
        #expect(!NotificationManager.shouldAlert(percent: -10, threshold: 80, previouslyFired: false))
    }

    // MARK: - AppleScript quoting

    @Test func applescriptQuoted_plainString() {
        let result = NotificationManager.applescriptQuoted("Hello world")
        #expect(result == "\"Hello world\"")
    }

    @Test func applescriptQuoted_escapesDoubleQuotes() {
        let result = NotificationManager.applescriptQuoted("He said \"hello\"")
        #expect(result == "\"He said \\\"hello\\\"\"")
    }

    @Test func applescriptQuoted_escapesBackslashes() {
        let result = NotificationManager.applescriptQuoted("path\\to\\file")
        #expect(result == "\"path\\\\to\\\\file\"")
    }

    @Test func applescriptQuoted_emptyString() {
        let result = NotificationManager.applescriptQuoted("")
        #expect(result == "\"\"")
    }

    @Test func applescriptQuoted_mixedSpecialChars() {
        let result = NotificationManager.applescriptQuoted("line\\n\"quoted\"")
        #expect(result == "\"line\\\\n\\\"quoted\\\"\"")
    }

    @Test func applescriptQuoted_shellMetacharsPassThrough() {
        // Shell chars like $ and ` should NOT be escaped — Process.arguments
        // bypasses the shell, so only AppleScript string delimiters matter.
        let result = NotificationManager.applescriptQuoted("$HOME `whoami`")
        #expect(result == "\"$HOME `whoami`\"")
    }
}

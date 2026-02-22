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
}

import Testing
import Foundation
@testable import AIBatteryCore

@Suite("UsageViewModel")
struct UsageViewModelTests {

    // MARK: - clampedRefreshInterval

    @Test func clampedRefreshInterval_zero_returnsDefault() {
        #expect(UsageViewModel.clampedRefreshInterval(0) == 60)
    }

    @Test func clampedRefreshInterval_negative_returnsDefault() {
        #expect(UsageViewModel.clampedRefreshInterval(-10) == 60)
    }

    @Test func clampedRefreshInterval_belowMin_clampsToMin() {
        #expect(UsageViewModel.clampedRefreshInterval(5) == 10)
    }

    @Test func clampedRefreshInterval_aboveMax_clampsToMax() {
        #expect(UsageViewModel.clampedRefreshInterval(120) == 60)
    }

    @Test func clampedRefreshInterval_inRange_returnsAsIs() {
        #expect(UsageViewModel.clampedRefreshInterval(30) == 30)
    }

    @Test func clampedRefreshInterval_exactMin_returnsMin() {
        #expect(UsageViewModel.clampedRefreshInterval(10) == 10)
    }

    @Test func clampedRefreshInterval_exactMax_returnsMax() {
        #expect(UsageViewModel.clampedRefreshInterval(60) == 60)
    }

    // MARK: - refreshErrorMessage

    @Test func refreshErrorMessage_noDataNoMessages_returnsNoUsage() {
        let msg = UsageViewModel.refreshErrorMessage(hasRateLimits: false, hasProfile: false, totalMessages: 0)
        #expect(msg == "No usage data yet. Start a Claude Code session to see your stats.")
    }

    @Test func refreshErrorMessage_noDataWithMessages_returnsAPIError() {
        let msg = UsageViewModel.refreshErrorMessage(hasRateLimits: false, hasProfile: false, totalMessages: 50)
        #expect(msg == "Unable to reach Anthropic API. Check your internet connection and try again.")
    }

    @Test func refreshErrorMessage_hasRateLimits_returnsNil() {
        let msg = UsageViewModel.refreshErrorMessage(hasRateLimits: true, hasProfile: false, totalMessages: 0)
        #expect(msg == nil)
    }

    @Test func refreshErrorMessage_hasProfile_returnsNil() {
        let msg = UsageViewModel.refreshErrorMessage(hasRateLimits: false, hasProfile: true, totalMessages: 0)
        #expect(msg == nil)
    }

    @Test func refreshErrorMessage_hasBothData_returnsNil() {
        let msg = UsageViewModel.refreshErrorMessage(hasRateLimits: true, hasProfile: true, totalMessages: 100)
        #expect(msg == nil)
    }

    // MARK: - hasDataChanged

    @Test func hasDataChanged_firstLoad_returnsTrue() {
        #expect(UsageViewModel.hasDataChanged(previousTotal: -1, previousToday: -1, newTotal: 0, newToday: 0))
    }

    @Test func hasDataChanged_totalChanged_returnsTrue() {
        #expect(UsageViewModel.hasDataChanged(previousTotal: 10, previousToday: 5, newTotal: 11, newToday: 5))
    }

    @Test func hasDataChanged_todayChanged_returnsTrue() {
        #expect(UsageViewModel.hasDataChanged(previousTotal: 10, previousToday: 5, newTotal: 10, newToday: 6))
    }

    @Test func hasDataChanged_unchanged_returnsFalse() {
        #expect(!UsageViewModel.hasDataChanged(previousTotal: 10, previousToday: 5, newTotal: 10, newToday: 5))
    }

    @Test func hasDataChanged_bothChanged_returnsTrue() {
        #expect(UsageViewModel.hasDataChanged(previousTotal: 10, previousToday: 5, newTotal: 20, newToday: 15))
    }
}

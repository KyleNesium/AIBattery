import Testing
import Foundation
@testable import AIBatteryCore

@Suite("Burn Prediction")
struct BurnPredictionTests {

    // MARK: - Basic estimates

    @Test func turnsToOrange_basicEstimate() {
        // 40% used, 80K of 160K usable, 10 turns → avg 8K/turn
        // Orange at 60% = 96K → need 16K more → 2 turns
        let result = TokenHealthStatus.estimatedTurnsToThreshold(
            currentUsagePercent: 50,
            totalUsed: 80_000,
            usableWindow: 160_000,
            turnCount: 10,
            thresholdPercent: 60
        )
        #expect(result == 2)
    }

    @Test func turnsToRed_basicEstimate() {
        // 65% used, 104K of 160K usable, 10 turns → avg 10.4K/turn
        // Red at 80% = 128K → need 24K more → 2 turns
        let result = TokenHealthStatus.estimatedTurnsToThreshold(
            currentUsagePercent: 65,
            totalUsed: 104_000,
            usableWindow: 160_000,
            turnCount: 10,
            thresholdPercent: 80
        )
        #expect(result == 2)
    }

    // MARK: - Nil returns (unreliable estimates)

    @Test func tooFewTurns_returnsNil() {
        // Only 4 turns — minimum is 5
        let result = TokenHealthStatus.estimatedTurnsToThreshold(
            currentUsagePercent: 40,
            totalUsed: 64_000,
            usableWindow: 160_000,
            turnCount: 4,
            thresholdPercent: 60
        )
        #expect(result == nil)
    }

    @Test func alreadyPastThreshold_returnsNil() {
        // 70% used, threshold is 60%
        let result = TokenHealthStatus.estimatedTurnsToThreshold(
            currentUsagePercent: 70,
            totalUsed: 112_000,
            usableWindow: 160_000,
            turnCount: 10,
            thresholdPercent: 60
        )
        #expect(result == nil)
    }

    @Test func exactlyAtThreshold_returnsNil() {
        // Exactly at 60%, threshold is 60%
        let result = TokenHealthStatus.estimatedTurnsToThreshold(
            currentUsagePercent: 60,
            totalUsed: 96_000,
            usableWindow: 160_000,
            turnCount: 10,
            thresholdPercent: 60
        )
        #expect(result == nil)
    }

    @Test func zeroTotalUsed_returnsNil() {
        let result = TokenHealthStatus.estimatedTurnsToThreshold(
            currentUsagePercent: 0,
            totalUsed: 0,
            usableWindow: 160_000,
            turnCount: 10,
            thresholdPercent: 60
        )
        #expect(result == nil)
    }

    @Test func exactlyFiveTurns_works() {
        // Minimum turn count (5) should work
        // 5 turns, 50K used → avg 10K/turn
        // Threshold 60% = 96K → need 46K → 4 turns
        let result = TokenHealthStatus.estimatedTurnsToThreshold(
            currentUsagePercent: 31.25,
            totalUsed: 50_000,
            usableWindow: 160_000,
            turnCount: 5,
            thresholdPercent: 60
        )
        #expect(result == 4)
    }

    // MARK: - Edge cases

    @Test func veryCloseToThreshold_returnsSmallNumber() {
        // 59% used, threshold 60% — just 1 turn away
        // 94_400 used of 160K, 10 turns → avg 9_440/turn
        // Need 96_000 - 94_400 = 1_600 more → 0 turns (rounds down to 0, returns nil)
        let result = TokenHealthStatus.estimatedTurnsToThreshold(
            currentUsagePercent: 59,
            totalUsed: 94_400,
            usableWindow: 160_000,
            turnCount: 10,
            thresholdPercent: 60
        )
        // 1600 / 9440 = 0.17 → 0 → nil (not useful to show)
        #expect(result == nil)
    }

    @Test func lowUsage_highTurnsAway() {
        // 31% used, 5 turns, threshold 60%
        // 49_600 used of 160K, 5 turns → avg 9_920/turn
        // Need 96_000 - 49_600 = 46_400 → 4 turns
        let result = TokenHealthStatus.estimatedTurnsToThreshold(
            currentUsagePercent: 31,
            totalUsed: 49_600,
            usableWindow: 160_000,
            turnCount: 5,
            thresholdPercent: 60
        )
        #expect(result == 4)
    }

    @Test func largeContextWindow() {
        // 200K usable, 40% used = 80K, 20 turns → avg 4K/turn
        // Threshold 60% = 120K → need 40K → 10 turns
        let result = TokenHealthStatus.estimatedTurnsToThreshold(
            currentUsagePercent: 40,
            totalUsed: 80_000,
            usableWindow: 200_000,
            turnCount: 20,
            thresholdPercent: 60
        )
        #expect(result == 10)
    }

    @Test func highTurnCount_smallAverage() {
        // Many small turns: 100 turns, 50K used → avg 500/turn
        // Threshold 60% = 96K → need 46K → 92 turns
        let result = TokenHealthStatus.estimatedTurnsToThreshold(
            currentUsagePercent: 31.25,
            totalUsed: 50_000,
            usableWindow: 160_000,
            turnCount: 100,
            thresholdPercent: 60
        )
        #expect(result == 92)
    }

    @Test func orangeToRed_prediction() {
        // Already in orange (65%), predicting red (80%)
        // 104K of 160K, 15 turns → avg 6_933/turn
        // Need 128K - 104K = 24K → 3 turns
        let result = TokenHealthStatus.estimatedTurnsToThreshold(
            currentUsagePercent: 65,
            totalUsed: 104_000,
            usableWindow: 160_000,
            turnCount: 15,
            thresholdPercent: 80
        )
        #expect(result == 3)
    }
}

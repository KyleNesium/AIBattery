import Testing
import Foundation
@testable import AIBatteryCore

@Suite("LocalUsageEstimate")
struct LocalUsageEstimateTests {
    // MARK: - calibrateFrom429 policy

    @MainActor
    @Test func calibrateFrom429_uncalibrated_seedsLimit() {
        resetState()
        defer { resetState() }

        LocalUsageEstimate.latestFiveHourTokens = 1_000_000
        LocalUsageEstimate.latestSevenDayTokens = 0
        LocalUsageEstimate.calibrateFrom429()

        // limit = 1_000_000 / 0.95 ≈ 1_052_631
        #expect(LocalUsageEstimate.fiveHourLimit > 1_000_000)
        #expect(LocalUsageEstimate.fiveHourLimit < 1_100_000)
    }

    @MainActor
    @Test func calibrateFrom429_existingCalibration_doesNotOverride() {
        resetState()
        defer { resetState() }

        // Pre-existing calibration from a real headers-backed call.
        LocalUsageEstimate.fiveHourLimit = 5_000_000
        LocalUsageEstimate.latestFiveHourTokens = 1_000_000
        LocalUsageEstimate.calibrateFrom429()

        // Must not ratchet a precise calibration down from a header-less 429
        // (which may not even be a quota throttle).
        #expect(LocalUsageEstimate.fiveHourLimit == 5_000_000)
    }

    @MainActor
    @Test func calibrateFrom429_belowMinTokenFloor_skipsSeeding() {
        resetState()
        defer { resetState() }

        LocalUsageEstimate.latestFiveHourTokens = 50_000 // below 100_000 floor
        LocalUsageEstimate.calibrateFrom429()

        #expect(LocalUsageEstimate.fiveHourLimit == 0)
    }

    @MainActor
    @Test func calibrateFrom429_independentWindows() {
        resetState()
        defer { resetState() }

        // 5h already calibrated (must not be touched), 7d uncalibrated (should seed).
        LocalUsageEstimate.fiveHourLimit = 3_000_000
        LocalUsageEstimate.sevenDayLimit = 0
        LocalUsageEstimate.latestFiveHourTokens = 1_000_000
        LocalUsageEstimate.latestSevenDayTokens = 1_000_000
        LocalUsageEstimate.calibrateFrom429()

        #expect(LocalUsageEstimate.fiveHourLimit == 3_000_000)
        #expect(LocalUsageEstimate.sevenDayLimit > 1_000_000)
    }

    // MARK: - Helpers

    @MainActor
    private func resetState() {
        LocalUsageEstimate.fiveHourLimit = 0
        LocalUsageEstimate.sevenDayLimit = 0
        LocalUsageEstimate.latestFiveHourTokens = 0
        LocalUsageEstimate.latestSevenDayTokens = 0
        UserDefaults.standard.removeObject(forKey: "aibattery_calibrated_at")
    }
}

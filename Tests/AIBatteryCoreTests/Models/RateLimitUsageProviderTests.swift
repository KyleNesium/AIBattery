import Foundation
import Testing
@testable import AIBatteryCore

@Suite("RateLimitUsage provider")
struct RateLimitUsageProviderTests {
    @Test func decodesLegacyPersistedJSONWithoutProviderFields() throws {
        // Shape persisted by v2.6.1 under aibattery_rateLimits_* — no provider key.
        let legacy = Data("""
        {"representativeClaim":"five_hour","fiveHourUtilization":0.42,"fiveHourReset":700000000,
         "fiveHourStatus":"allowed","sevenDayUtilization":0.1,"sevenDayReset":700400000,
         "sevenDayStatus":"allowed","overallStatus":"allowed"}
        """.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let usage = try decoder.decode(RateLimitUsage.self, from: legacy)
        #expect(usage.provider == .claude)
        #expect(usage.fiveHourWindowMinutes == nil)
        #expect(usage.sevenDayDisplayLabel == "7-Day")
    }

    @Test func codexProviderDrivesLabels() {
        let usage = RateLimitUsage(
            representativeClaim: RateLimitUsage.fiveHourWindow,
            fiveHourUtilization: 0.21, fiveHourReset: Date(), fiveHourStatus: "allowed",
            sevenDayUtilization: 0.03, sevenDayReset: Date(), sevenDayStatus: "allowed",
            overallStatus: "allowed",
            provider: .codex, fiveHourWindowMinutes: 300, sevenDayWindowMinutes: 10_080
        )
        #expect(usage.sevenDayDisplayLabel == "Weekly")
        #expect(usage.provider == .codex)
    }

    @Test func existingCallSitesCompileViaDefaults() {
        let usage = RateLimitUsage(
            representativeClaim: RateLimitUsage.sevenDayWindow,
            fiveHourUtilization: 0.5, fiveHourReset: nil, fiveHourStatus: "allowed",
            sevenDayUtilization: 0.9, sevenDayReset: nil, sevenDayStatus: "allowed",
            overallStatus: "allowed"
        )
        #expect(usage.provider == .claude)
    }

    // MARK: - windowMinutes drive window-duration math (spec §3)

    private func codexUsage(fiveHourMinutes: Int?, resetIn: TimeInterval, utilization: Double, now: Date) -> RateLimitUsage {
        RateLimitUsage(
            representativeClaim: RateLimitUsage.fiveHourWindow,
            fiveHourUtilization: utilization, fiveHourReset: now.addingTimeInterval(resetIn), fiveHourStatus: "allowed",
            sevenDayUtilization: 0.1, sevenDayReset: now.addingTimeInterval(500_000), sevenDayStatus: "allowed",
            overallStatus: "allowed",
            provider: .codex, fiveHourWindowMinutes: fiveHourMinutes, sevenDayWindowMinutes: 10_080
        )
    }

    @Test func windowDurations_defaultTo300And10080WhenAbsent() {
        let usage = codexUsage(fiveHourMinutes: nil, resetIn: 1_000, utilization: 0.5, now: Date())
        #expect(usage.fiveHourDuration == 300 * 60)
        #expect(usage.sevenDayDuration == 10_080 * 60)
    }

    @Test func rolloverArtifactGuard_usesPayloadWindowMinutes() {
        // A 60-minute window that resets in 55 min started 5 min ago → a 96% reading is
        // a rollover artifact. With the default 300-minute assumption it would look
        // 245 min old and be trusted.
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let short = codexUsage(fiveHourMinutes: 60, resetIn: 55 * 60, utilization: 0.96, now: now)
        #expect(short.withClearedRolloverArtifacts(now: now).fiveHourUtilization == 0)
        let assumed = codexUsage(fiveHourMinutes: nil, resetIn: 55 * 60, utilization: 0.96, now: now)
        #expect(assumed.withClearedRolloverArtifacts(now: now).fiveHourUtilization == 0.96)
    }

    @Test func burnRateEstimate_usesPayloadWindowMinutes() {
        // 60-minute window, 30 min elapsed, 60% used → limit in ~20 min (before reset).
        // The 300-minute assumption would compute 270 min elapsed and project past reset → nil.
        let now = Date()
        let short = codexUsage(fiveHourMinutes: 60, resetIn: 30 * 60, utilization: 0.6, now: now)
        let estimate = short.estimatedTimeToLimit(for: RateLimitUsage.fiveHourWindow)
        #expect(estimate != nil && abs((estimate ?? 0) - 20 * 60) < 5)
        let assumed = codexUsage(fiveHourMinutes: nil, resetIn: 30 * 60, utilization: 0.6, now: now)
        #expect(assumed.estimatedTimeToLimit(for: RateLimitUsage.fiveHourWindow) == nil)
    }
}

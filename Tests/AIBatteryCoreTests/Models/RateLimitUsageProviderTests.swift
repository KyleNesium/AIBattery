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
}

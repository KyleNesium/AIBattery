import Testing
@testable import AIBatteryCore

@Suite("MetricMode")
struct MetricModeTests {

    // MARK: - Raw values

    @Test func rawValues() {
        #expect(MetricMode.fiveHour.rawValue == "5h")
        #expect(MetricMode.sevenDay.rawValue == "7d")
        #expect(MetricMode.contextHealth.rawValue == "context")
        #expect(MetricMode.dailyPace.rawValue == "pace")
    }

    // MARK: - Init from raw value

    @Test func initFromValidRaw() {
        #expect(MetricMode(rawValue: "5h") == .fiveHour)
        #expect(MetricMode(rawValue: "7d") == .sevenDay)
        #expect(MetricMode(rawValue: "context") == .contextHealth)
        #expect(MetricMode(rawValue: "pace") == .dailyPace)
    }

    @Test func initFromInvalidRaw() {
        #expect(MetricMode(rawValue: "invalid") == nil)
        #expect(MetricMode(rawValue: "") == nil)
    }

    // MARK: - Labels

    @Test func labels() {
        #expect(MetricMode.fiveHour.label == "5-Hour")
        #expect(MetricMode.sevenDay.label == "7-Day")
        #expect(MetricMode.contextHealth.label == "Context")
        #expect(MetricMode.dailyPace.label == "Daily Pace")
    }

    // MARK: - Short labels

    @Test func shortLabels() {
        #expect(MetricMode.fiveHour.shortLabel == "5h")
        #expect(MetricMode.sevenDay.shortLabel == "7d")
        #expect(MetricMode.contextHealth.shortLabel == "Ctx")
        #expect(MetricMode.dailyPace.shortLabel == "Pace")
    }

    // MARK: - CaseIterable

    @Test func allCases() {
        #expect(MetricMode.allCases.count == 4)
        #expect(MetricMode.allCases.contains(.fiveHour))
        #expect(MetricMode.allCases.contains(.sevenDay))
        #expect(MetricMode.allCases.contains(.contextHealth))
        #expect(MetricMode.allCases.contains(.dailyPace))
    }
}

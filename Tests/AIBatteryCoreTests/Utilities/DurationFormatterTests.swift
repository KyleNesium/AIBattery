import Testing
@testable import AIBatteryCore

@Suite("DurationFormatter")
struct DurationFormatterTests {

    @Test func compact_zeroSeconds() {
        #expect(DurationFormatter.compact(0) == "soon")
    }

    @Test func compact_negativeSeconds() {
        #expect(DurationFormatter.compact(-100) == "soon")
    }

    @Test func compact_underOneMinute() {
        #expect(DurationFormatter.compact(30) == "1m")
    }

    @Test func compact_exactMinutes() {
        #expect(DurationFormatter.compact(300) == "5m")
    }

    @Test func compact_hoursAndMinutes() {
        #expect(DurationFormatter.compact(7500) == "2h 5m")
    }

    @Test func compact_exactHours() {
        #expect(DurationFormatter.compact(3600) == "1h 0m")
    }

    @Test func compact_overOneDay() {
        // 25 hours = 1d 1h
        #expect(DurationFormatter.compact(90000) == "1d 1h")
    }

    @Test func compact_multipleDays() {
        // 50 hours = 2d 2h
        #expect(DurationFormatter.compact(180000) == "2d 2h")
    }

    @Test func compact_justUnder24Hours() {
        // 23h 59m
        #expect(DurationFormatter.compact(86340) == "23h 59m")
    }

    @Test func compact_exactlyOneMinute() {
        #expect(DurationFormatter.compact(60) == "1m")
    }
}

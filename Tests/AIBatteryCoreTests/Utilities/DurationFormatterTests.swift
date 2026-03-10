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

    @Test func compact_underOneMinute_showsSeconds() {
        #expect(DurationFormatter.compact(30) == "30s")
    }

    @Test func compact_oneSecond() {
        #expect(DurationFormatter.compact(1) == "1s")
    }

    @Test func compact_almostOneMinute() {
        #expect(DurationFormatter.compact(59) == "59s")
    }

    @Test func compact_fractionalSeconds_roundsDown() {
        #expect(DurationFormatter.compact(0.5) == "1s")
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

    @Test func compact_exactly24Hours() {
        // 86400 seconds = 1d 0h (not "24h 0m")
        #expect(DurationFormatter.compact(86400) == "1d 0h")
    }

    @Test func compact_justUnder24Hours() {
        // 23h 59m
        #expect(DurationFormatter.compact(86340) == "23h 59m")
    }

    @Test func compact_exactlyOneMinute() {
        #expect(DurationFormatter.compact(60) == "1m")
    }
}

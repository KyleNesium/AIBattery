import Testing
import Foundation
@testable import AIBatteryCore

@Suite("DateFormatters")
struct DateFormattersTests {

    // MARK: - dateKey

    @Test func dateKey_format() {
        let date = makeDate(year: 2025, month: 3, day: 15)
        #expect(DateFormatters.dateKey.string(from: date) == "2025-03-15")
    }

    @Test func dateKey_roundTrip() {
        let original = "2025-12-31"
        let date = DateFormatters.dateKey.date(from: original)
        #expect(date != nil)
        #expect(DateFormatters.dateKey.string(from: date!) == original)
    }

    // MARK: - iso8601

    @Test func iso8601_parsesFractionalSeconds() {
        let str = "2025-06-15T10:30:45.123Z"
        let date = DateFormatters.iso8601.date(from: str)
        #expect(date != nil)
    }

    @Test func iso8601_roundTrip() {
        let str = "2025-06-15T10:30:45.000Z"
        let date = DateFormatters.iso8601.date(from: str)
        #expect(date != nil)
        let output = DateFormatters.iso8601.string(from: date!)
        #expect(output == str)
    }

    // MARK: - shortDay

    @Test func shortDay_producesThreeLetterDay() {
        // 2025-03-17 is a Monday
        let date = makeDate(year: 2025, month: 3, day: 17)
        #expect(DateFormatters.shortDay.string(from: date) == "Mon")
    }

    // MARK: - shortMonth

    @Test func shortMonth_producesThreeLetterMonth() {
        let date = makeDate(year: 2025, month: 1, day: 1)
        #expect(DateFormatters.shortMonth.string(from: date) == "Jan")
    }

    // MARK: - Locale pinning

    @Test func allFormatters_usePOSIXLocale() {
        // dateKey, shortDay, shortMonth should all use en_US_POSIX
        #expect(DateFormatters.dateKey.locale.identifier == "en_US_POSIX")
        #expect(DateFormatters.shortDay.locale.identifier == "en_US_POSIX")
        #expect(DateFormatters.shortMonth.locale.identifier == "en_US_POSIX")
    }

    // MARK: - Helper

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: components)!
    }
}

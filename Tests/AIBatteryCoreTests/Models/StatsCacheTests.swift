import Testing
import Foundation
@testable import AIBatteryCore

@Suite("StatsCache")
struct StatsCacheTests {

    // MARK: - DailyActivity

    @Test func dailyActivity_parsedDate_valid() {
        let activity = DailyActivity(date: "2025-06-15", messageCount: 10, sessionCount: 2, toolCallCount: 5)
        #expect(activity.parsedDate != nil)
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: activity.parsedDate!)
        #expect(components.year == 2025)
        #expect(components.month == 6)
        #expect(components.day == 15)
    }

    @Test func dailyActivity_parsedDate_invalidFormat() {
        let activity = DailyActivity(date: "15/06/2025", messageCount: 0, sessionCount: 0, toolCallCount: 0)
        #expect(activity.parsedDate == nil)
    }

    @Test func dailyActivity_parsedDate_empty() {
        let activity = DailyActivity(date: "", messageCount: 0, sessionCount: 0, toolCallCount: 0)
        #expect(activity.parsedDate == nil)
    }

    @Test func dailyActivity_id_isDate() {
        let activity = DailyActivity(date: "2025-01-01", messageCount: 0, sessionCount: 0, toolCallCount: 0)
        #expect(activity.id == "2025-01-01")
    }

    // MARK: - LongestSession

    @Test func longestSession_durationFormatted_hoursAndMinutes() {
        let session = LongestSession(sessionId: "s1", duration: 7_500_000, messageCount: 50, timestamp: "2025-01-01T00:00:00Z")
        #expect(session.durationFormatted == "2h 5m")
    }

    @Test func longestSession_durationFormatted_minutesOnly() {
        let session = LongestSession(sessionId: "s1", duration: 300_000, messageCount: 10, timestamp: "2025-01-01T00:00:00Z")
        #expect(session.durationFormatted == "5m")
    }

    @Test func longestSession_durationFormatted_zeroMinutes() {
        let session = LongestSession(sessionId: "s1", duration: 30_000, messageCount: 1, timestamp: "2025-01-01T00:00:00Z")
        // 30 seconds → 0m
        #expect(session.durationFormatted == "0m")
    }

    @Test func longestSession_durationFormatted_exactHour() {
        let session = LongestSession(sessionId: "s1", duration: 3_600_000, messageCount: 20, timestamp: "2025-01-01T00:00:00Z")
        #expect(session.durationFormatted == "1h 0m")
    }

    // MARK: - Codable round-trip

    @Test func dailyActivity_codableRoundTrip() throws {
        let original = DailyActivity(date: "2025-03-20", messageCount: 42, sessionCount: 3, toolCallCount: 15)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DailyActivity.self, from: data)
        #expect(decoded.date == original.date)
        #expect(decoded.messageCount == original.messageCount)
        #expect(decoded.sessionCount == original.sessionCount)
        #expect(decoded.toolCallCount == original.toolCallCount)
    }

    @Test func longestSession_codableRoundTrip() throws {
        let original = LongestSession(sessionId: "abc-123", duration: 120_000, messageCount: 8, timestamp: "2025-05-10T12:00:00Z")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(LongestSession.self, from: data)
        #expect(decoded.sessionId == original.sessionId)
        #expect(decoded.duration == original.duration)
        #expect(decoded.messageCount == original.messageCount)
        #expect(decoded.timestamp == original.timestamp)
    }
}

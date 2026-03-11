import Foundation

struct StatsCache: Codable {
    let version: Int
    let lastComputedDate: String
    let dailyActivity: [DailyActivity]
    let dailyModelTokens: [DailyModelTokens]
    let modelUsage: [String: ModelUsageEntry]
    let totalSessions: Int
    let totalMessages: Int
    let longestSession: LongestSession?
    let firstSessionDate: String?
    let hourCounts: [String: Int]
    let totalSpeculationTimeSavedMs: Int?
}

struct DailyActivity: Codable, Identifiable {
    let date: String
    let messageCount: Int
    let sessionCount: Int
    let toolCallCount: Int

    var id: String { date }

    /// Cached parsed date — computed once at decode time instead of on every access.
    /// `DateFormatter.date(from:)` is expensive (locale + calendar resolution per call).
    let parsedDate: Date?

    init(date: String, messageCount: Int, sessionCount: Int, toolCallCount: Int) {
        self.date = date
        self.messageCount = messageCount
        self.sessionCount = sessionCount
        self.toolCallCount = toolCallCount
        self.parsedDate = DateFormatters.dateKey.date(from: date)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try container.decode(String.self, forKey: .date)
        messageCount = try container.decode(Int.self, forKey: .messageCount)
        sessionCount = try container.decode(Int.self, forKey: .sessionCount)
        toolCallCount = try container.decode(Int.self, forKey: .toolCallCount)
        parsedDate = DateFormatters.dateKey.date(from: date)
    }

    private enum CodingKeys: String, CodingKey {
        case date, messageCount, sessionCount, toolCallCount
    }
}

struct DailyModelTokens: Codable {
    let date: String
    let tokensByModel: [String: Int]
}

struct ModelUsageEntry: Codable {
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadInputTokens: Int
    let cacheCreationInputTokens: Int
    let webSearchRequests: Int?
    let contextWindow: Int?
    let maxOutputTokens: Int?
}

struct LongestSession: Codable {
    let sessionId: String
    let duration: Int // milliseconds
    let messageCount: Int
    let timestamp: String

    var durationFormatted: String {
        DurationFormatter.compact(TimeInterval(duration) / 1000)
    }
}

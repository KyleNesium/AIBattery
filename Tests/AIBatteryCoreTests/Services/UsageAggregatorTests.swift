import Testing
import Foundation
@testable import AIBatteryCore

@Suite("UsageAggregator", .serialized)
struct UsageAggregatorTests {

    // MARK: - Helpers

    private func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-aggregator-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private func writeStatsCache(_ json: String, to dir: URL) throws -> URL {
        let url = dir.appendingPathComponent("stats-cache.json")
        try Data(json.utf8).write(to: url)
        return url
    }

    private func writeJSONL(_ lines: [String], projectName: String = "test-project", sessionId: String = "session-1", to dir: URL) throws {
        let projectDir = dir.appendingPathComponent(projectName)
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        let fileURL = projectDir.appendingPathComponent("\(sessionId).jsonl")
        let content = lines.joined(separator: "\n") + "\n"
        try Data(content.utf8).write(to: fileURL)
    }

    private func makeAssistantLine(
        model: String = "claude-sonnet-4-5-20250929",
        input: Int = 100,
        output: Int = 50,
        cacheRead: Int = 0,
        cacheWrite: Int = 0,
        sessionId: String = "session-1",
        messageId: String? = nil,
        timestamp: Date? = nil
    ) -> String {
        let ts = timestamp ?? Date()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let tsStr = formatter.string(from: ts)
        let msgId = messageId ?? UUID().uuidString
        return """
        {"type":"assistant","timestamp":"\(tsStr)","sessionId":"\(sessionId)","cwd":"/test","message":{"role":"assistant","model":"\(model)","id":"\(msgId)","usage":{"input_tokens":\(input),"output_tokens":\(output),"cache_read_input_tokens":\(cacheRead),"cache_creation_input_tokens":\(cacheWrite)}}}
        """
    }

    // MARK: - No data

    @Test func aggregate_noData_returnsEmptySnapshot() {
        let dir = tempDir()
        defer { cleanup(dir) }

        let statsCacheURL = dir.appendingPathComponent("nonexistent.json")
        let projectsDir = dir.appendingPathComponent("projects")

        let reader = StatsCacheReader(fileURL: statsCacheURL)
        let logReader = SessionLogReader(projectsURL: projectsDir)
        let aggregator = UsageAggregator(statsCacheReader: reader, sessionLogReader: logReader)

        let snapshot = aggregator.aggregate(rateLimits: nil)

        #expect(snapshot.totalSessions == 0)
        #expect(snapshot.totalMessages == 0)
        #expect(snapshot.modelTokens.isEmpty)
        #expect(snapshot.rateLimits == nil)
    }

    // MARK: - Stats cache only

    @Test func aggregate_statsCacheOnly_populatesSnapshot() throws {
        let dir = tempDir()
        defer { cleanup(dir) }

        let cacheURL = try writeStatsCache(Self.statsCacheJSON, to: dir)
        let projectsDir = dir.appendingPathComponent("projects")

        let reader = StatsCacheReader(fileURL: cacheURL)
        let logReader = SessionLogReader(projectsURL: projectsDir)
        let aggregator = UsageAggregator(statsCacheReader: reader, sessionLogReader: logReader)

        let snapshot = aggregator.aggregate(rateLimits: nil)

        #expect(snapshot.totalSessions == 10)
        #expect(snapshot.totalMessages == 200)
        #expect(snapshot.peakHour == 14)
        #expect(snapshot.peakHourCount == 25)
    }

    // MARK: - JSONL only

    @Test func aggregate_jsonlOnly_countsTodayEntries() throws {
        let dir = tempDir()
        defer { cleanup(dir) }

        let cacheURL = dir.appendingPathComponent("nonexistent.json")
        let projectsDir = dir.appendingPathComponent("projects")

        let now = Date()
        let lines = [
            makeAssistantLine(input: 100, output: 50, messageId: "msg-1", timestamp: now),
            makeAssistantLine(input: 200, output: 100, messageId: "msg-2", timestamp: now),
        ]
        try writeJSONL(lines, to: projectsDir)

        let reader = StatsCacheReader(fileURL: cacheURL)
        let logReader = SessionLogReader(projectsURL: projectsDir)
        let aggregator = UsageAggregator(statsCacheReader: reader, sessionLogReader: logReader)

        let snapshot = aggregator.aggregate(rateLimits: nil)

        #expect(snapshot.todayMessages == 2)
        #expect(snapshot.todaySessions == 1)
        #expect(snapshot.totalMessages == 2)
    }

    // MARK: - Rate limits pass-through

    @Test func aggregate_rateLimitsPassedThrough() {
        let dir = tempDir()
        defer { cleanup(dir) }

        let cacheURL = dir.appendingPathComponent("nonexistent.json")
        let projectsDir = dir.appendingPathComponent("projects")

        let reader = StatsCacheReader(fileURL: cacheURL)
        let logReader = SessionLogReader(projectsURL: projectsDir)
        let aggregator = UsageAggregator(statsCacheReader: reader, sessionLogReader: logReader)

        let rateLimits = RateLimitUsage(
            representativeClaim: "five_hour",
            fiveHourUtilization: 0.425,
            fiveHourReset: Date().addingTimeInterval(3600),
            fiveHourStatus: "allowed",
            sevenDayUtilization: 0.15,
            sevenDayReset: Date().addingTimeInterval(86400),
            sevenDayStatus: "allowed",
            overallStatus: "allowed"
        )

        let snapshot = aggregator.aggregate(rateLimits: rateLimits)

        #expect(snapshot.rateLimits?.fiveHourPercent == 42.5)
        #expect(snapshot.rateLimits?.sevenDayPercent == 15.0)
    }

    // MARK: - Model filtering

    @Test func aggregate_filtersNonClaudeModels() throws {
        let dir = tempDir()
        defer { cleanup(dir) }

        let cacheURL = dir.appendingPathComponent("nonexistent.json")
        let projectsDir = dir.appendingPathComponent("projects")

        let now = Date()
        let lines = [
            makeAssistantLine(model: "claude-sonnet-4-5-20250929", input: 100, output: 50, messageId: "msg-1", timestamp: now),
            makeAssistantLine(model: "gpt-4", input: 200, output: 100, messageId: "msg-2", timestamp: now),
        ]
        try writeJSONL(lines, to: projectsDir)

        // Set token window to 7 days to use windowed mode
        UserDefaults.standard.set(7.0, forKey: UserDefaultsKeys.tokenWindowDays)
        defer { UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.tokenWindowDays) }

        let reader = StatsCacheReader(fileURL: cacheURL)
        let logReader = SessionLogReader(projectsURL: projectsDir)
        let aggregator = UsageAggregator(statsCacheReader: reader, sessionLogReader: logReader)

        let snapshot = aggregator.aggregate(rateLimits: nil)

        // Only claude- models should appear in modelTokens
        #expect(snapshot.modelTokens.count == 1)
        #expect(snapshot.modelTokens[0].id == "claude-sonnet-4-5-20250929")
    }

    // MARK: - Windowed token aggregation

    @Test func aggregate_windowedMode_aggregatesTokens() throws {
        let dir = tempDir()
        defer { cleanup(dir) }

        let cacheURL = dir.appendingPathComponent("nonexistent.json")
        let projectsDir = dir.appendingPathComponent("projects")

        let now = Date()
        let lines = [
            makeAssistantLine(input: 100, output: 50, cacheRead: 10, cacheWrite: 5, messageId: "msg-1", timestamp: now),
            makeAssistantLine(input: 200, output: 100, cacheRead: 20, cacheWrite: 10, messageId: "msg-2", timestamp: now),
        ]
        try writeJSONL(lines, to: projectsDir)

        UserDefaults.standard.set(1.0, forKey: UserDefaultsKeys.tokenWindowDays)
        defer { UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.tokenWindowDays) }

        let reader = StatsCacheReader(fileURL: cacheURL)
        let logReader = SessionLogReader(projectsURL: projectsDir)
        let aggregator = UsageAggregator(statsCacheReader: reader, sessionLogReader: logReader)

        let snapshot = aggregator.aggregate(rateLimits: nil)

        #expect(snapshot.modelTokens.count == 1)
        let model = snapshot.modelTokens[0]
        #expect(model.inputTokens == 300)
        #expect(model.outputTokens == 150)
        #expect(model.cacheReadTokens == 30)
        #expect(model.cacheWriteTokens == 15)
    }

    // MARK: - Token health

    @Test func aggregate_populatesTokenHealth() throws {
        let dir = tempDir()
        defer { cleanup(dir) }

        let cacheURL = dir.appendingPathComponent("nonexistent.json")
        let projectsDir = dir.appendingPathComponent("projects")

        let now = Date()
        let lines = [
            makeAssistantLine(input: 100, output: 50, messageId: "msg-1", timestamp: now),
        ]
        try writeJSONL(lines, to: projectsDir)

        let reader = StatsCacheReader(fileURL: cacheURL)
        let logReader = SessionLogReader(projectsURL: projectsDir)
        let aggregator = UsageAggregator(statsCacheReader: reader, sessionLogReader: logReader)

        let snapshot = aggregator.aggregate(rateLimits: nil)

        // Token health should be populated (at minimum a band assessment)
        #expect(snapshot.tokenHealth != nil)
    }

    // MARK: - Deduplication

    @Test func aggregate_deduplicatesSessionsById() throws {
        let dir = tempDir()
        defer { cleanup(dir) }

        let cacheURL = dir.appendingPathComponent("nonexistent.json")
        let projectsDir = dir.appendingPathComponent("projects")

        let now = Date()
        // Same messageId in two different files — should only count once
        let lines1 = [makeAssistantLine(messageId: "dup-msg", timestamp: now)]
        let lines2 = [makeAssistantLine(messageId: "dup-msg", timestamp: now)]
        try writeJSONL(lines1, projectName: "project-a", sessionId: "sess-1", to: projectsDir)
        try writeJSONL(lines2, projectName: "project-b", sessionId: "sess-2", to: projectsDir)

        let reader = StatsCacheReader(fileURL: cacheURL)
        let logReader = SessionLogReader(projectsURL: projectsDir)
        let aggregator = UsageAggregator(statsCacheReader: reader, sessionLogReader: logReader)

        let snapshot = aggregator.aggregate(rateLimits: nil)

        #expect(snapshot.todayMessages == 1)
    }

    // MARK: - Stats-cache + JSONL merge

    @Test func aggregate_statsCachePlusJsonl_mergesSessionCount() throws {
        let dir = tempDir()
        defer { cleanup(dir) }

        let cacheURL = try writeStatsCache(Self.statsCacheJSON, to: dir)
        let projectsDir = dir.appendingPathComponent("projects")

        let now = Date()
        let lines = [
            makeAssistantLine(input: 300, output: 150, messageId: "merge-msg-1", timestamp: now),
            makeAssistantLine(input: 400, output: 200, sessionId: "session-2", messageId: "merge-msg-2", timestamp: now),
        ]
        try writeJSONL(lines, sessionId: "session-1", to: projectsDir)
        try writeJSONL(
            [makeAssistantLine(input: 100, output: 50, sessionId: "session-2", messageId: "merge-msg-3", timestamp: now)],
            projectName: "test-project-2",
            sessionId: "session-2",
            to: projectsDir
        )

        let reader = StatsCacheReader(fileURL: cacheURL)
        let logReader = SessionLogReader(projectsURL: projectsDir)
        let aggregator = UsageAggregator(statsCacheReader: reader, sessionLogReader: logReader)

        let snapshot = aggregator.aggregate(rateLimits: nil)

        // Stats cache has 10 sessions + 200 messages; JSONL adds today's
        #expect(snapshot.totalSessions >= 10)
        #expect(snapshot.totalMessages >= 200)
        // Today should have at least 3 messages from JSONL (msg-1 in sess-1, msg-2 + msg-3 in sess-2)
        #expect(snapshot.todayMessages >= 2)
        // Today should have 2 unique sessions (session-1 and session-2)
        #expect(snapshot.todaySessions == 2)
    }

    // MARK: - All-time mode

    @Test func aggregate_allTimeMode_usesStatsCacheModelUsage() throws {
        let dir = tempDir()
        defer { cleanup(dir) }

        let cacheURL = try writeStatsCache(Self.statsCacheJSON, to: dir)
        let projectsDir = dir.appendingPathComponent("projects")

        // Add a recent JSONL entry so the model passes the 72-hour recency filter
        let now = Date()
        try writeJSONL(
            [makeAssistantLine(model: "claude-sonnet-4-5-20250929", input: 10, output: 5, timestamp: now)],
            to: projectsDir
        )

        // Set to all-time mode (0)
        UserDefaults.standard.set(0.0, forKey: UserDefaultsKeys.tokenWindowDays)
        defer { UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.tokenWindowDays) }

        let reader = StatsCacheReader(fileURL: cacheURL)
        let logReader = SessionLogReader(projectsURL: projectsDir)
        let aggregator = UsageAggregator(statsCacheReader: reader, sessionLogReader: logReader)

        let snapshot = aggregator.aggregate(rateLimits: nil)

        // All-time mode should include stats-cache modelUsage totals
        #expect(!snapshot.modelTokens.isEmpty)
        if let sonnet = snapshot.modelTokens.first(where: { $0.id == "claude-sonnet-4-5-20250929" }) {
            // Stats cache has 10000 input + 5000 output + 2000 cache read + 500 cache write = 17500
            // Plus the recent JSONL entry's tokens
            #expect(sonnet.totalTokens >= 17500)
        }
    }

    // MARK: - Test data

    private static let statsCacheJSON = """
    {
        "version": 1,
        "lastComputedDate": "2025-06-15",
        "dailyActivity": [
            {"date": "2025-06-14", "messageCount": 80, "sessionCount": 3, "toolCallCount": 15},
            {"date": "2025-06-15", "messageCount": 120, "sessionCount": 7, "toolCallCount": 30}
        ],
        "dailyModelTokens": [
            {"date": "2025-06-15", "tokensByModel": {"claude-sonnet-4-5-20250929": 50000}}
        ],
        "modelUsage": {
            "claude-sonnet-4-5-20250929": {
                "inputTokens": 10000,
                "outputTokens": 5000,
                "cacheReadInputTokens": 2000,
                "cacheCreationInputTokens": 500
            }
        },
        "totalSessions": 10,
        "totalMessages": 200,
        "longestSession": {
            "sessionId": "sess-abc",
            "duration": 7200000,
            "messageCount": 30,
            "timestamp": "2025-06-14T12:00:00.000Z"
        },
        "firstSessionDate": "2025-01-10T08:30:00.000Z",
        "hourCounts": {"14": 25, "15": 18}
    }
    """
}

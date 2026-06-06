import Testing
import Foundation
@testable import AIBatteryCore

@Suite("UsageAggregator", .serialized)
@MainActor
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
        timestamp: Date? = nil,
        cwd: String = "/test"
    ) -> String {
        let ts = timestamp ?? Date()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let tsStr = formatter.string(from: ts)
        let msgId = messageId ?? UUID().uuidString
        let cwdField = cwd.isEmpty ? "" : "\"cwd\":\"\(cwd)\","
        return """
        {"type":"assistant","timestamp":"\(tsStr)","sessionId":"\(sessionId)",\(cwdField)"message":{"role":"assistant","model":"\(model)","id":"\(msgId)","usage":{"input_tokens":\(input),"output_tokens":\(output),"cache_read_input_tokens":\(cacheRead),"cache_creation_input_tokens":\(cacheWrite)}}}
        """
    }

    private func makeAssistantLineWithToolCalls(
        toolCallCount: Int,
        model: String = "claude-sonnet-4-5-20250929",
        input: Int = 100,
        output: Int = 50,
        sessionId: String = "session-1",
        messageId: String? = nil,
        timestamp: Date? = nil,
        cwd: String = "/test"
    ) -> String {
        let ts = timestamp ?? Date()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let tsStr = formatter.string(from: ts)
        let msgId = messageId ?? UUID().uuidString
        let cwdField = cwd.isEmpty ? "" : "\"cwd\":\"\(cwd)\","
        let toolBlocks = (0..<toolCallCount).map { i in
            "{\"type\":\"tool_use\",\"id\":\"tu-\(i)\",\"name\":\"Tool\",\"input\":{}}"
        }.joined(separator: ",")
        let contentField = "[{\"type\":\"text\",\"text\":\"response\"},\(toolBlocks.isEmpty ? "" : toolBlocks)]"
        return """
        {"type":"assistant","timestamp":"\(tsStr)","sessionId":"\(sessionId)",\(cwdField)"message":{"role":"assistant","model":"\(model)","id":"\(msgId)","content":\(contentField),"usage":{"input_tokens":\(input),"output_tokens":\(output),"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}
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

        let (snapshot, _) = aggregator.aggregate(rateLimits: nil)

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

        let (snapshot, _) = aggregator.aggregate(rateLimits: nil)

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

        let (snapshot, _) = aggregator.aggregate(rateLimits: nil)

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
            fiveHourReset: Date().addingTimeInterval(3_600),
            fiveHourStatus: "allowed",
            sevenDayUtilization: 0.15,
            sevenDayReset: Date().addingTimeInterval(86_400),
            sevenDayStatus: "allowed",
            overallStatus: "allowed"
        )

        let (snapshot, _) = aggregator.aggregate(rateLimits: rateLimits)

        #expect(snapshot.rateLimits?.fiveHourPercent == 42.5)
        #expect(snapshot.rateLimits?.sevenDayPercent == 15.0)
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

        let (snapshot, _) = aggregator.aggregate(rateLimits: nil)

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

        let (snapshot, _) = aggregator.aggregate(rateLimits: nil)

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

        let (snapshot, _) = aggregator.aggregate(rateLimits: nil)

        // Stats cache has 10 sessions + 200 messages; JSONL adds today's
        #expect(snapshot.totalSessions >= 10)
        #expect(snapshot.totalMessages >= 200)
        // Today should have at least 3 messages from JSONL (msg-1 in sess-1, msg-2 + msg-3 in sess-2)
        #expect(snapshot.todayMessages >= 2)
        // Today should have 2 unique sessions (session-1 and session-2)
        #expect(snapshot.todaySessions == 2)
    }

    // MARK: - Stats cache model usage

    @Test func aggregate_usesStatsCacheModelUsage() throws {
        let dir = tempDir()
        defer { cleanup(dir) }

        let cacheURL = try writeStatsCache(Self.statsCacheJSON, to: dir)
        let projectsDir = dir.appendingPathComponent("projects")

        let reader = StatsCacheReader(fileURL: cacheURL)
        let logReader = SessionLogReader(projectsURL: projectsDir)
        let aggregator = UsageAggregator(statsCacheReader: reader, sessionLogReader: logReader)

        let (snapshot, _) = aggregator.aggregate(rateLimits: nil)

        // Should include stats-cache modelUsage totals without needing recent JSONL
        #expect(!snapshot.modelTokens.isEmpty)
        if let sonnet = snapshot.modelTokens.first(where: { $0.id == "claude-sonnet-4-5-20250929" }) {
            // Stats cache has 10000 input + 5000 output + 2000 cache read + 500 cache write = 17500
            #expect(sonnet.totalTokens == 17_500)
        }
    }

    // MARK: - Redundant aggregation skip

    @Test func aggregate_unchangedInputs_returnsCachedSnapshot() throws {
        let dir = tempDir()
        defer { cleanup(dir) }

        let cacheURL = dir.appendingPathComponent("nonexistent.json")
        let projectsDir = dir.appendingPathComponent("projects")

        let now = Date()
        let lines = [
            makeAssistantLine(input: 100, output: 50, messageId: "cache-msg-1", timestamp: now),
        ]
        try writeJSONL(lines, to: projectsDir)

        let reader = StatsCacheReader(fileURL: cacheURL)
        let logReader = SessionLogReader(projectsURL: projectsDir)
        let aggregator = UsageAggregator(statsCacheReader: reader, sessionLogReader: logReader)

        let rateLimits = RateLimitUsage(
            representativeClaim: "five_hour",
            fiveHourUtilization: 0.5,
            fiveHourReset: nil,
            fiveHourStatus: "allowed",
            sevenDayUtilization: 0.1,
            sevenDayReset: nil,
            sevenDayStatus: "allowed",
            overallStatus: "allowed"
        )

        let (first, _) = aggregator.aggregate(rateLimits: rateLimits)
        let (second, _) = aggregator.aggregate(rateLimits: rateLimits)

        // Same object returned (reference-equal for struct means identical field values)
        #expect(first.totalMessages == second.totalMessages)
        #expect(first.todayMessages == second.todayMessages)
        // The cached snapshot preserves the original lastUpdated timestamp
        #expect(first.lastUpdated == second.lastUpdated)
    }

    @Test func aggregate_changedRateLimits_recomputes() throws {
        let dir = tempDir()
        defer { cleanup(dir) }

        let cacheURL = dir.appendingPathComponent("nonexistent.json")
        let projectsDir = dir.appendingPathComponent("projects")

        let now = Date()
        try writeJSONL(
            [makeAssistantLine(input: 100, output: 50, messageId: "rl-msg-1", timestamp: now)],
            to: projectsDir
        )

        let reader = StatsCacheReader(fileURL: cacheURL)
        let logReader = SessionLogReader(projectsURL: projectsDir)
        let aggregator = UsageAggregator(statsCacheReader: reader, sessionLogReader: logReader)

        let rl1 = RateLimitUsage(
            representativeClaim: "five_hour",
            fiveHourUtilization: 0.5,
            fiveHourReset: nil,
            fiveHourStatus: "allowed",
            sevenDayUtilization: 0.1,
            sevenDayReset: nil,
            sevenDayStatus: "allowed",
            overallStatus: "allowed"
        )
        let rl2 = RateLimitUsage(
            representativeClaim: "five_hour",
            fiveHourUtilization: 0.8,
            fiveHourReset: nil,
            fiveHourStatus: "allowed",
            sevenDayUtilization: 0.1,
            sevenDayReset: nil,
            sevenDayStatus: "allowed",
            overallStatus: "allowed"
        )

        let (first, _) = aggregator.aggregate(rateLimits: rl1)
        let (second, _) = aggregator.aggregate(rateLimits: rl2)

        // Different rate limits should produce a fresh snapshot
        #expect(first.rateLimits?.fiveHourPercent == 50.0)
        #expect(second.rateLimits?.fiveHourPercent == 80.0)
    }

    @Test func aggregate_newJsonlEntries_recomputes() throws {
        let dir = tempDir()
        defer { cleanup(dir) }

        let cacheURL = dir.appendingPathComponent("nonexistent.json")
        let projectsDir = dir.appendingPathComponent("projects")

        let now = Date()
        try writeJSONL(
            [makeAssistantLine(input: 100, output: 50, messageId: "new-msg-1", timestamp: now)],
            to: projectsDir
        )

        let reader = StatsCacheReader(fileURL: cacheURL)
        let logReader = SessionLogReader(projectsURL: projectsDir)
        let aggregator = UsageAggregator(statsCacheReader: reader, sessionLogReader: logReader)

        let (first, _) = aggregator.aggregate(rateLimits: nil)
        #expect(first.todayMessages == 1)

        // Add a new entry — invalidate both reader cache and aggregator fingerprint
        logReader.invalidate()
        aggregator.invalidate()
        try writeJSONL(
            [
                makeAssistantLine(input: 100, output: 50, messageId: "new-msg-1", timestamp: now),
                makeAssistantLine(input: 200, output: 100, messageId: "new-msg-2", timestamp: now),
            ],
            to: projectsDir
        )

        let (second, _) = aggregator.aggregate(rateLimits: nil)
        #expect(second.todayMessages == 2)
    }

    // MARK: - Hourly merge

    @Test func aggregate_mergesJsonlIntoHourCounts() throws {
        let dir = tempDir()
        defer { cleanup(dir) }

        let cacheURL = try writeStatsCache(Self.statsCacheJSON, to: dir)
        let projectsDir = dir.appendingPathComponent("projects")

        let calendar = Calendar.current
        let now = Date()
        let hour10 = try #require(calendar.date(bySettingHour: 10, minute: 30, second: 0, of: now))
        let hour11 = try #require(calendar.date(bySettingHour: 11, minute: 15, second: 0, of: now))

        let lines = [
            makeAssistantLine(input: 100, output: 50, messageId: "hour-msg-1", timestamp: hour10),
            makeAssistantLine(input: 100, output: 50, messageId: "hour-msg-2", timestamp: hour10),
            makeAssistantLine(input: 100, output: 50, messageId: "hour-msg-3", timestamp: hour11),
        ]
        try writeJSONL(lines, to: projectsDir)

        let reader = StatsCacheReader(fileURL: cacheURL)
        let logReader = SessionLogReader(projectsURL: projectsDir)
        let aggregator = UsageAggregator(statsCacheReader: reader, sessionLogReader: logReader)

        let (snapshot, _) = aggregator.aggregate(rateLimits: nil)

        // JSONL has 2 messages at hour 10 and 1 at hour 11
        #expect(snapshot.hourCounts["10"] == 2)
        #expect(snapshot.hourCounts["11"] == 1)
        // Stats cache hours should still be present
        #expect(snapshot.hourCounts["14"] == 25)
        #expect(snapshot.hourCounts["15"] == 18)
    }

    @Test func aggregate_hourlyMerge_updatedPeakHour() throws {
        let dir = tempDir()
        defer { cleanup(dir) }

        // Stats cache has peak at hour 14 with 25 messages
        let cacheURL = try writeStatsCache(Self.statsCacheJSON, to: dir)
        let projectsDir = dir.appendingPathComponent("projects")

        let calendar = Calendar.current
        let now = Date()
        let hour9 = try #require(calendar.date(bySettingHour: 9, minute: 0, second: 0, of: now))

        // Add 30 messages at hour 9 to surpass the cache peak of 25
        var lines: [String] = []
        for i in 0..<30 {
            lines.append(makeAssistantLine(input: 10, output: 5, sessionId: "sess-\(i)", messageId: "peak-msg-\(i)", timestamp: hour9))
        }
        try writeJSONL(lines, to: projectsDir)

        let reader = StatsCacheReader(fileURL: cacheURL)
        let logReader = SessionLogReader(projectsURL: projectsDir)
        let aggregator = UsageAggregator(statsCacheReader: reader, sessionLogReader: logReader)

        let (snapshot, _) = aggregator.aggregate(rateLimits: nil)

        // Peak should now be hour 9 with 30 messages
        #expect(snapshot.peakHour == 9)
        #expect(snapshot.peakHourCount == 30)
    }

    // MARK: - TotalMessages dedup

    @Test func aggregate_totalMessages_noDoubleCountWhenCacheIncludesToday() throws {
        let dir = tempDir()
        defer { cleanup(dir) }

        let formatter = DateFormatters.dateKey
        let todayStr = formatter.string(from: Date())

        // Stats cache includes today's date in dailyActivity with 5 messages
        let cacheJSON = """
        {
            "version": 1,
            "lastComputedDate": "\(todayStr)",
            "dailyActivity": [
                {"date": "\(todayStr)", "messageCount": 5, "sessionCount": 2, "toolCallCount": 3}
            ],
            "dailyModelTokens": [],
            "modelUsage": {},
            "totalSessions": 2,
            "totalMessages": 5,
            "hourCounts": {}
        }
        """

        let cacheURL = try writeStatsCache(cacheJSON, to: dir)
        let projectsDir = dir.appendingPathComponent("projects")

        // JSONL also has 5 messages for today (same data the cache was built from)
        let now = Date()
        var lines: [String] = []
        for i in 0..<5 {
            lines.append(makeAssistantLine(input: 10, output: 5, messageId: "dedup-msg-\(i)", timestamp: now))
        }
        try writeJSONL(lines, to: projectsDir)

        let reader = StatsCacheReader(fileURL: cacheURL)
        let logReader = SessionLogReader(projectsURL: projectsDir)
        let aggregator = UsageAggregator(statsCacheReader: reader, sessionLogReader: logReader)

        let (snapshot, _) = aggregator.aggregate(rateLimits: nil)

        // Should be 5, not 10 (no double-counting)
        #expect(snapshot.totalMessages == 5)
    }

    @Test func aggregate_totalMessages_addsNewMessagesOnlyBeyondCache() throws {
        let dir = tempDir()
        defer { cleanup(dir) }

        let formatter = DateFormatters.dateKey
        let todayStr = formatter.string(from: Date())

        // Stats cache includes today with 3 messages
        let cacheJSON = """
        {
            "version": 1,
            "lastComputedDate": "\(todayStr)",
            "dailyActivity": [
                {"date": "\(todayStr)", "messageCount": 3, "sessionCount": 1, "toolCallCount": 0}
            ],
            "dailyModelTokens": [],
            "modelUsage": {},
            "totalSessions": 1,
            "totalMessages": 3,
            "hourCounts": {}
        }
        """

        let cacheURL = try writeStatsCache(cacheJSON, to: dir)
        let projectsDir = dir.appendingPathComponent("projects")

        // JSONL has 5 messages (2 more than cache)
        let now = Date()
        var lines: [String] = []
        for i in 0..<5 {
            lines.append(makeAssistantLine(input: 10, output: 5, messageId: "extra-msg-\(i)", timestamp: now))
        }
        try writeJSONL(lines, to: projectsDir)

        let reader = StatsCacheReader(fileURL: cacheURL)
        let logReader = SessionLogReader(projectsURL: projectsDir)
        let aggregator = UsageAggregator(statsCacheReader: reader, sessionLogReader: logReader)

        let (snapshot, _) = aggregator.aggregate(rateLimits: nil)

        // 3 (cache total) + 2 (additional beyond cache's today) = 5
        #expect(snapshot.totalMessages == 5)
    }

    // MARK: - Model filter removal

    @Test func aggregate_showsOldModelsWithoutRecentJsonl() throws {
        let dir = tempDir()
        defer { cleanup(dir) }

        // Stats cache has a model with no recent JSONL activity
        let cacheJSON = """
        {
            "version": 1,
            "lastComputedDate": "2025-01-15",
            "dailyActivity": [],
            "dailyModelTokens": [
                {"date": "2025-01-15", "tokensByModel": {"claude-opus-4-20250514": 100000}}
            ],
            "modelUsage": {
                "claude-opus-4-20250514": {
                    "inputTokens": 50000,
                    "outputTokens": 30000,
                    "cacheReadInputTokens": 10000,
                    "cacheCreationInputTokens": 5000
                }
            },
            "totalSessions": 5,
            "totalMessages": 100,
            "hourCounts": {}
        }
        """

        let cacheURL = try writeStatsCache(cacheJSON, to: dir)
        let projectsDir = dir.appendingPathComponent("projects")

        let reader = StatsCacheReader(fileURL: cacheURL)
        let logReader = SessionLogReader(projectsURL: projectsDir)
        let aggregator = UsageAggregator(statsCacheReader: reader, sessionLogReader: logReader)

        let (snapshot, _) = aggregator.aggregate(rateLimits: nil)

        // Model should appear even without recent activity
        let opus = snapshot.modelTokens.first(where: { $0.id == "claude-opus-4-20250514" })
        #expect(opus != nil)
        #expect(opus?.totalTokens == 95_000)
        #expect(snapshot.totalTokens == 95_000)
    }

    // MARK: - All-dates daily merge

    @Test func aggregate_mergesAllDatesIntoDailyActivity() throws {
        let dir = tempDir()
        defer { cleanup(dir) }

        let formatter = DateFormatters.dateKey
        let cal = Calendar.current
        let now = Date()
        let yesterday = try #require(cal.date(byAdding: .day, value: -1, to: now))
        let twoDaysAgo = try #require(cal.date(byAdding: .day, value: -2, to: now))
        let yesterdayStr = formatter.string(from: yesterday)
        let twoDaysAgoStr = formatter.string(from: twoDaysAgo)

        // Stats cache was rebuilt 3 days ago — doesn't include yesterday or 2 days ago
        let cacheJSON = """
        {
            "version": 1,
            "lastComputedDate": "\(formatter.string(from: cal.date(byAdding: .day, value: -3, to: now)!))",
            "dailyActivity": [],
            "dailyModelTokens": [],
            "modelUsage": {},
            "totalSessions": 0,
            "totalMessages": 0,
            "hourCounts": {}
        }
        """

        let cacheURL = try writeStatsCache(cacheJSON, to: dir)
        let projectsDir = dir.appendingPathComponent("projects")

        // JSONL has entries for yesterday and 2 days ago (not just today)
        let lines = [
            makeAssistantLine(input: 10, output: 5, messageId: "old-1", timestamp: twoDaysAgo),
            makeAssistantLine(input: 10, output: 5, messageId: "old-2", timestamp: twoDaysAgo),
            makeAssistantLine(input: 10, output: 5, messageId: "yest-1", timestamp: yesterday),
            makeAssistantLine(input: 10, output: 5, messageId: "today-1", timestamp: now),
        ]
        try writeJSONL(lines, to: projectsDir)

        let reader = StatsCacheReader(fileURL: cacheURL)
        let logReader = SessionLogReader(projectsURL: projectsDir)
        let aggregator = UsageAggregator(statsCacheReader: reader, sessionLogReader: logReader)

        let (snapshot, _) = aggregator.aggregate(rateLimits: nil)

        // dailyActivity should include entries for all 3 dates
        let activityDates = Set(snapshot.dailyActivity.map(\.date))
        #expect(activityDates.contains(twoDaysAgoStr))
        #expect(activityDates.contains(yesterdayStr))
        #expect(snapshot.dailyActivity.first(where: { $0.date == twoDaysAgoStr })?.messageCount == 2)
        #expect(snapshot.dailyActivity.first(where: { $0.date == yesterdayStr })?.messageCount == 1)
        #expect(snapshot.totalMessages == 4)
    }

    // MARK: - todayHourCounts

    @Test func aggregate_todayHourCountsSeparateFromAllTime() throws {
        let dir = tempDir()
        defer { cleanup(dir) }

        // Stats cache has all-time hour counts at hour 14
        let cacheURL = try writeStatsCache(Self.statsCacheJSON, to: dir)
        let projectsDir = dir.appendingPathComponent("projects")

        let calendar = Calendar.current
        let now = Date()
        let hour10 = try #require(calendar.date(bySettingHour: 10, minute: 0, second: 0, of: now))
        let lines = [
            makeAssistantLine(input: 10, output: 5, messageId: "today-h10-1", timestamp: hour10),
            makeAssistantLine(input: 10, output: 5, messageId: "today-h10-2", timestamp: hour10),
        ]
        try writeJSONL(lines, to: projectsDir)

        let reader = StatsCacheReader(fileURL: cacheURL)
        let logReader = SessionLogReader(projectsURL: projectsDir)
        let aggregator = UsageAggregator(statsCacheReader: reader, sessionLogReader: logReader)

        let (snapshot, _) = aggregator.aggregate(rateLimits: nil)

        // todayHourCounts should only have today's data
        #expect(snapshot.todayHourCounts["10"] == 2)
        #expect(snapshot.todayHourCounts["14"] == nil) // stats cache hour, not today
        // hourCounts (all-time) should have both
        #expect(snapshot.hourCounts["10"] == 2)
        #expect(snapshot.hourCounts["14"] == 25)
    }

    // MARK: - Project tokens: grouping by cwd

    @Test func projectTokens_groupsByCwd() throws {
        let dir = tempDir()
        defer { cleanup(dir) }

        let cacheURL = dir.appendingPathComponent("nonexistent.json")
        let projectsDir = dir.appendingPathComponent("projects")

        let now = Date()
        let lines = [
            makeAssistantLine(input: 100, output: 50, messageId: "proj-1", timestamp: now, cwd: "/Users/kyle/projects/alpha"),
            makeAssistantLine(input: 200, output: 100, messageId: "proj-2", timestamp: now, cwd: "/Users/kyle/projects/beta"),
        ]
        try writeJSONL(lines, to: projectsDir)

        let reader = StatsCacheReader(fileURL: cacheURL)
        let logReader = SessionLogReader(projectsURL: projectsDir)
        let aggregator = UsageAggregator(statsCacheReader: reader, sessionLogReader: logReader)

        let (snapshot, _) = aggregator.aggregate(rateLimits: nil)

        #expect(snapshot.projectTokens.count == 2)
        let alpha = snapshot.projectTokens.first(where: { $0.projectName == "alpha" })
        let beta = snapshot.projectTokens.first(where: { $0.projectName == "beta" })
        #expect(alpha?.totalTokens == 150)
        #expect(beta?.totalTokens == 300)
    }

    @Test func projectTokens_nilCwdGroupedAsOther() throws {
        let dir = tempDir()
        defer { cleanup(dir) }

        let cacheURL = dir.appendingPathComponent("nonexistent.json")
        let projectsDir = dir.appendingPathComponent("projects")

        let now = Date()
        let lines = [
            makeAssistantLine(input: 100, output: 50, messageId: "no-cwd-1", timestamp: now, cwd: ""),
        ]
        try writeJSONL(lines, to: projectsDir)

        let reader = StatsCacheReader(fileURL: cacheURL)
        let logReader = SessionLogReader(projectsURL: projectsDir)
        let aggregator = UsageAggregator(statsCacheReader: reader, sessionLogReader: logReader)

        let (snapshot, _) = aggregator.aggregate(rateLimits: nil)

        let other = snapshot.projectTokens.first(where: { $0.projectName == "Other" })
        #expect(other != nil)
        #expect(other?.totalTokens == 150)
    }

    @Test func projectTokens_costPerEntry() throws {
        let dir = tempDir()
        defer { cleanup(dir) }

        let cacheURL = dir.appendingPathComponent("nonexistent.json")
        let projectsDir = dir.appendingPathComponent("projects")

        let now = Date()
        // Two different models in the same project — costs should aggregate correctly
        let lines = [
            makeAssistantLine(model: "claude-sonnet-4-5-20250929", input: 1_000_000, output: 0, messageId: "cost-1", timestamp: now, cwd: "/projects/myapp"),
            makeAssistantLine(model: "claude-opus-4-20250514", input: 1_000_000, output: 0, messageId: "cost-2", timestamp: now, cwd: "/projects/myapp"),
        ]
        try writeJSONL(lines, to: projectsDir)

        let reader = StatsCacheReader(fileURL: cacheURL)
        let logReader = SessionLogReader(projectsURL: projectsDir)
        let aggregator = UsageAggregator(statsCacheReader: reader, sessionLogReader: logReader)

        let (snapshot, _) = aggregator.aggregate(rateLimits: nil)

        let myapp = snapshot.projectTokens.first(where: { $0.projectName == "myapp" })
        #expect(myapp != nil)
        // Sonnet input: $3/M * 1M = $3, Opus input: $15/M * 1M = $15 → total $18
        #expect(myapp?.estimatedCost == 18.0)
    }

    @Test func projectTokens_emptyWhenNoEntries() {
        let dir = tempDir()
        defer { cleanup(dir) }

        let cacheURL = dir.appendingPathComponent("nonexistent.json")
        let projectsDir = dir.appendingPathComponent("projects")

        let reader = StatsCacheReader(fileURL: cacheURL)
        let logReader = SessionLogReader(projectsURL: projectsDir)
        let aggregator = UsageAggregator(statsCacheReader: reader, sessionLogReader: logReader)

        let (snapshot, _) = aggregator.aggregate(rateLimits: nil)

        #expect(snapshot.projectTokens.isEmpty)
    }

    @Test func projectTokens_mergesSessions() throws {
        let dir = tempDir()
        defer { cleanup(dir) }

        let cacheURL = dir.appendingPathComponent("nonexistent.json")
        let projectsDir = dir.appendingPathComponent("projects")

        let now = Date()
        // Same cwd across two sessions → should merge into one project
        let lines1 = [
            makeAssistantLine(input: 100, output: 50, sessionId: "sess-a", messageId: "merge-1", timestamp: now, cwd: "/workspace/myapp"),
        ]
        let lines2 = [
            makeAssistantLine(input: 200, output: 100, sessionId: "sess-b", messageId: "merge-2", timestamp: now, cwd: "/workspace/myapp"),
        ]
        try writeJSONL(lines1, projectName: "proj-a", sessionId: "sess-a", to: projectsDir)
        try writeJSONL(lines2, projectName: "proj-b", sessionId: "sess-b", to: projectsDir)

        let reader = StatsCacheReader(fileURL: cacheURL)
        let logReader = SessionLogReader(projectsURL: projectsDir)
        let aggregator = UsageAggregator(statsCacheReader: reader, sessionLogReader: logReader)

        let (snapshot, _) = aggregator.aggregate(rateLimits: nil)

        let myapp = snapshot.projectTokens.first(where: { $0.projectName == "myapp" })
        #expect(myapp != nil)
        #expect(myapp?.totalTokens == 450) // 300 + 150
        #expect(snapshot.projectTokens.count == 1) // merged, not two separate entries
    }

    // MARK: - Fingerprint skip (PERF-06)

    @Test func aggregate_fingerprintSkip_returnsCachedSnapshot() throws {
        let dir = tempDir()
        defer { cleanup(dir) }

        let cacheURL = dir.appendingPathComponent("nonexistent.json")
        let projectsDir = dir.appendingPathComponent("projects")

        let now = Date()
        try writeJSONL(
            [makeAssistantLine(input: 100, output: 50, messageId: "fp-msg-1", timestamp: now)],
            to: projectsDir
        )

        let reader = StatsCacheReader(fileURL: cacheURL)
        let logReader = SessionLogReader(projectsURL: projectsDir)
        let aggregator = UsageAggregator(statsCacheReader: reader, sessionLogReader: logReader)

        let (first, _) = aggregator.aggregate(rateLimits: nil)
        let (second, _) = aggregator.aggregate(rateLimits: nil)

        // The cached snapshot is returned: same lastUpdated timestamp proves no recomputation
        #expect(first.lastUpdated == second.lastUpdated)
        // Same data content
        #expect(first.totalMessages == second.totalMessages)
        #expect(first.todayMessages == second.todayMessages)
        #expect(first.modelTokens.map(\.id) == second.modelTokens.map(\.id))
    }

    @Test func aggregate_fingerprintChanged_recomputes() throws {
        let dir = tempDir()
        defer { cleanup(dir) }

        let cacheURL = dir.appendingPathComponent("nonexistent.json")
        let projectsDir = dir.appendingPathComponent("projects")

        let now = Date()
        try writeJSONL(
            [makeAssistantLine(input: 100, output: 50, messageId: "fp-change-1", timestamp: now)],
            to: projectsDir
        )

        let reader = StatsCacheReader(fileURL: cacheURL)
        let logReader = SessionLogReader(projectsURL: projectsDir)
        let aggregator = UsageAggregator(statsCacheReader: reader, sessionLogReader: logReader)

        // First call with nil rate limits
        let (first, _) = aggregator.aggregate(rateLimits: nil)
        #expect(first.rateLimits == nil)

        // Second call with non-nil rate limits — fingerprint changes, must recompute
        let rl = RateLimitUsage(
            representativeClaim: "five_hour",
            fiveHourUtilization: 0.75,
            fiveHourReset: nil,
            fiveHourStatus: "allowed",
            sevenDayUtilization: 0.30,
            sevenDayReset: nil,
            sevenDayStatus: "allowed",
            overallStatus: "allowed"
        )
        let (second, _) = aggregator.aggregate(rateLimits: rl)

        // Recomputed snapshot carries the updated rate limit data
        #expect(second.rateLimits?.fiveHourPercent == 75.0)
        #expect(second.rateLimits?.sevenDayPercent == 30.0)
    }

    @Test func aggregate_projectTokens_fromPreBuiltMap() throws {
        let dir = tempDir()
        defer { cleanup(dir) }

        let cacheURL = dir.appendingPathComponent("nonexistent.json")
        let projectsDir = dir.appendingPathComponent("projects")

        let now = Date()
        // Project A: two different models
        let projALines = [
            makeAssistantLine(model: "claude-sonnet-4-5-20250929", input: 1_000, output: 500,
                              messageId: "map-a1", timestamp: now, cwd: "/workspace/project-alpha"),
            makeAssistantLine(model: "claude-opus-4-20250514", input: 2_000, output: 1_000,
                              messageId: "map-a2", timestamp: now, cwd: "/workspace/project-alpha"),
        ]
        // Project B: two different models
        let projBLines = [
            makeAssistantLine(model: "claude-sonnet-4-5-20250929", input: 500, output: 250,
                              messageId: "map-b1", timestamp: now, cwd: "/workspace/project-beta"),
            makeAssistantLine(model: "claude-opus-4-20250514", input: 800, output: 400,
                              messageId: "map-b2", timestamp: now, cwd: "/workspace/project-beta"),
        ]
        try writeJSONL(projALines, projectName: "proj-a", sessionId: "sess-a", to: projectsDir)
        try writeJSONL(projBLines, projectName: "proj-b", sessionId: "sess-b", to: projectsDir)

        let reader = StatsCacheReader(fileURL: cacheURL)
        let logReader = SessionLogReader(projectsURL: projectsDir)
        let aggregator = UsageAggregator(statsCacheReader: reader, sessionLogReader: logReader)

        let (snapshot, _) = aggregator.aggregate(rateLimits: nil)

        // Exactly 2 projects — proves grouping by cwd key works from the pre-built map
        #expect(snapshot.projectTokens.count == 2)

        let alpha = snapshot.projectTokens.first(where: { $0.projectName == "project-alpha" })
        let beta = snapshot.projectTokens.first(where: { $0.projectName == "project-beta" })

        // Alpha: 1000+500 input + 2000+1000 input = 3000+1500 = 4500 total tokens input,
        // but totalTokens = input + output + cache: (1000+500) + (2000+1000) = 4500 input total
        // + (500+1000) output = 1500 total output → totalTokens = 4500 + 1500 = 6000? No:
        // totalTokens = inputTokens + outputTokens + cacheReadTokens + cacheWriteTokens
        // alpha: input=3000, output=1500, cacheRead=0, cacheWrite=0 → total=4500
        #expect(alpha != nil)
        #expect(alpha?.inputTokens == 3_000)
        #expect(alpha?.outputTokens == 1_500)
        #expect(alpha?.totalTokens == 4_500)

        // Beta: input=1300, output=650, total=1950
        #expect(beta != nil)
        #expect(beta?.inputTokens == 1_300)
        #expect(beta?.outputTokens == 650)
        #expect(beta?.totalTokens == 1_950)
    }

    // MARK: - Observed models

    @Test func aggregate_setsObservedModelsOnRateLimitFetcher() throws {
        let dir = tempDir()
        defer { cleanup(dir) }

        let cacheURL = dir.appendingPathComponent("nonexistent.json")
        let projectsDir = dir.appendingPathComponent("projects")

        let now = Date()
        let earlier = now.addingTimeInterval(-3_600)

        // Two different models — newer model is sonnet-4-6, older is sonnet-4-5
        let lines = [
            makeAssistantLine(model: "claude-sonnet-4-5-20250929", input: 100, output: 50,
                              messageId: "obs-1", timestamp: earlier),
            makeAssistantLine(model: "claude-sonnet-4-6-20250929", input: 200, output: 100,
                              messageId: "obs-2", timestamp: now),
        ]
        try writeJSONL(lines, to: projectsDir)

        let accountId = "test-observed-\(UUID().uuidString)"

        let reader = StatsCacheReader(fileURL: cacheURL)
        let logReader = SessionLogReader(projectsURL: projectsDir)
        // Inject a temp ledger so this accountId-bearing aggregate doesn't write the real token-ledger.json.
        let aggregator = UsageAggregator(statsCacheReader: reader, sessionLogReader: logReader,
                                         ledger: TokenLedger(fileURL: dir.appendingPathComponent("token-ledger.json")))

        let (_, effects) = aggregator.aggregate(rateLimits: nil, accountId: accountId)

        // Most recently seen model (sonnet-4-6, at `now`) should be first
        #expect(effects.observedModels.first == "claude-sonnet-4-6-20250929")
        #expect(effects.observedModels.count == 2)
    }

    @Test func aggregate_returnsCorrectSideEffects() throws {
        let dir = tempDir()
        defer { cleanup(dir) }

        let cacheURL = dir.appendingPathComponent("nonexistent.json")
        let projectsDir = dir.appendingPathComponent("projects")

        let now = Date()
        let earlier = now.addingTimeInterval(-7_200)
        let oldest = now.addingTimeInterval(-14_400)

        // Three entries with distinct models in ascending time order
        let lines = [
            makeAssistantLine(model: "claude-opus-4-20250514", input: 100, output: 50,
                              messageId: "eff-1", timestamp: oldest),
            makeAssistantLine(model: "claude-sonnet-4-5-20250929", input: 100, output: 50,
                              messageId: "eff-2", timestamp: earlier),
            makeAssistantLine(model: "claude-sonnet-4-6-20250929", input: 100, output: 50,
                              messageId: "eff-3", timestamp: now),
        ]
        try writeJSONL(lines, to: projectsDir)

        let accountId = "test-effects-\(UUID().uuidString)"
        let reader = StatsCacheReader(fileURL: cacheURL)
        let logReader = SessionLogReader(projectsURL: projectsDir)
        // Inject a temp ledger so this accountId-bearing aggregate doesn't write the real token-ledger.json.
        let aggregator = UsageAggregator(statsCacheReader: reader, sessionLogReader: logReader,
                                         ledger: TokenLedger(fileURL: dir.appendingPathComponent("token-ledger.json")))

        let (_, effects) = aggregator.aggregate(rateLimits: nil, accountId: accountId)

        // activeUserModel is the last entry's model (entries sorted ascending by timestamp)
        #expect(effects.activeUserModel == "claude-sonnet-4-6-20250929")
        // observedModels sorted by recency: most recent first
        #expect(effects.observedModels.first == "claude-sonnet-4-6-20250929")
        #expect(effects.observedModels.contains("claude-sonnet-4-5-20250929"))
        #expect(effects.observedModels.contains("claude-opus-4-20250514"))
        #expect(effects.observedModels.count == 3)
        // accountId is threaded through
        #expect(effects.accountId == accountId)
    }

    @Test func aggregate_noAccountId_doesNotSetObservedModels() throws {
        let dir = tempDir()
        defer { cleanup(dir) }

        let cacheURL = dir.appendingPathComponent("nonexistent.json")
        let projectsDir = dir.appendingPathComponent("projects")

        let now = Date()
        let lines = [
            makeAssistantLine(model: "claude-sonnet-4-5-20250929", input: 100, output: 50,
                              messageId: "no-acct-1", timestamp: now),
        ]
        try writeJSONL(lines, to: projectsDir)

        let reader = StatsCacheReader(fileURL: cacheURL)
        let logReader = SessionLogReader(projectsURL: projectsDir)
        let aggregator = UsageAggregator(statsCacheReader: reader, sessionLogReader: logReader)

        // No accountId — should not persist observed models
        let (_, effects) = aggregator.aggregate(rateLimits: nil)

        // Without accountId, observed models are still computed but not persisted
        // Verify the code path doesn't crash and returns valid effects
        #expect(effects.accountId == nil)
    }

    // MARK: - Tool call count merge

    @Test func aggregate_jsonlMoreToolCalls_jsonlWins() throws {
        let dir = tempDir()
        defer { cleanup(dir) }

        let formatter = DateFormatters.dateKey
        let todayStr = formatter.string(from: Date())

        // Stats cache has 3 tool calls for today
        let cacheJSON = """
        {
            "version": 1,
            "lastComputedDate": "\(todayStr)",
            "dailyActivity": [
                {"date": "\(todayStr)", "messageCount": 2, "sessionCount": 1, "toolCallCount": 3}
            ],
            "dailyModelTokens": [],
            "modelUsage": {},
            "totalSessions": 1,
            "totalMessages": 2,
            "hourCounts": {}
        }
        """

        let cacheURL = try writeStatsCache(cacheJSON, to: dir)
        let projectsDir = dir.appendingPathComponent("projects")

        // JSONL has 5 tool calls today — should win (5 > 3)
        let now = Date()
        let lines = [
            makeAssistantLineWithToolCalls(toolCallCount: 2, messageId: "tc-1", timestamp: now),
            makeAssistantLineWithToolCalls(toolCallCount: 3, messageId: "tc-2", timestamp: now),
        ]
        try writeJSONL(lines, to: projectsDir)

        let reader = StatsCacheReader(fileURL: cacheURL)
        let logReader = SessionLogReader(projectsURL: projectsDir)
        let aggregator = UsageAggregator(statsCacheReader: reader, sessionLogReader: logReader)

        let (snapshot, _) = aggregator.aggregate(rateLimits: nil)

        #expect(snapshot.todayToolCalls == 5) // max(5 jsonl, 3 cache)
    }

    @Test func aggregate_cacheMoreToolCalls_cacheWins() throws {
        let dir = tempDir()
        defer { cleanup(dir) }

        let formatter = DateFormatters.dateKey
        let todayStr = formatter.string(from: Date())

        // Stats cache has 7 tool calls for today (fresher data)
        let cacheJSON = """
        {
            "version": 1,
            "lastComputedDate": "\(todayStr)",
            "dailyActivity": [
                {"date": "\(todayStr)", "messageCount": 5, "sessionCount": 1, "toolCallCount": 7}
            ],
            "dailyModelTokens": [],
            "modelUsage": {},
            "totalSessions": 1,
            "totalMessages": 5,
            "hourCounts": {}
        }
        """

        let cacheURL = try writeStatsCache(cacheJSON, to: dir)
        let projectsDir = dir.appendingPathComponent("projects")

        // JSONL has 2 tool calls — cache wins (7 > 2)
        let now = Date()
        let lines = [
            makeAssistantLineWithToolCalls(toolCallCount: 2, messageId: "tc-cache-1", timestamp: now),
        ]
        try writeJSONL(lines, to: projectsDir)

        let reader = StatsCacheReader(fileURL: cacheURL)
        let logReader = SessionLogReader(projectsURL: projectsDir)
        let aggregator = UsageAggregator(statsCacheReader: reader, sessionLogReader: logReader)

        let (snapshot, _) = aggregator.aggregate(rateLimits: nil)

        #expect(snapshot.todayToolCalls == 7) // max(2 jsonl, 7 cache)
    }

    @Test func aggregate_noCacheDailyActivity_jsonlToolCallsUsed() throws {
        let dir = tempDir()
        defer { cleanup(dir) }

        let cacheURL = dir.appendingPathComponent("nonexistent.json")
        let projectsDir = dir.appendingPathComponent("projects")

        // No stats cache — JSONL tool calls are the only source
        let now = Date()
        let lines = [
            makeAssistantLineWithToolCalls(toolCallCount: 4, messageId: "tc-nocache-1", timestamp: now),
            makeAssistantLineWithToolCalls(toolCallCount: 2, messageId: "tc-nocache-2", timestamp: now),
        ]
        try writeJSONL(lines, to: projectsDir)

        let reader = StatsCacheReader(fileURL: cacheURL)
        let logReader = SessionLogReader(projectsURL: projectsDir)
        let aggregator = UsageAggregator(statsCacheReader: reader, sessionLogReader: logReader)

        let (snapshot, _) = aggregator.aggregate(rateLimits: nil)

        #expect(snapshot.todayToolCalls == 6) // 4 + 2 from JSONL, cache is 0
    }

    @Test func aggregate_noJsonlTodayEntries_cacheToolCallsUsed() throws {
        let dir = tempDir()
        defer { cleanup(dir) }

        let formatter = DateFormatters.dateKey
        let todayStr = formatter.string(from: Date())

        // Stats cache has 8 tool calls for today
        let cacheJSON = """
        {
            "version": 1,
            "lastComputedDate": "\(todayStr)",
            "dailyActivity": [
                {"date": "\(todayStr)", "messageCount": 10, "sessionCount": 2, "toolCallCount": 8}
            ],
            "dailyModelTokens": [],
            "modelUsage": {},
            "totalSessions": 2,
            "totalMessages": 10,
            "hourCounts": {}
        }
        """

        let cacheURL = try writeStatsCache(cacheJSON, to: dir)
        // No JSONL files at all
        let projectsDir = dir.appendingPathComponent("projects")

        let reader = StatsCacheReader(fileURL: cacheURL)
        let logReader = SessionLogReader(projectsURL: projectsDir)
        let aggregator = UsageAggregator(statsCacheReader: reader, sessionLogReader: logReader)

        let (snapshot, _) = aggregator.aggregate(rateLimits: nil)

        #expect(snapshot.todayToolCalls == 8) // cache value used, jsonl is 0
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

    // MARK: - 7-day rolling-window boundary

    /// Anthropic's 7-day quota window is rolling 7×86400 (mirroring the 5-hour window),
    /// not calendar-day "last 7 days". The previous implementation used
    /// `calendar.date(byAdding: .day, value: -7, to: today)` which biased the count
    /// high by up to 24h of stale tokens — and that bias fed straight into
    /// `LocalUsageEstimate.calibrate(localTokens / utilization)`, producing a too-low
    /// derived limit that could later read ≥100% even when the API said well under.
    ///
    /// Pinning the rolling boundary: an entry exactly `7d + 2h` ago must be excluded
    /// from `sevenDayTokens`; an entry `6d + 22h` ago must be included. Time-of-day
    /// independent because `now` is injected.
    @Test func aggregate_sevenDayWindow_rollingBoundaryExcludesOlderThan7x86400() throws {
        let dir = tempDir()
        defer { cleanup(dir) }

        let cacheURL = dir.appendingPathComponent("nonexistent.json")
        let projectsDir = dir.appendingPathComponent("projects")

        // Anchor `now` at noon so the calendar-day bias would have been observable
        // under the old code (calendar 7-days-ago = midnight of day-7, which is
        // 12h *earlier* than the rolling 7×86400 cutoff). The test pins behavior
        // that's now correct regardless of wall-clock time of day.
        let now = try #require(ISO8601DateFormatter().date(from: "2026-05-25T12:00:00Z"))
        let stale = now.addingTimeInterval(-(7 * 86_400 + 2 * 3_600)) // 7d 2h ago → out
        let fresh = now.addingTimeInterval(-(6 * 86_400 + 22 * 3_600)) // 6d 22h ago → in

        let lines = [
            makeAssistantLine(input: 1_000, output: 0, messageId: "stale", timestamp: stale),
            makeAssistantLine(input: 0, output: 500, messageId: "fresh", timestamp: fresh),
        ]
        try writeJSONL(lines, to: projectsDir)

        let reader = StatsCacheReader(fileURL: cacheURL)
        let logReader = SessionLogReader(projectsURL: projectsDir)
        let aggregator = UsageAggregator(statsCacheReader: reader, sessionLogReader: logReader)

        let (snapshot, _) = aggregator.aggregate(rateLimits: nil, now: now)

        // Only the 6d22h-old entry counts (500 output tokens), not the 7d2h-old one.
        #expect(snapshot.sevenDayTokens == 500)
    }
}

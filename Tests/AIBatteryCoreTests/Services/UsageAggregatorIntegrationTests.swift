import Testing
import Foundation
@testable import AIBatteryCore

/// End-to-end integration tests for the full aggregation pipeline:
/// discover files -> parse -> aggregate -> evict -> re-aggregate.
///
/// Uses real FileManager I/O, real SessionLogReader, and a StatsCacheReader
/// pointed at a non-existent file (JSONL-only aggregation, no stats-cache).
@Suite("UsageAggregator Integration", .serialized)
struct UsageAggregatorIntegrationTests {
    // MARK: - Helpers

    private func tempDir(id: String = UUID().uuidString) -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("agg-integration-\(id)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// Writes JSONL lines to a session file inside the named project subdirectory.
    private func writeJSONL(
        _ lines: [String],
        projectName: String,
        sessionId: String,
        to dir: URL
    ) throws {
        let projectDir = dir.appendingPathComponent(projectName)
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        let fileURL = projectDir.appendingPathComponent("\(sessionId).jsonl")
        let content = lines.joined(separator: "\n") + "\n"
        try Data(content.utf8).write(to: fileURL)
    }

    /// Returns a single valid assistant JSONL line.
    /// Defaults to today's timestamp so it counts in todayMessages and todayEntries.
    private func makeAssistantLine(
        model: String = "claude-sonnet-4-5-20250929",
        input: Int = 100,
        output: Int = 50,
        sessionId: String = "session-1",
        messageId: String? = nil,
        timestamp: Date? = nil,
        cwd: String = "/test/project"
    ) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let tsStr = formatter.string(from: timestamp ?? Date())
        let msgId = messageId ?? UUID().uuidString
        let cwdField = cwd.isEmpty ? "" : "\"cwd\":\"\(cwd)\","
        return """
        {"type":"assistant","timestamp":"\(tsStr)","sessionId":"\(sessionId)",\(cwdField)"message":{"role":"assistant","model":"\(model)","id":"\(msgId)","usage":{"input_tokens":\(input),"output_tokens":\(output),"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}
        """
    }

    /// Sets a file's modification date to yesterday.
    private func backdateFile(at url: URL) throws {
        let yesterday = Date().addingTimeInterval(-86_400)
        try FileManager.default.setAttributes([.modificationDate: yesterday], ofItemAtPath: url.path)
    }

    /// Builds an aggregator backed by real JSONL files at `projectsDir`.
    /// Uses a non-existent stats-cache path so only JSONL data is aggregated.
    private func makeAggregator(projectsDir: URL, rootDir: URL) -> (UsageAggregator, SessionLogReader) {
        let statsCachePath = rootDir.appendingPathComponent("nonexistent-stats-cache.json")
        let statsCacheReader = StatsCacheReader(fileURL: statsCachePath)
        let sessionLogReader = SessionLogReader(projectsURL: projectsDir)
        let aggregator = UsageAggregator(statsCacheReader: statsCacheReader, sessionLogReader: sessionLogReader)
        return (aggregator, sessionLogReader)
    }

    // MARK: - Test 1: Aggregate then re-aggregate — snapshot matches

    @Test func fullPipeline_aggregateThenReaggregate_snapshotMatches() throws {
        let root = tempDir()
        defer { cleanup(root) }
        let projectsDir = root.appendingPathComponent("projects")

        // Two projects with known token counts
        try writeJSONL(
            [
                makeAssistantLine(input: 100, output: 50, sessionId: "sess-a", messageId: "msg-a1", cwd: "/proj/alpha"),
                makeAssistantLine(input: 200, output: 80, sessionId: "sess-a", messageId: "msg-a2", cwd: "/proj/alpha"),
            ],
            projectName: "-proj-alpha",
            sessionId: "sess-a",
            to: projectsDir
        )
        try writeJSONL(
            [
                makeAssistantLine(input: 150, output: 60, sessionId: "sess-b", messageId: "msg-b1", cwd: "/proj/beta"),
            ],
            projectName: "-proj-beta",
            sessionId: "sess-b",
            to: projectsDir
        )

        let (aggregator, sessionLogReader) = makeAggregator(projectsDir: projectsDir, rootDir: root)

        // First aggregate
        let (snapshot1, _) = aggregator.aggregate(rateLimits: nil)
        #expect(snapshot1.todayMessages == 3, "First aggregate: 3 today messages")
        let total1 = snapshot1.todayModelTokens.reduce(0) { $0 + $1.inputTokens }
        #expect(total1 == 450, "First aggregate: 100 + 200 + 150 = 450 input tokens today")

        // Invalidate both reader and aggregator (simulates next polling cycle)
        sessionLogReader.invalidate()
        aggregator.invalidate()

        let (snapshot2, _) = aggregator.aggregate(rateLimits: nil)
        #expect(snapshot2.todayMessages == snapshot1.todayMessages,
                "Re-aggregate todayMessages must match first aggregate")
        let total2 = snapshot2.todayModelTokens.reduce(0) { $0 + $1.inputTokens }
        #expect(total2 == total1, "Re-aggregate today input token total must match")
    }

    // MARK: - Test 2: Aggregate after eviction — totals preserved

    @Test func fullPipeline_aggregateAfterEviction_totalsPreserved() throws {
        let root = tempDir()
        defer { cleanup(root) }
        let projectsDir = root.appendingPathComponent("projects")

        // Write a session file and immediately backdate it (triggers eviction in SessionLogReader)
        try writeJSONL(
            [
                makeAssistantLine(
                    input: 300,
                    output: 120,
                    sessionId: "old-sess",
                    messageId: "msg-old-1",
                    timestamp: Date().addingTimeInterval(-86_400), // yesterday's timestamp
                    cwd: "/proj/old"
                ),
                makeAssistantLine(
                    input: 400,
                    output: 160,
                    sessionId: "old-sess",
                    messageId: "msg-old-2",
                    timestamp: Date().addingTimeInterval(-86_400),
                    cwd: "/proj/old"
                ),
            ],
            projectName: "-proj-old",
            sessionId: "old-sess",
            to: projectsDir
        )
        let oldFileURL = projectsDir
            .appendingPathComponent("-proj-old")
            .appendingPathComponent("old-sess.jsonl")
        try backdateFile(at: oldFileURL)

        let (aggregator, sessionLogReader) = makeAggregator(projectsDir: projectsDir, rootDir: root)

        // First aggregate — SessionLogReader parses and then evicts yesterday's entries from per-file cache
        let (snapshot1, _) = aggregator.aggregate(rateLimits: nil)
        #expect(snapshot1.totalMessages == 2, "First aggregate: 2 total messages (old entries counted in total)")

        // Verify reader evicted the per-file arrays
        let liveCount = sessionLogReader.cacheEntriesWithLiveEntriesCountForTesting()
        #expect(liveCount == 0, "Yesterday's file entries must be evicted after first read")

        // Invalidate ONLY the aggregator (not the reader) — simulates next polling cycle
        // where files haven't changed so reader returns cachedAllEntries directly.
        aggregator.invalidate()

        let (snapshot2, _) = aggregator.aggregate(rateLimits: nil)
        #expect(snapshot2.totalMessages == snapshot1.totalMessages,
                "After eviction, re-aggregate total message count must match")
    }

    // MARK: - Test 3: New session added — aggregate reflects it

    @Test func fullPipeline_newSessionAdded_aggregateReflectsIt() throws {
        let root = tempDir()
        defer { cleanup(root) }
        let projectsDir = root.appendingPathComponent("projects")

        // Start with 1 session file
        try writeJSONL(
            [
                makeAssistantLine(input: 100, output: 50, sessionId: "sess-1", messageId: "msg-s1-1", cwd: "/proj/main"),
                makeAssistantLine(input: 100, output: 50, sessionId: "sess-1", messageId: "msg-s1-2", cwd: "/proj/main"),
            ],
            projectName: "-proj-main",
            sessionId: "sess-1",
            to: projectsDir
        )

        let (aggregator, sessionLogReader) = makeAggregator(projectsDir: projectsDir, rootDir: root)

        let (snapshot1, _) = aggregator.aggregate(rateLimits: nil)
        #expect(snapshot1.todayMessages == 2, "First aggregate: 2 messages from session 1")
        let total1 = snapshot1.todayModelTokens.reduce(0) { $0 + $1.inputTokens }
        #expect(total1 == 200, "First aggregate: 100 + 100 = 200 input tokens")

        // Add a second session file with 3 messages
        try writeJSONL(
            [
                makeAssistantLine(input: 200, output: 80, sessionId: "sess-2", messageId: "msg-s2-1", cwd: "/proj/main"),
                makeAssistantLine(input: 300, output: 120, sessionId: "sess-2", messageId: "msg-s2-2", cwd: "/proj/main"),
                makeAssistantLine(input: 400, output: 160, sessionId: "sess-2", messageId: "msg-s2-3", cwd: "/proj/main"),
            ],
            projectName: "-proj-main",
            sessionId: "sess-2",
            to: projectsDir
        )

        // Invalidate both reader and aggregator
        sessionLogReader.invalidate()
        sessionLogReader.expireDiscoveryTTLForTesting()
        aggregator.invalidate()

        let (snapshot2, _) = aggregator.aggregate(rateLimits: nil)
        #expect(snapshot2.todayMessages == 5, "Second aggregate: 2 + 3 = 5 total messages")
        let total2 = snapshot2.todayModelTokens.reduce(0) { $0 + $1.inputTokens }
        #expect(total2 == 1_100, "Second aggregate: 100+100+200+300+400 = 1100 input tokens")
    }
}

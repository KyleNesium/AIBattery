import Testing
import Foundation
@testable import AIBatteryCore

/// End-to-end integration tests for the full incremental scanning pipeline:
/// discover files -> parse -> cache -> invalidate -> re-read.
///
/// Each test creates an isolated temp directory and a fresh SessionLogReader,
/// exercising real FileManager I/O rather than mocked internals.
@Suite("SessionLogReader Integration", .serialized)
struct SessionLogReaderIntegrationTests {

    // MARK: - Helpers

    /// Creates a temp projects directory with the given project subdirectories.
    /// The directory name uses a Claude Code-style encoding: leading "-" + path with "/" as "-".
    /// Example: project named "proj-a" becomes "-proj-a".
    private func makeTempProjectsDir(
        id: String = UUID().uuidString,
        projectNames: [String] = ["-proj-alpha", "-proj-beta", "-proj-gamma"]
    ) throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("slr-integration-\(id)")
        for name in projectNames {
            let projectDir = tmp.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        }
        return tmp
    }

    /// Writes JSONL lines to a session file inside the named project subdirectory.
    private func writeJSONL(
        lines: [String],
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

    /// Returns a single valid assistant JSONL line with a today timestamp (so it lands in todayEntries).
    private func assistantLine(
        model: String = "claude-sonnet-4-5-20250929",
        inputTokens: Int = 100,
        outputTokens: Int = 50,
        messageId: String,
        sessionId: String = "ses-1",
        timestamp: Date? = nil
    ) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let ts = formatter.string(from: timestamp ?? Date())
        return """
        {"type":"assistant","timestamp":"\(ts)","sessionId":"\(sessionId)","message":{"role":"assistant","model":"\(model)","id":"\(messageId)","usage":{"input_tokens":\(inputTokens),"output_tokens":\(outputTokens)}}}
        """
    }

    /// Sets a file's modification date to yesterday.
    private func backdateFile(at url: URL) throws {
        let yesterday = Date().addingTimeInterval(-86400)
        try FileManager.default.setAttributes([.modificationDate: yesterday], ofItemAtPath: url.path)
    }

    // MARK: - Test 1: Full pipeline discover -> read -> invalidate -> re-read, totals match

    @Test func fullPipeline_discoverReadInvalidateReread_totalsMatch() throws {
        let projectsDir = try makeTempProjectsDir(projectNames: ["-proj-a", "-proj-b", "-proj-c"])
        defer { try? FileManager.default.removeItem(at: projectsDir) }

        // 3 project dirs, 2 JSONL files each, known token counts
        let projects = ["-proj-a", "-proj-b", "-proj-c"]
        var msgIndex = 0
        for proj in projects {
            for session in ["ses-1", "ses-2"] {
                msgIndex += 1
                try writeJSONL(
                    lines: [assistantLine(inputTokens: msgIndex * 10, outputTokens: msgIndex * 5, messageId: "msg-\(proj)-\(session)")],
                    projectName: proj,
                    sessionId: session,
                    to: projectsDir
                )
            }
        }

        let reader = SessionLogReader(projectsURL: projectsDir)

        // First read — full scan
        let first = reader.readAllUsageEntries()
        #expect(first.count == 6, "Expected 6 entries (3 projects x 2 files)")

        let firstTotal = first.reduce(0) { $0 + $1.inputTokens }

        // Invalidate then re-read — incremental path
        reader.invalidate()
        let second = reader.readAllUsageEntries()

        #expect(second.count == first.count, "Entry count must match after invalidate + re-read")
        let secondTotal = second.reduce(0) { $0 + $1.inputTokens }
        #expect(secondTotal == firstTotal, "Input token total must be identical on incremental re-read")
    }

    // MARK: - Test 2: New file added after first read — discovered on second read

    @Test func fullPipeline_addNewFileAfterFirstRead_picksUpNewEntries() throws {
        let projectsDir = try makeTempProjectsDir(projectNames: ["-my-project"])
        defer { try? FileManager.default.removeItem(at: projectsDir) }

        // Initial state: 2 entries in 1 file
        try writeJSONL(
            lines: [
                assistantLine(inputTokens: 100, messageId: "msg-001"),
                assistantLine(inputTokens: 200, messageId: "msg-002"),
            ],
            projectName: "-my-project",
            sessionId: "session-a",
            to: projectsDir
        )

        let reader = SessionLogReader(projectsURL: projectsDir)
        let first = reader.readAllUsageEntries()
        #expect(first.count == 2, "Initial read should return 2 entries")

        // Add a new JSONL file with 3 entries
        try writeJSONL(
            lines: [
                assistantLine(inputTokens: 300, messageId: "msg-003"),
                assistantLine(inputTokens: 400, messageId: "msg-004"),
                assistantLine(inputTokens: 500, messageId: "msg-005"),
            ],
            projectName: "-my-project",
            sessionId: "session-b",
            to: projectsDir
        )

        // Invalidate and expire TTL so discovery re-enumerates
        reader.invalidate()
        reader.expireDiscoveryTTLForTesting()

        let second = reader.readAllUsageEntries()
        #expect(second.count == 5, "Second read should find all 5 entries (2 original + 3 new)")

        let newMessageIds = second.map(\.messageId)
        #expect(newMessageIds.contains("msg-003"), "New entry msg-003 must be present")
        #expect(newMessageIds.contains("msg-005"), "New entry msg-005 must be present")
    }

    // MARK: - Test 3: Modify existing file — updated entries reflected

    @Test func fullPipeline_modifyExistingFile_updatedEntriesReflected() throws {
        let projectsDir = try makeTempProjectsDir(projectNames: ["-edit-proj"])
        defer { try? FileManager.default.removeItem(at: projectsDir) }

        // Write initial file with 2 entries
        try writeJSONL(
            lines: [
                assistantLine(inputTokens: 100, messageId: "msg-v1-a"),
                assistantLine(inputTokens: 200, messageId: "msg-v1-b"),
            ],
            projectName: "-edit-proj",
            sessionId: "evolving",
            to: projectsDir
        )

        let reader = SessionLogReader(projectsURL: projectsDir)
        let first = reader.readAllUsageEntries()
        #expect(first.count == 2)

        // Sleep so APFS mod-date changes on overwrite
        Thread.sleep(forTimeInterval: 1.0)

        // Overwrite with 3 different entries (new messageIds simulate fresh session data)
        try writeJSONL(
            lines: [
                assistantLine(inputTokens: 300, messageId: "msg-v2-a"),
                assistantLine(inputTokens: 400, messageId: "msg-v2-b"),
                assistantLine(inputTokens: 500, messageId: "msg-v2-c"),
            ],
            projectName: "-edit-proj",
            sessionId: "evolving",
            to: projectsDir
        )

        reader.invalidate()
        reader.expireDiscoveryTTLForTesting()

        let second = reader.readAllUsageEntries()
        // Old entries (msg-v1-*) removed; new entries (msg-v2-*) added
        #expect(second.count == 3, "Modified file: old 2 entries replaced by 3 new entries")

        let ids = Set(second.map(\.messageId))
        #expect(!ids.contains("msg-v1-a"), "Stale entry msg-v1-a must be removed")
        #expect(!ids.contains("msg-v1-b"), "Stale entry msg-v1-b must be removed")
        #expect(ids.contains("msg-v2-a"), "New entry msg-v2-a must be present")
        #expect(ids.contains("msg-v2-c"), "New entry msg-v2-c must be present")
    }

    // MARK: - Test 4: Delete a file — entries removed from results

    @Test func fullPipeline_deleteFile_entriesRemoved() throws {
        let projectsDir = try makeTempProjectsDir(projectNames: ["-del-proj"])
        defer { try? FileManager.default.removeItem(at: projectsDir) }

        // Two session files
        try writeJSONL(
            lines: [
                assistantLine(inputTokens: 100, messageId: "msg-keep-1"),
                assistantLine(inputTokens: 200, messageId: "msg-keep-2"),
            ],
            projectName: "-del-proj",
            sessionId: "keeper",
            to: projectsDir
        )
        try writeJSONL(
            lines: [
                assistantLine(inputTokens: 999, messageId: "msg-gone-1"),
            ],
            projectName: "-del-proj",
            sessionId: "todelete",
            to: projectsDir
        )

        let reader = SessionLogReader(projectsURL: projectsDir)
        let first = reader.readAllUsageEntries()
        #expect(first.count == 3, "Initial read: 3 entries across 2 files")

        // Delete the second file
        let deletedFile = projectsDir
            .appendingPathComponent("-del-proj")
            .appendingPathComponent("todelete.jsonl")
        try FileManager.default.removeItem(at: deletedFile)

        reader.invalidate()
        reader.expireDiscoveryTTLForTesting()

        let second = reader.readAllUsageEntries()
        #expect(second.count == 2, "After deleting file, only 2 entries remain")

        let ids = Set(second.map(\.messageId))
        #expect(!ids.contains("msg-gone-1"), "Deleted file's entry must be removed")
        #expect(ids.contains("msg-keep-1"), "Surviving file's entries must remain")
        #expect(ids.contains("msg-keep-2"), "Surviving file's entries must remain")
    }

    // MARK: - Test 5: Eviction does not affect totals

    @Test func fullPipeline_evictionDoesNotAffectTotals() throws {
        let projectsDir = try makeTempProjectsDir(projectNames: ["-evict-proj"])
        defer { try? FileManager.default.removeItem(at: projectsDir) }

        // Write a JSONL file and immediately backdate it to yesterday
        try writeJSONL(
            lines: [
                assistantLine(inputTokens: 100, outputTokens: 40, messageId: "msg-old-1"),
                assistantLine(inputTokens: 200, outputTokens: 80, messageId: "msg-old-2"),
            ],
            projectName: "-evict-proj",
            sessionId: "yesterday",
            to: projectsDir
        )
        let oldFileURL = projectsDir
            .appendingPathComponent("-evict-proj")
            .appendingPathComponent("yesterday.jsonl")
        try backdateFile(at: oldFileURL)

        let reader = SessionLogReader(projectsURL: projectsDir)

        // First read — triggers eviction of yesterday's file entries
        let first = reader.readAllUsageEntries()
        #expect(first.count == 2)

        // Verify eviction: no live entry arrays for old files
        let liveCount = reader.cacheEntriesWithLiveEntriesCountForTesting()
        #expect(liveCount == 0, "Yesterday's file entries must be evicted from per-file cache after merge")

        // Second read — must return same totals from cachedAllEntries
        // even though per-file entry arrays are nil
        reader.invalidate()
        let second = reader.readAllUsageEntries()
        #expect(second.count == first.count, "Entry count must match after eviction cycle")

        let firstInputTotal = first.reduce(0) { $0 + $1.inputTokens }
        let secondInputTotal = second.reduce(0) { $0 + $1.inputTokens }
        #expect(secondInputTotal == firstInputTotal, "Input token totals must match exactly after eviction")

        let firstOutputTotal = first.reduce(0) { $0 + $1.outputTokens }
        let secondOutputTotal = second.reduce(0) { $0 + $1.outputTokens }
        #expect(secondOutputTotal == firstOutputTotal, "Output token totals must match exactly after eviction")
    }
}

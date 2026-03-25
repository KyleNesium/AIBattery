import Testing
import Foundation
@testable import AIBatteryCore

@Suite("SessionLogReader")
struct SessionLogReaderTests {

    // MARK: - AssistantUsageEntry model

    @Test func assistantUsageEntry_fieldsCorrect() {
        let entry = AssistantUsageEntry(
            timestamp: Date(timeIntervalSince1970: 1000),
            model: "claude-sonnet-4-5-20250929",
            messageId: "msg-123",
            inputTokens: 100,
            outputTokens: 50,
            cacheReadTokens: 200,
            cacheWriteTokens: 30,
            sessionId: "session-1",
            cwd: "/Users/test/project",
            gitBranch: "main",
            toolCallCount: 0
        )
        #expect(entry.model == "claude-sonnet-4-5-20250929")
        #expect(entry.inputTokens == 100)
        #expect(entry.outputTokens == 50)
        #expect(entry.cacheReadTokens == 200)
        #expect(entry.cacheWriteTokens == 30)
        #expect(entry.sessionId == "session-1")
        #expect(entry.cwd == "/Users/test/project")
        #expect(entry.gitBranch == "main")
    }

    // MARK: - SessionEntry decoding

    @Test func sessionEntry_decodesAssistantMessage() throws {
        let json = """
        {
            "type": "assistant",
            "timestamp": "2026-02-17T10:00:00.000Z",
            "sessionId": "abc-123",
            "message": {
                "role": "assistant",
                "model": "claude-sonnet-4-5-20250929",
                "id": "msg-001",
                "usage": {
                    "input_tokens": 500,
                    "output_tokens": 120,
                    "cache_read_input_tokens": 1000,
                    "cache_creation_input_tokens": 0
                }
            }
        }
        """
        let entry = try JSONDecoder().decode(SessionEntry.self, from: Data(json.utf8))
        #expect(entry.type == "assistant")
        #expect(entry.sessionId == "abc-123")
        #expect(entry.message?.model == "claude-sonnet-4-5-20250929")
        #expect(entry.message?.usage?.inputTokens == 500)
        #expect(entry.message?.usage?.outputTokens == 120)
        #expect(entry.message?.usage?.cacheReadInputTokens == 1000)
        #expect(entry.message?.usage?.cacheCreationInputTokens == 0)
    }

    @Test func sessionEntry_decodesMinimalEntry() throws {
        let json = """
        {"type": "user", "timestamp": "2026-02-17T09:00:00.000Z"}
        """
        let entry = try JSONDecoder().decode(SessionEntry.self, from: Data(json.utf8))
        #expect(entry.type == "user")
        #expect(entry.message == nil)
    }

    @Test func sessionEntry_handlesNullUsage() throws {
        let json = """
        {
            "type": "assistant",
            "message": {
                "role": "assistant",
                "model": "claude-sonnet-4-5-20250929"
            }
        }
        """
        let entry = try JSONDecoder().decode(SessionEntry.self, from: Data(json.utf8))
        #expect(entry.message?.usage == nil)
    }

    @Test func sessionEntry_handlesServiceTier() throws {
        let json = """
        {
            "type": "assistant",
            "message": {
                "role": "assistant",
                "model": "claude-sonnet-4-5-20250929",
                "usage": {
                    "input_tokens": 10,
                    "output_tokens": 5,
                    "service_tier": "standard"
                }
            }
        }
        """
        let entry = try JSONDecoder().decode(SessionEntry.self, from: Data(json.utf8))
        // service_tier is an unknown key — decode succeeds without it
        #expect(entry.message?.usage?.inputTokens == 10)
    }

    // MARK: - makeUsageEntry

    @Test func makeUsageEntry_validAssistant_returnsEntry() throws {
        let json = """
        {
            "type": "assistant",
            "timestamp": "2026-02-17T10:00:00.000Z",
            "sessionId": "sess-001",
            "cwd": "/Users/test",
            "message": {
                "role": "assistant",
                "model": "claude-sonnet-4-5-20250929",
                "id": "msg-001",
                "usage": {
                    "input_tokens": 100,
                    "output_tokens": 50,
                    "cache_read_input_tokens": 200,
                    "cache_creation_input_tokens": 10
                }
            }
        }
        """
        let entry = try JSONDecoder().decode(SessionEntry.self, from: Data(json.utf8))
        let result = SessionLogReader.makeUsageEntry(from: entry)
        #expect(result != nil)
        #expect(result?.model == "claude-sonnet-4-5-20250929")
        #expect(result?.inputTokens == 100)
        #expect(result?.outputTokens == 50)
        #expect(result?.cacheReadTokens == 200)
        #expect(result?.cacheWriteTokens == 10)
        #expect(result?.sessionId == "sess-001")
        #expect(result?.messageId == "msg-001")
    }

    @Test func makeUsageEntry_userMessage_returnsNil() throws {
        let json = """
        {"type": "user", "timestamp": "2026-02-17T09:00:00.000Z"}
        """
        let entry = try JSONDecoder().decode(SessionEntry.self, from: Data(json.utf8))
        #expect(SessionLogReader.makeUsageEntry(from: entry) == nil)
    }

    @Test func makeUsageEntry_noUsage_returnsNil() throws {
        let json = """
        {
            "type": "assistant",
            "message": {
                "role": "assistant",
                "model": "claude-sonnet-4-5-20250929"
            }
        }
        """
        let entry = try JSONDecoder().decode(SessionEntry.self, from: Data(json.utf8))
        #expect(SessionLogReader.makeUsageEntry(from: entry) == nil)
    }

    @Test func makeUsageEntry_noModel_returnsNil() throws {
        let json = """
        {
            "type": "assistant",
            "message": {
                "role": "assistant",
                "usage": {
                    "input_tokens": 100,
                    "output_tokens": 50
                }
            }
        }
        """
        let entry = try JSONDecoder().decode(SessionEntry.self, from: Data(json.utf8))
        #expect(SessionLogReader.makeUsageEntry(from: entry) == nil)
    }

    @Test func makeUsageEntry_nullTokens_defaultsToZero() throws {
        let json = """
        {
            "type": "assistant",
            "sessionId": "sess-002",
            "message": {
                "role": "assistant",
                "model": "claude-haiku-3-5-20241022",
                "usage": {}
            }
        }
        """
        let entry = try JSONDecoder().decode(SessionEntry.self, from: Data(json.utf8))
        let result = SessionLogReader.makeUsageEntry(from: entry)
        #expect(result != nil)
        #expect(result?.inputTokens == 0)
        #expect(result?.outputTokens == 0)
        #expect(result?.cacheReadTokens == 0)
        #expect(result?.cacheWriteTokens == 0)
    }

    @Test func makeUsageEntry_usesUUIDWhenNoMessageId() throws {
        let json = """
        {
            "type": "assistant",
            "uuid": "fallback-uuid-123",
            "message": {
                "role": "assistant",
                "model": "claude-sonnet-4-5-20250929",
                "usage": {
                    "input_tokens": 10,
                    "output_tokens": 5
                }
            }
        }
        """
        let entry = try JSONDecoder().decode(SessionEntry.self, from: Data(json.utf8))
        let result = SessionLogReader.makeUsageEntry(from: entry)
        #expect(result?.messageId == "fallback-uuid-123")
    }

    // MARK: - Tool call counting

    @Test func makeUsageEntry_twoToolUseBlocks_returnsToolCallCount2() throws {
        let json = """
        {
            "type": "assistant",
            "timestamp": "2026-02-17T10:00:00.000Z",
            "sessionId": "sess-tool-1",
            "message": {
                "role": "assistant",
                "model": "claude-sonnet-4-5-20250929",
                "id": "msg-tool-1",
                "content": [
                    {"type": "text", "text": "Here are the results"},
                    {"type": "tool_use", "id": "tu-1", "name": "Read", "input": {}},
                    {"type": "tool_use", "id": "tu-2", "name": "Write", "input": {}}
                ],
                "usage": {
                    "input_tokens": 100,
                    "output_tokens": 50
                }
            }
        }
        """
        let entry = try JSONDecoder().decode(SessionEntry.self, from: Data(json.utf8))
        let result = SessionLogReader.makeUsageEntry(from: entry)
        #expect(result?.toolCallCount == 2)
    }

    @Test func makeUsageEntry_noContentField_returnsToolCallCount0() throws {
        let json = """
        {
            "type": "assistant",
            "timestamp": "2026-02-17T10:00:00.000Z",
            "sessionId": "sess-tool-2",
            "message": {
                "role": "assistant",
                "model": "claude-sonnet-4-5-20250929",
                "id": "msg-tool-2",
                "usage": {
                    "input_tokens": 100,
                    "output_tokens": 50
                }
            }
        }
        """
        let entry = try JSONDecoder().decode(SessionEntry.self, from: Data(json.utf8))
        let result = SessionLogReader.makeUsageEntry(from: entry)
        #expect(result?.toolCallCount == 0)
    }

    @Test func makeUsageEntry_onlyTextBlocks_returnsToolCallCount0() throws {
        let json = """
        {
            "type": "assistant",
            "timestamp": "2026-02-17T10:00:00.000Z",
            "sessionId": "sess-tool-3",
            "message": {
                "role": "assistant",
                "model": "claude-sonnet-4-5-20250929",
                "id": "msg-tool-3",
                "content": [
                    {"type": "text", "text": "Hello"},
                    {"type": "text", "text": "World"}
                ],
                "usage": {
                    "input_tokens": 100,
                    "output_tokens": 50
                }
            }
        }
        """
        let entry = try JSONDecoder().decode(SessionEntry.self, from: Data(json.utf8))
        let result = SessionLogReader.makeUsageEntry(from: entry)
        #expect(result?.toolCallCount == 0)
    }

    @Test func makeUsageEntry_mixedContent_returnsToolCallCount3() throws {
        let json = """
        {
            "type": "assistant",
            "timestamp": "2026-02-17T10:00:00.000Z",
            "sessionId": "sess-tool-4",
            "message": {
                "role": "assistant",
                "model": "claude-sonnet-4-5-20250929",
                "id": "msg-tool-4",
                "content": [
                    {"type": "text", "text": "Executing tasks"},
                    {"type": "tool_use", "id": "tu-1", "name": "Read", "input": {}},
                    {"type": "tool_use", "id": "tu-2", "name": "Write", "input": {}},
                    {"type": "tool_use", "id": "tu-3", "name": "Bash", "input": {}}
                ],
                "usage": {
                    "input_tokens": 200,
                    "output_tokens": 80
                }
            }
        }
        """
        let entry = try JSONDecoder().decode(SessionEntry.self, from: Data(json.utf8))
        let result = SessionLogReader.makeUsageEntry(from: entry)
        #expect(result?.toolCallCount == 3)
    }

    @Test func makeUsageEntry_emptyContentArray_returnsToolCallCount0() throws {
        let json = """
        {
            "type": "assistant",
            "timestamp": "2026-02-17T10:00:00.000Z",
            "sessionId": "sess-tool-5",
            "message": {
                "role": "assistant",
                "model": "claude-sonnet-4-5-20250929",
                "id": "msg-tool-5",
                "content": [],
                "usage": {
                    "input_tokens": 100,
                    "output_tokens": 50
                }
            }
        }
        """
        let entry = try JSONDecoder().decode(SessionEntry.self, from: Data(json.utf8))
        let result = SessionLogReader.makeUsageEntry(from: entry)
        #expect(result?.toolCallCount == 0)
    }

    // MARK: - Concurrency: NSLock + pendingInvalidation

    /// Creates a temp projects directory with one project subdir. Returns the projectsURL.
    private func makeTempProjectsDir(id: String = UUID().uuidString) throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("slr-concurrency-\(id)")
        let projectDir = tmp.appendingPathComponent("projects")
            .appendingPathComponent("-test-project")
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        return tmp.appendingPathComponent("projects")
    }

    /// Writes JSONL lines to a named session file inside the first project subdir.
    private func writeJSONL(
        _ lines: [String],
        to projectsDir: URL,
        sessionName: String = "session.jsonl"
    ) throws {
        let projectDir = projectsDir.appendingPathComponent("-test-project")
        let fileURL = projectDir.appendingPathComponent(sessionName)
        let content = lines.joined(separator: "\n") + "\n"
        try Data(content.utf8).write(to: fileURL)
    }

    /// Returns a single valid assistant JSONL line.
    private func assistantLine(
        messageId: String,
        timestamp: String = "2026-02-17T10:00:00.000Z",
        sessionId: String = "ses-1",
        inputTokens: Int = 100,
        outputTokens: Int = 50
    ) -> String {
        """
        {"type":"assistant","timestamp":"\(timestamp)","sessionId":"\(sessionId)","message":{"role":"assistant","model":"claude-sonnet-4-5-20250929","id":"\(messageId)","usage":{"input_tokens":\(inputTokens),"output_tokens":\(outputTokens)}}}
        """
    }

    @Test func invalidate_whenNoScanRunning_clearsCachesDirectly() throws {
        let projectsDir = try makeTempProjectsDir()
        defer { try? FileManager.default.removeItem(at: projectsDir.deletingLastPathComponent()) }

        // Write one entry and prime the cache.
        try writeJSONL([assistantLine(messageId: "msg-001", inputTokens: 100)], to: projectsDir)
        let reader = SessionLogReader(projectsURL: projectsDir)
        let first = reader.readAllUsageEntries()
        #expect(first.count == 1)
        #expect(first[0].inputTokens == 100)

        // Overwrite the file with a different entry.
        // Sleep ensures mod date changes (APFS has 1-second resolution for some APIs).
        Thread.sleep(forTimeInterval: 1.0)
        try writeJSONL([assistantLine(messageId: "msg-001", inputTokens: 9999)], to: projectsDir)

        // invalidate() with no scan running must mark dirty so next read re-scans.
        reader.invalidate()

        // Next read should pick up the changed file rather than returning the stale cache.
        let second = reader.readAllUsageEntries()
        #expect(second.count == 1)
        #expect(second[0].inputTokens == 9999)
    }

    @Test func invalidate_afterScan_nextReadReturnsFreshData() throws {
        let projectsDir = try makeTempProjectsDir()
        defer { try? FileManager.default.removeItem(at: projectsDir.deletingLastPathComponent()) }

        // Write 1 entry, read to populate cache.
        try writeJSONL([assistantLine(messageId: "msg-A01")], to: projectsDir)
        let reader = SessionLogReader(projectsURL: projectsDir)
        let first = reader.readAllUsageEntries()
        #expect(first.count == 1)

        // Write a new file with 2 entries (different session file to guarantee
        // a cache-key miss even if mod date resolution is coarse).
        try writeJSONL(
            [
                assistantLine(messageId: "msg-B01", sessionId: "ses-2"),
                assistantLine(messageId: "msg-B02", sessionId: "ses-2"),
            ],
            to: projectsDir,
            sessionName: "session2.jsonl"
        )

        // invalidate() with lock free — clears cachedAllEntries and discoveredFiles.
        reader.invalidate()

        // Next read must re-scan and return both files' entries.
        let second = reader.readAllUsageEntries()
        #expect(second.count == 3)
    }

    @Test func readAllUsageEntries_returnsSortedByTimestamp() throws {
        let projectsDir = try makeTempProjectsDir()
        defer { try? FileManager.default.removeItem(at: projectsDir.deletingLastPathComponent()) }

        // Write entries with deliberately out-of-order timestamps across two files.
        try writeJSONL(
            [
                assistantLine(messageId: "msg-late",  timestamp: "2026-02-17T12:00:00.000Z"),
                assistantLine(messageId: "msg-early", timestamp: "2026-02-17T08:00:00.000Z"),
            ],
            to: projectsDir,
            sessionName: "file-a.jsonl"
        )
        try writeJSONL(
            [
                assistantLine(messageId: "msg-mid", timestamp: "2026-02-17T10:00:00.000Z"),
            ],
            to: projectsDir,
            sessionName: "file-b.jsonl"
        )

        let reader = SessionLogReader(projectsURL: projectsDir)
        let entries = reader.readAllUsageEntries()

        #expect(entries.count == 3)
        // Verify ascending timestamp order.
        for i in 0..<(entries.count - 1) {
            #expect(entries[i].timestamp <= entries[i + 1].timestamp)
        }
        #expect(entries[0].messageId == "msg-early")
        #expect(entries[1].messageId == "msg-mid")
        #expect(entries[2].messageId == "msg-late")
    }

    @Test func readAllUsageEntries_deduplicatesByMessageId() throws {
        let projectsDir = try makeTempProjectsDir()
        defer { try? FileManager.default.removeItem(at: projectsDir.deletingLastPathComponent()) }

        let sharedId = "msg-shared-001"

        // Same messageId in two different JSONL files.
        try writeJSONL(
            [assistantLine(messageId: sharedId, inputTokens: 111)],
            to: projectsDir,
            sessionName: "file-x.jsonl"
        )
        try writeJSONL(
            [assistantLine(messageId: sharedId, inputTokens: 222)],
            to: projectsDir,
            sessionName: "file-y.jsonl"
        )

        let reader = SessionLogReader(projectsURL: projectsDir)
        let entries = reader.readAllUsageEntries()

        // Only one entry with the shared ID should survive deduplication.
        #expect(entries.count == 1)
        #expect(entries[0].messageId == sharedId)
    }

    @Test func concurrent_readAndInvalidate_noDeadlock() throws {
        let projectsDir = try makeTempProjectsDir()
        defer { try? FileManager.default.removeItem(at: projectsDir.deletingLastPathComponent()) }

        try writeJSONL(
            [
                assistantLine(messageId: "msg-c1"),
                assistantLine(messageId: "msg-c2"),
            ],
            to: projectsDir
        )

        let reader = SessionLogReader(projectsURL: projectsDir)
        let group = DispatchGroup()

        // 10 concurrent readers + 10 concurrent invalidations on separate queues.
        for i in 0..<10 {
            let readQueue = DispatchQueue(label: "test.read.\(i)", attributes: .concurrent)
            let invalidateQueue = DispatchQueue(label: "test.invalidate.\(i)", attributes: .concurrent)

            group.enter()
            readQueue.async {
                _ = reader.readAllUsageEntries()
                group.leave()
            }

            group.enter()
            invalidateQueue.async {
                reader.invalidate()
                group.leave()
            }
        }

        // Must complete well within 5 seconds — any deadlock would hang here.
        let result = group.wait(timeout: .now() + 5)
        #expect(result == .success)
    }

    // MARK: - Dirty-flag fast path

    @Test func notDirty_returnsCachedImmediately() throws {
        let projectsDir = try makeTempProjectsDir()
        defer { try? FileManager.default.removeItem(at: projectsDir.deletingLastPathComponent()) }

        try writeJSONL([assistantLine(messageId: "msg-orig", inputTokens: 100)], to: projectsDir)
        let reader = SessionLogReader(projectsURL: projectsDir)

        let first = reader.readAllUsageEntries()
        #expect(first.count == 1)
        #expect(first[0].inputTokens == 100)

        // Overwrite file with different tokens — do NOT invalidate
        Thread.sleep(forTimeInterval: 1.0)
        try writeJSONL([assistantLine(messageId: "msg-orig", inputTokens: 999)], to: projectsDir)

        // Without invalidation, should return cached result (not 999)
        let second = reader.readAllUsageEntries()
        #expect(second.count == 1)
        #expect(second[0].inputTokens == 100, "Should return cached result without invalidation, not re-parse")
    }

    // MARK: - Incremental cache behavior

    @Test func incrementalRebuild_onlyReParsesChangedFiles() throws {
        let projectsDir = try makeTempProjectsDir()
        defer { try? FileManager.default.removeItem(at: projectsDir.deletingLastPathComponent()) }

        // Write two files with distinct entries
        try writeJSONL(
            [assistantLine(messageId: "msg-A", inputTokens: 100)],
            to: projectsDir,
            sessionName: "file-a.jsonl"
        )
        try writeJSONL(
            [assistantLine(messageId: "msg-B", inputTokens: 200)],
            to: projectsDir,
            sessionName: "file-b.jsonl"
        )

        let reader = SessionLogReader(projectsURL: projectsDir)
        let first = reader.readAllUsageEntries()
        #expect(first.count == 2)

        // Sleep to ensure mod date changes on APFS
        Thread.sleep(forTimeInterval: 1.0)

        // Overwrite file-a with updated tokens (same messageId)
        try writeJSONL(
            [assistantLine(messageId: "msg-A", inputTokens: 999)],
            to: projectsDir,
            sessionName: "file-a.jsonl"
        )
        reader.invalidate()

        let second = reader.readAllUsageEntries()
        #expect(second.count == 2)

        // Changed file re-parsed: msg-A should have updated tokens
        let entryA = second.first { $0.messageId == "msg-A" }
        #expect(entryA?.inputTokens == 999)

        // Unchanged file cached: msg-B keeps original tokens
        let entryB = second.first { $0.messageId == "msg-B" }
        #expect(entryB?.inputTokens == 200)
    }

    @Test func cacheUnbounded_noEvictionAt250Files() throws {
        let projectsDir = try makeTempProjectsDir()
        defer { try? FileManager.default.removeItem(at: projectsDir.deletingLastPathComponent()) }

        // Write 250 separate JSONL files, each with one unique entry
        for i in 0..<250 {
            try writeJSONL(
                [assistantLine(messageId: "msg-\(i)", inputTokens: i)],
                to: projectsDir,
                sessionName: "session-\(String(format: "%03d", i)).jsonl"
            )
        }

        let reader = SessionLogReader(projectsURL: projectsDir)
        let first = reader.readAllUsageEntries()
        #expect(first.count == 250, "All 250 entries should be present (no eviction)")

        // Read again — still 250 (no eviction between reads)
        let second = reader.readAllUsageEntries()
        #expect(second.count == 250, "Cache should hold all 250 entries without eviction")
    }

    @Test func deletedFile_removedFromResults() throws {
        let projectsDir = try makeTempProjectsDir()
        defer { try? FileManager.default.removeItem(at: projectsDir.deletingLastPathComponent()) }

        try writeJSONL(
            [assistantLine(messageId: "msg-A")],
            to: projectsDir,
            sessionName: "file-a.jsonl"
        )
        try writeJSONL(
            [assistantLine(messageId: "msg-B")],
            to: projectsDir,
            sessionName: "file-b.jsonl"
        )

        let reader = SessionLogReader(projectsURL: projectsDir)
        let first = reader.readAllUsageEntries()
        #expect(first.count == 2)

        // Delete file-b
        let projectDir = projectsDir.appendingPathComponent("-test-project")
        try FileManager.default.removeItem(at: projectDir.appendingPathComponent("file-b.jsonl"))

        reader.invalidate()

        let second = reader.readAllUsageEntries()
        #expect(second.count == 1)
        #expect(second[0].messageId == "msg-A")
    }

    @Test func incrementalRebuild_preservesDeduplication() throws {
        let projectsDir = try makeTempProjectsDir()
        defer { try? FileManager.default.removeItem(at: projectsDir.deletingLastPathComponent()) }

        // Same messageId in two different files
        try writeJSONL(
            [assistantLine(messageId: "msg-SHARED", inputTokens: 100)],
            to: projectsDir,
            sessionName: "file-a.jsonl"
        )
        try writeJSONL(
            [assistantLine(messageId: "msg-SHARED", inputTokens: 200)],
            to: projectsDir,
            sessionName: "file-b.jsonl"
        )

        let reader = SessionLogReader(projectsURL: projectsDir)
        let first = reader.readAllUsageEntries()
        #expect(first.count == 1, "Duplicate messageId should be deduped")

        // Sleep to ensure mod date changes
        Thread.sleep(forTimeInterval: 1.0)

        // Modify file-a with same shared messageId but different tokens
        try writeJSONL(
            [assistantLine(messageId: "msg-SHARED", inputTokens: 300)],
            to: projectsDir,
            sessionName: "file-a.jsonl"
        )
        reader.invalidate()

        let second = reader.readAllUsageEntries()
        #expect(second.count == 1, "Deduplication should be preserved after incremental rebuild")
    }
}

import Foundation
import Testing
@testable import AIBatteryCore

/// Full-scale check against the developer's real `~/.claude/projects` tree. Opt-in only
/// (`AIBATTERY_REAL_CLAUDE_LOGS=1`) — CI has no logs and the suite must stay hermetic.
@Suite("SessionLogReader — real data (opt-in)")
struct SessionLogReaderRealDataTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["AIBATTERY_REAL_CLAUDE_LOGS"] == "1"))
    func scansRealProjectsTreeQuicklyAndConsistently() throws {
        let root = ClaudePaths.projects
        try #require(FileManager.default.fileExists(atPath: root.path), "no ~/.claude/projects on this machine")
        let reader = SessionLogReader(projectsURL: root)

        let coldStart = Date()
        let entries = reader.readAllUsageEntries()
        let cold = Date().timeIntervalSince(coldStart)
        let warmStart = Date()
        let again = reader.readAllUsageEntries()
        let warm = Date().timeIntervalSince(warmStart)
        reader.invalidate()
        let dirtyStart = Date()
        let rebuilt = reader.readAllUsageEntries()
        let dirty = Date().timeIntervalSince(dirtyStart)

        print("REAL-DATA-CLAUDE cold=\(String(format: "%.2f", cold))s warm=\(String(format: "%.4f", warm))s dirtyRebuild=\(String(format: "%.2f", dirty))s entries=\(entries.count) sessions=\(Set(entries.map(\.sessionId)).count) corrupt=\(reader.lastCorruptLineCount)")

        #expect(!entries.isEmpty)
        #expect(again.count == entries.count)
        #expect(rebuilt.count >= entries.count) // logs may be written concurrently
        #expect(entries.map(\.timestamp) == entries.map(\.timestamp).sorted())
        #expect(Set(entries.map(\.messageId)).count == entries.count)
        #expect(warm < 0.05)
    }

    /// What the incremental tail parse is for: the active session file is 7-10 MB and
    /// used to be re-read from byte 0 on every debounced write. Copies the largest real
    /// session file, appends one line, and times the re-read both ways.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["AIBATTERY_REAL_CLAUDE_LOGS"] == "1"))
    func appendToTheLargestRealFileIsCheaperThanAFullReparse() throws {
        let root = ClaudePaths.projects
        try #require(FileManager.default.fileExists(atPath: root.path), "no ~/.claude/projects on this machine")

        // Largest .jsonl in the real tree — the one a live session is writing.
        var largest: (url: URL, size: UInt64)?
        if let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let url as URL in walker where url.pathExtension == "jsonl" {
                let size = UInt64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
                if size > (largest?.size ?? 0) {
                    largest = (url, size)
                }
            }
        }
        let source = try #require(largest, "no session files found")

        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("slr-tail-\(UUID().uuidString)")
        let projectDir = tmp.appendingPathComponent("projects").appendingPathComponent("-bench")
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let copy = projectDir.appendingPathComponent("session.jsonl")
        try FileManager.default.copyItem(at: source.url, to: copy)
        // `copyItem` preserves the source's modification date. The per-file cache evicts
        // entries for files older than today, and an evicted file always re-parses in
        // full — so a stale date here would benchmark the wrong path.
        try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: copy.path)
        let projectsDir = tmp.appendingPathComponent("projects")

        let appended = #"{"type":"assistant","timestamp":"2026-10-31T12:00:00.000Z","sessionId":"bench","message":{"role":"assistant","model":"claude-sonnet-4-5-20250929","id":"bench-append","usage":{"input_tokens":1,"output_tokens":1}}}"# + "\n"

        func appendLine() throws {
            let handle = try FileHandle(forWritingTo: copy)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(appended.utf8))
        }

        // Incremental: prime, append, re-read.
        let incremental = SessionLogReader(projectsURL: projectsDir)
        _ = incremental.readAllUsageEntries()
        try appendLine()
        incremental.invalidate()
        let tailStart = Date()
        let tailEntries = incremental.readAllUsageEntries()
        let tailSeconds = Date().timeIntervalSince(tailStart)

        // Full: a reader that has never seen this file parses it from byte 0.
        let fullStart = Date()
        let fullEntries = SessionLogReader(projectsURL: projectsDir).readAllUsageEntries()
        let fullSeconds = Date().timeIntervalSince(fullStart)

        print("REAL-DATA-TAILPARSE file=\(source.size / 1_048_576)MB tail=\(String(format: "%.1f", tailSeconds * 1_000))ms full=\(String(format: "%.1f", fullSeconds * 1_000))ms entries=\(tailEntries.count)")

        // Same answer, both ways — the point of the whole exercise.
        #expect(tailEntries.count == fullEntries.count)
        #expect(tailEntries.map(\.messageId).sorted() == fullEntries.map(\.messageId).sorted())
        let tailTools = tailEntries.reduce(0) { $0 + $1.toolCallCount }
        let fullTools = fullEntries.reduce(0) { $0 + $1.toolCallCount }
        #expect(tailTools == fullTools, "tool-call coalescing must survive the resume boundary")
        #expect(tailSeconds < fullSeconds)
    }
}

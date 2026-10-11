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
}

import Testing
import Foundation
@testable import AIBatteryCore

@Suite("SessionLogReader — file safety checks")
struct SessionLogReaderSymlinkTests {

    private let fm = FileManager.default

    private func makeTempDir() -> URL {
        let dir = fm.temporaryDirectory.appendingPathComponent("slr-symlink-\(UUID().uuidString)")
        try! fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func cleanup(_ url: URL) {
        try? fm.removeItem(at: url)
    }

    private func writeJSONL(_ content: String, to url: URL) throws {
        try Data(content.utf8).write(to: url)
    }

    private let sampleLine = """
    {"type":"assistant","timestamp":"2026-02-17T10:00:00.000Z","sessionId":"s1","message":{"role":"assistant","model":"claude-sonnet-4-5-20250929","id":"msg-1","usage":{"input_tokens":100,"output_tokens":50}}}
    """

    // MARK: - Normal files are included

    @Test func discoverFiles_normalFiles_included() throws {
        let base = makeTempDir()
        defer { cleanup(base) }

        let projectDir = base.appendingPathComponent("my-project")
        try fm.createDirectory(at: projectDir, withIntermediateDirectories: true)
        let jsonlFile = projectDir.appendingPathComponent("session.jsonl")
        try writeJSONL(sampleLine, to: jsonlFile)

        let reader = SessionLogReader(projectsURL: base)
        let entries = reader.readAllUsageEntries()
        #expect(entries.count == 1)
    }

    // MARK: - Symlink outside boundary is excluded

    @Test func discoverFiles_symlinkOutsideBoundary_excluded() throws {
        let base = makeTempDir()
        let outsideDir = makeTempDir()
        defer {
            cleanup(base)
            cleanup(outsideDir)
        }

        // Create a real JSONL file outside the projects directory
        let outsideFile = outsideDir.appendingPathComponent("secret.jsonl")
        try writeJSONL(sampleLine, to: outsideFile)

        // Create a project dir with a symlink pointing outside
        let projectDir = base.appendingPathComponent("evil-project")
        try fm.createDirectory(at: projectDir, withIntermediateDirectories: true)
        let symlinkPath = projectDir.appendingPathComponent("linked.jsonl")
        try fm.createSymbolicLink(at: symlinkPath, withDestinationURL: outsideFile)

        let reader = SessionLogReader(projectsURL: base)
        let entries = reader.readAllUsageEntries()
        // The symlink pointing outside the boundary should be filtered out
        #expect(entries.isEmpty)
    }

    // MARK: - Symlink within boundary is included

    @Test func discoverFiles_symlinkWithinBoundary_included() throws {
        let base = makeTempDir()
        defer { cleanup(base) }

        // Create two project dirs, one with the real file, one with a symlink to it
        let projectA = base.appendingPathComponent("project-a")
        try fm.createDirectory(at: projectA, withIntermediateDirectories: true)
        let realFile = projectA.appendingPathComponent("session.jsonl")
        try writeJSONL(sampleLine, to: realFile)

        let projectB = base.appendingPathComponent("project-b")
        try fm.createDirectory(at: projectB, withIntermediateDirectories: true)
        let symlinkPath = projectB.appendingPathComponent("linked.jsonl")
        try fm.createSymbolicLink(at: symlinkPath, withDestinationURL: realFile)

        let reader = SessionLogReader(projectsURL: base)
        let entries = reader.readAllUsageEntries()
        // Both files should be found (same messageId, so deduplication will collapse to 1)
        #expect(entries.count == 1)
    }

    // MARK: - JSONL file size guard

    @Test func maxJSONLFileSize_is50MB() {
        #expect(SessionLogReader.maxJSONLFileSize == 50_000_000)
    }

    @Test func cachedRead_oversizedFile_returnsEmpty() throws {
        let base = makeTempDir()
        defer { cleanup(base) }

        let projectDir = base.appendingPathComponent("big-project")
        try fm.createDirectory(at: projectDir, withIntermediateDirectories: true)

        // Create a file just over the limit (write sparse — only need size, not valid JSONL)
        let bigFile = projectDir.appendingPathComponent("huge.jsonl")
        let handle = FileManager.default.createFile(atPath: bigFile.path, contents: nil)
        #expect(handle == true)
        let fh = try FileHandle(forWritingTo: bigFile)
        try fh.truncate(atOffset: SessionLogReader.maxJSONLFileSize + 1)
        try fh.close()

        let reader = SessionLogReader(projectsURL: base)
        let entries = reader.readAllUsageEntries()
        #expect(entries.isEmpty)
    }

    // MARK: - World-writable file check

    @Test func cachedRead_worldWritableFile_returnsEmpty() throws {
        let base = makeTempDir()
        defer { cleanup(base) }

        let projectDir = base.appendingPathComponent("writable-project")
        try fm.createDirectory(at: projectDir, withIntermediateDirectories: true)
        let jsonlFile = projectDir.appendingPathComponent("session.jsonl")
        try writeJSONL(sampleLine, to: jsonlFile)

        // Make the file world-writable
        try fm.setAttributes([.posixPermissions: 0o666], ofItemAtPath: jsonlFile.path)

        let reader = SessionLogReader(projectsURL: base)
        let entries = reader.readAllUsageEntries()
        #expect(entries.isEmpty)
    }
}

import Testing
import Foundation
@testable import AIBatteryCore

@Suite("SessionLogReader — Symlink Boundary Check")
struct SessionLogReaderSymlinkTests {

    /// Files that resolve inside the projects directory should be kept.
    @Test func discoverFiles_keepsFilesInsideProjectsDir() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("symlink-test-\(UUID().uuidString)")
        let projectsDir = tmpDir.appendingPathComponent("projects")
        let projectDir = projectsDir.appendingPathComponent("test-project")

        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        let jsonlFile = projectDir.appendingPathComponent("session.jsonl")
        try Data("{}".utf8).write(to: jsonlFile)

        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let reader = SessionLogReader(projectsURL: projectsDir)
        let files = reader.discoverJSONLFilesForTesting()

        #expect(files.contains(where: { $0.lastPathComponent == "session.jsonl" }))
    }

    /// A symlink pointing outside the projects directory should be filtered out.
    @Test func discoverFiles_excludesSymlinkOutsideProjectsDir() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("symlink-test-\(UUID().uuidString)")
        let projectsDir = tmpDir.appendingPathComponent("projects")
        let projectDir = projectsDir.appendingPathComponent("test-project")
        let outsideDir = tmpDir.appendingPathComponent("outside")

        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outsideDir, withIntermediateDirectories: true)

        // Create a real file outside the projects dir
        let outsideFile = outsideDir.appendingPathComponent("secret.jsonl")
        try Data("{}".utf8).write(to: outsideFile)

        // Symlink from inside projects → outside
        let symlinkPath = projectDir.appendingPathComponent("linked.jsonl")
        try FileManager.default.createSymbolicLink(at: symlinkPath, withDestinationURL: outsideFile)

        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let reader = SessionLogReader(projectsURL: projectsDir)
        let files = reader.discoverJSONLFilesForTesting()

        #expect(!files.contains(where: { $0.lastPathComponent == "linked.jsonl" }))
    }
}

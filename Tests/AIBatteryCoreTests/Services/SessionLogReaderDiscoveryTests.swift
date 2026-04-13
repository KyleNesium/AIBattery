import Testing
import Foundation
@testable import AIBatteryCore

@Suite("SessionLogReader — TTL-based Discovery Fallback")
@MainActor
struct SessionLogReaderDiscoveryTests {

    // MARK: - Helpers

    private func makeProjectsDir() throws -> URL {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("discovery-ttl-test-\(UUID().uuidString)")
        let projectsDir = tmpDir.appendingPathComponent("projects")
        let projectDir = projectsDir.appendingPathComponent("-test-project")
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        return projectsDir
    }

    private func addJSONLFile(to projectsDir: URL, name: String = "session.jsonl") throws -> URL {
        let projectDir = try FileManager.default.contentsOfDirectory(
            at: projectsDir,
            includingPropertiesForKeys: nil
        ).first ?? projectsDir.appendingPathComponent("-test-project")
        let file = projectDir.appendingPathComponent(name)
        try Data("{}".utf8).write(to: file)
        return file
    }

    /// Creates a named project directory inside the projects root and returns its URL.
    private func makeProjectDir(in projectsDir: URL, name: String) throws -> URL {
        let dir = projectsDir.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Adds a JSONL file to a specific project directory.
    private func addJSONLFileToProject(in projectDir: URL, name: String) throws -> URL {
        let file = projectDir.appendingPathComponent(name)
        try Data("{}".utf8).write(to: file)
        return file
    }

    // MARK: - TTL Constant

    @Test func discoveryTTL_is60Seconds() {
        #expect(SessionLogReader.discoveryTTL == 60)
    }

    // MARK: - Cache hit within TTL

    @Test func discovery_returnsCachedResultWithinTTL() throws {
        let projectsDir = try makeProjectsDir()
        defer { try? FileManager.default.removeItem(at: projectsDir.deletingLastPathComponent()) }
        try addJSONLFile(to: projectsDir)

        let reader = SessionLogReader(projectsURL: projectsDir)

        let first = reader.discoverJSONLFilesForTesting()
        let second = reader.discoverJSONLFilesForTesting()

        // Both calls return the same cached result (referencing the same file)
        #expect(first.count == second.count)
        #expect(first.map(\.path).sorted() == second.map(\.path).sorted())
    }

    // MARK: - TTL expiry forces re-enumeration

    @Test func discovery_reEnumeratesAfterTTLExpiry() throws {
        let projectsDir = try makeProjectsDir()
        defer { try? FileManager.default.removeItem(at: projectsDir.deletingLastPathComponent()) }
        try addJSONLFile(to: projectsDir, name: "first.jsonl")

        let reader = SessionLogReader(projectsURL: projectsDir)

        // Prime the cache
        let first = reader.discoverJSONLFilesForTesting()
        #expect(first.count == 1)

        // Add a new file — we do NOT touch dir mod dates manually
        // (on macOS adding a file updates dir mod date, so we need to simulate
        //  the TTL expiry case: expire the TTL then add the file)
        reader.expireDiscoveryTTLForTesting()
        try addJSONLFile(to: projectsDir, name: "second.jsonl")

        let second = reader.discoverJSONLFilesForTesting()
        #expect(second.count == 2)
    }

    // MARK: - invalidate() resets TTL timestamp

    @Test func invalidate_resetsLastFullEnumerationDate() throws {
        let projectsDir = try makeProjectsDir()
        defer { try? FileManager.default.removeItem(at: projectsDir.deletingLastPathComponent()) }
        try addJSONLFile(to: projectsDir)

        let reader = SessionLogReader(projectsURL: projectsDir)

        // Prime the cache so lastFullEnumerationDate is set
        _ = reader.discoverJSONLFilesForTesting()

        // Invalidate should reset TTL
        reader.invalidate()

        // After invalidate + adding a new file, re-enumeration should pick it up
        try addJSONLFile(to: projectsDir, name: "after-invalidate.jsonl")
        let files = reader.discoverJSONLFilesForTesting()
        #expect(files.count == 2)
    }

    // MARK: - Per-directory incremental discovery

    @Test func unchangedDirectory_skipsEnumeration() throws {
        // Create projects root with two project dirs, each containing a JSONL file
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("discovery-incr-test-\(UUID().uuidString)")
        let projectsDir = tmpDir.appendingPathComponent("projects")
        try FileManager.default.createDirectory(at: projectsDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let dirA = try makeProjectDir(in: projectsDir, name: "-project-a")
        let dirB = try makeProjectDir(in: projectsDir, name: "-project-b")
        try addJSONLFileToProject(in: dirA, name: "a.jsonl")
        try addJSONLFileToProject(in: dirB, name: "b.jsonl")

        let reader = SessionLogReader(projectsURL: projectsDir)

        // Prime cache — both dirs enumerated
        let first = reader.discoverJSONLFilesForTesting()
        #expect(first.count == 2)

        // Invalidate (clears discoveredFiles but preserves per-dir cache)
        reader.invalidate()

        // Second discovery — both dirs unchanged, should still return both files
        let second = reader.discoverJSONLFilesForTesting()
        #expect(second.count == 2)
        #expect(Set(second.map(\.lastPathComponent)) == Set(["a.jsonl", "b.jsonl"]))
    }

    @Test func newDirectoryDiscovered_afterInvalidation() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("discovery-newdir-test-\(UUID().uuidString)")
        let projectsDir = tmpDir.appendingPathComponent("projects")
        try FileManager.default.createDirectory(at: projectsDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let dirA = try makeProjectDir(in: projectsDir, name: "-project-a")
        try addJSONLFileToProject(in: dirA, name: "a.jsonl")

        let reader = SessionLogReader(projectsURL: projectsDir)

        let first = reader.discoverJSONLFilesForTesting()
        #expect(first.count == 1)

        // Add a new project directory with a file
        let dirB = try makeProjectDir(in: projectsDir, name: "-project-b")
        try addJSONLFileToProject(in: dirB, name: "b.jsonl")

        // Invalidate so discovery re-checks
        reader.invalidate()

        let second = reader.discoverJSONLFilesForTesting()
        #expect(second.count == 2)
        #expect(second.map(\.lastPathComponent).sorted() == ["a.jsonl", "b.jsonl"])
    }

    @Test func deletedDirectory_filesRemoved() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("discovery-deldir-test-\(UUID().uuidString)")
        let projectsDir = tmpDir.appendingPathComponent("projects")
        try FileManager.default.createDirectory(at: projectsDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let dirA = try makeProjectDir(in: projectsDir, name: "-project-a")
        let dirB = try makeProjectDir(in: projectsDir, name: "-project-b")
        try addJSONLFileToProject(in: dirA, name: "a.jsonl")
        try addJSONLFileToProject(in: dirB, name: "b.jsonl")

        let reader = SessionLogReader(projectsURL: projectsDir)

        let first = reader.discoverJSONLFilesForTesting()
        #expect(first.count == 2)

        // Delete project B
        try FileManager.default.removeItem(at: dirB)

        // Invalidate so discovery re-checks
        reader.invalidate()

        let second = reader.discoverJSONLFilesForTesting()
        #expect(second.count == 1)
        #expect(second.first?.lastPathComponent == "a.jsonl")
    }
}

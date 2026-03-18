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
}

import Testing
import Foundation
@testable import AIBatteryCore

@Suite("SecureNetworking")
struct SecureNetworkingTests {

    @Test func maxResponseBytes_is2MB() {
        #expect(SecureNetworking.maxResponseBytes == 2_000_000)
    }

    @Test func session_isEphemeral() {
        let config = SecureNetworking.session.configuration
        // Ephemeral sessions have no disk cache and no persistent storage
        #expect(config.urlCache?.diskCapacity == 0)
        #expect(config.httpCookieStorage == nil)
    }

    @Test func session_isSingleton() {
        let a = SecureNetworking.session
        let b = SecureNetworking.session
        #expect(a === b)
    }

    @Test func worldWritableBit_isCorrect() {
        #expect(SecureNetworking.worldWritableBit == 0o002)
    }

    // MARK: - isWorldWritable

    @Test func isWorldWritable_normalFile_returnsFalse() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sn-test-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("test".utf8).write(to: url)

        // Default permissions (0644) — not world-writable
        #expect(SecureNetworking.isWorldWritable(atPath: url.path) == false)
    }

    @Test func isWorldWritable_worldWritableFile_returnsTrue() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sn-test-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("test".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o666], ofItemAtPath: url.path)

        #expect(SecureNetworking.isWorldWritable(atPath: url.path) == true)
    }

    @Test func isWorldWritable_nonexistentFile_returnsFalse() {
        #expect(SecureNetworking.isWorldWritable(atPath: "/nonexistent/path/file.txt") == false)
    }
}

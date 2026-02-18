import Testing
import Foundation
@testable import AIBatteryCore

@Suite("SessionEntry")
struct SessionEntryTests {

    // MARK: - Codable decode

    @Test func decode_fullEntry() throws {
        let json = """
        {
            "type": "assistant",
            "timestamp": "2025-06-15T10:30:00Z",
            "sessionId": "session-abc",
            "uuid": "uuid-123",
            "cwd": "/Users/test/project",
            "gitBranch": "main",
            "message": {
                "role": "assistant",
                "model": "claude-opus-4-6",
                "id": "msg-001",
                "usage": {
                    "input_tokens": 1000,
                    "output_tokens": 500,
                    "cache_creation_input_tokens": 200,
                    "cache_read_input_tokens": 100,
                    "service_tier": "standard"
                }
            }
        }
        """
        let entry = try JSONDecoder().decode(SessionEntry.self, from: Data(json.utf8))
        #expect(entry.type == "assistant")
        #expect(entry.sessionId == "session-abc")
        #expect(entry.cwd == "/Users/test/project")
        #expect(entry.gitBranch == "main")
        #expect(entry.message?.role == "assistant")
        #expect(entry.message?.model == "claude-opus-4-6")
        #expect(entry.message?.usage?.input_tokens == 1000)
        #expect(entry.message?.usage?.output_tokens == 500)
        #expect(entry.message?.usage?.cache_creation_input_tokens == 200)
        #expect(entry.message?.usage?.cache_read_input_tokens == 100)
    }

    @Test func decode_minimalEntry() throws {
        let json = """
        {
            "type": "user"
        }
        """
        let entry = try JSONDecoder().decode(SessionEntry.self, from: Data(json.utf8))
        #expect(entry.type == "user")
        #expect(entry.sessionId == nil)
        #expect(entry.message == nil)
        #expect(entry.cwd == nil)
    }

    @Test func decode_missingUsage() throws {
        let json = """
        {
            "type": "assistant",
            "sessionId": "s1",
            "message": {
                "role": "assistant",
                "model": "claude-opus-4-6"
            }
        }
        """
        let entry = try JSONDecoder().decode(SessionEntry.self, from: Data(json.utf8))
        #expect(entry.message?.usage == nil)
        #expect(entry.message?.model == "claude-opus-4-6")
    }

    // MARK: - Codable round-trip

    @Test func encode_decode_roundTrip() throws {
        let original = SessionEntry(
            type: "assistant",
            timestamp: "2025-01-01T00:00:00Z",
            sessionId: "s-round",
            message: SessionEntry.SessionMessage(
                role: "assistant",
                model: "claude-haiku-4-5-20251001",
                usage: SessionEntry.TokenUsage(
                    input_tokens: 500,
                    output_tokens: 200,
                    cache_creation_input_tokens: 0,
                    cache_read_input_tokens: 50,
                    service_tier: nil
                ),
                id: "msg-rt"
            ),
            uuid: "u1",
            cwd: "/tmp",
            gitBranch: "feat/test"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SessionEntry.self, from: data)
        #expect(decoded.type == "assistant")
        #expect(decoded.sessionId == "s-round")
        #expect(decoded.message?.model == "claude-haiku-4-5-20251001")
        #expect(decoded.message?.usage?.input_tokens == 500)
        #expect(decoded.gitBranch == "feat/test")
    }
}

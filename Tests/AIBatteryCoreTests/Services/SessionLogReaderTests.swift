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
            gitBranch: "main"
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
}

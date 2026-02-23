import Testing
import Foundation
@testable import AIBatteryCore

@Suite("StatsCacheReader")
struct StatsCacheReaderTests {

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("test-stats-cache-\(UUID().uuidString).json")
    }

    private func writeJSON(_ json: String, to url: URL) throws {
        try Data(json.utf8).write(to: url)
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Basic read

    @Test func read_validFile_decodesStatsCache() throws {
        let url = tempURL()
        defer { cleanup(url) }
        try writeJSON(Self.minimalJSON, to: url)

        let reader = StatsCacheReader(fileURL: url)
        let result = reader.read()

        #expect(result != nil)
        #expect(result?.version == 1)
        #expect(result?.totalSessions == 5)
        #expect(result?.totalMessages == 42)
        #expect(result?.firstSessionDate == "2025-01-01T00:00:00.000Z")
    }

    @Test func read_missingFile_returnsNil() {
        let url = tempURL()
        let reader = StatsCacheReader(fileURL: url)
        #expect(reader.read() == nil)
    }

    @Test func read_invalidJSON_returnsNil() throws {
        let url = tempURL()
        defer { cleanup(url) }
        try writeJSON("{ not valid json }", to: url)

        let reader = StatsCacheReader(fileURL: url)
        #expect(reader.read() == nil)
    }

    @Test func read_emptyObject_returnsNil() throws {
        let url = tempURL()
        defer { cleanup(url) }
        try writeJSON("{}", to: url)

        let reader = StatsCacheReader(fileURL: url)
        #expect(reader.read() == nil)
    }

    // MARK: - Caching

    @Test func read_cachesSameResult() throws {
        let url = tempURL()
        defer { cleanup(url) }
        try writeJSON(Self.minimalJSON, to: url)

        let reader = StatsCacheReader(fileURL: url)
        let first = reader.read()
        let second = reader.read()

        #expect(first != nil)
        #expect(second != nil)
        #expect(first?.totalMessages == second?.totalMessages)
    }

    @Test func read_returnsUpdatedDataAfterFileChange() throws {
        let url = tempURL()
        defer { cleanup(url) }
        try writeJSON(Self.minimalJSON, to: url)

        let reader = StatsCacheReader(fileURL: url)
        let first = reader.read()
        #expect(first?.totalMessages == 42)

        // Simulate file change: small delay to ensure mod date changes
        Thread.sleep(forTimeInterval: 0.05)
        let updated = Self.minimalJSON.replacingOccurrences(of: "\"totalMessages\": 42", with: "\"totalMessages\": 100")
        try writeJSON(updated, to: url)

        let second = reader.read()
        #expect(second?.totalMessages == 100)
    }

    // MARK: - Invalidate

    @Test func invalidate_clearsCacheForFreshRead() throws {
        let url = tempURL()
        defer { cleanup(url) }
        try writeJSON(Self.minimalJSON, to: url)

        let reader = StatsCacheReader(fileURL: url)
        _ = reader.read()

        reader.invalidate()

        // Delete the file so next read returns nil (proves cache was cleared)
        cleanup(url)
        #expect(reader.read() == nil)
    }

    // MARK: - Full payload

    @Test func read_fullPayload_decodesAllFields() throws {
        let url = tempURL()
        defer { cleanup(url) }
        try writeJSON(Self.fullJSON, to: url)

        let reader = StatsCacheReader(fileURL: url)
        let result = reader.read()

        #expect(result != nil)
        #expect(result?.version == 1)
        #expect(result?.lastComputedDate == "2025-06-15")
        #expect(result?.totalSessions == 10)
        #expect(result?.totalMessages == 200)

        // Daily activity
        #expect(result?.dailyActivity.count == 2)
        #expect(result?.dailyActivity[0].date == "2025-06-14")
        #expect(result?.dailyActivity[0].messageCount == 80)
        #expect(result?.dailyActivity[0].toolCallCount == 15)
        #expect(result?.dailyActivity[1].date == "2025-06-15")

        // Daily model tokens
        #expect(result?.dailyModelTokens.count == 1)
        #expect(result?.dailyModelTokens[0].tokensByModel["claude-sonnet-4-5-20250929"] == 50000)

        // Model usage
        #expect(result?.modelUsage.count == 1)
        let sonnet = result?.modelUsage["claude-sonnet-4-5-20250929"]
        #expect(sonnet?.inputTokens == 10000)
        #expect(sonnet?.outputTokens == 5000)
        #expect(sonnet?.cacheReadInputTokens == 2000)
        #expect(sonnet?.cacheCreationInputTokens == 500)

        // Longest session
        #expect(result?.longestSession?.sessionId == "sess-abc")
        #expect(result?.longestSession?.duration == 7_200_000)
        #expect(result?.longestSession?.messageCount == 30)

        // Hour counts
        #expect(result?.hourCounts["14"] == 25)
        #expect(result?.hourCounts["15"] == 18)

        // First session
        #expect(result?.firstSessionDate == "2025-01-10T08:30:00.000Z")
    }

    // MARK: - DailyModelTokens decoding

    @Test func dailyModelTokens_decodesCorrectly() throws {
        let json = """
        {"date": "2025-06-15", "tokensByModel": {"claude-opus-4-6": 100000, "claude-sonnet-4-5-20250929": 50000}}
        """
        let decoded = try JSONDecoder().decode(DailyModelTokens.self, from: Data(json.utf8))
        #expect(decoded.date == "2025-06-15")
        #expect(decoded.tokensByModel.count == 2)
        #expect(decoded.tokensByModel["claude-opus-4-6"] == 100000)
    }

    @Test func dailyModelTokens_emptyModels() throws {
        let json = """
        {"date": "2025-06-15", "tokensByModel": {}}
        """
        let decoded = try JSONDecoder().decode(DailyModelTokens.self, from: Data(json.utf8))
        #expect(decoded.tokensByModel.isEmpty)
    }

    // MARK: - ModelUsageEntry decoding

    @Test func modelUsageEntry_decodesAllFields() throws {
        let json = """
        {"inputTokens": 1000, "outputTokens": 500, "cacheReadInputTokens": 200, "cacheCreationInputTokens": 50, "webSearchRequests": 3, "contextWindow": 200000, "maxOutputTokens": 8192}
        """
        let decoded = try JSONDecoder().decode(ModelUsageEntry.self, from: Data(json.utf8))
        #expect(decoded.inputTokens == 1000)
        #expect(decoded.outputTokens == 500)
        #expect(decoded.cacheReadInputTokens == 200)
        #expect(decoded.cacheCreationInputTokens == 50)
        #expect(decoded.webSearchRequests == 3)
        #expect(decoded.contextWindow == 200000)
        #expect(decoded.maxOutputTokens == 8192)
    }

    @Test func modelUsageEntry_optionalFieldsMissing() throws {
        let json = """
        {"inputTokens": 100, "outputTokens": 50, "cacheReadInputTokens": 0, "cacheCreationInputTokens": 0}
        """
        let decoded = try JSONDecoder().decode(ModelUsageEntry.self, from: Data(json.utf8))
        #expect(decoded.webSearchRequests == nil)
        #expect(decoded.contextWindow == nil)
        #expect(decoded.maxOutputTokens == nil)
    }

    // MARK: - Test JSON

    private static let minimalJSON = """
    {
        "version": 1,
        "lastComputedDate": "2025-06-15",
        "dailyActivity": [],
        "dailyModelTokens": [],
        "modelUsage": {},
        "totalSessions": 5,
        "totalMessages": 42,
        "longestSession": null,
        "firstSessionDate": "2025-01-01T00:00:00.000Z",
        "hourCounts": {}
    }
    """

    private static let fullJSON = """
    {
        "version": 1,
        "lastComputedDate": "2025-06-15",
        "dailyActivity": [
            {"date": "2025-06-14", "messageCount": 80, "sessionCount": 3, "toolCallCount": 15},
            {"date": "2025-06-15", "messageCount": 120, "sessionCount": 7, "toolCallCount": 30}
        ],
        "dailyModelTokens": [
            {"date": "2025-06-15", "tokensByModel": {"claude-sonnet-4-5-20250929": 50000}}
        ],
        "modelUsage": {
            "claude-sonnet-4-5-20250929": {
                "inputTokens": 10000,
                "outputTokens": 5000,
                "cacheReadInputTokens": 2000,
                "cacheCreationInputTokens": 500
            }
        },
        "totalSessions": 10,
        "totalMessages": 200,
        "longestSession": {
            "sessionId": "sess-abc",
            "duration": 7200000,
            "messageCount": 30,
            "timestamp": "2025-06-14T12:00:00.000Z"
        },
        "firstSessionDate": "2025-01-10T08:30:00.000Z",
        "hourCounts": {"14": 25, "15": 18}
    }
    """
}

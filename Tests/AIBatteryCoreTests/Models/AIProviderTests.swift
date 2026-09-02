import Foundation
import Testing
@testable import AIBatteryCore

@Suite("AIProvider")
struct AIProviderTests {
    @Test func glyphsAndLabels() {
        #expect(AIProvider.claude.glyph == "\u{2726}") // ✦
        #expect(AIProvider.codex.glyph == "\u{2B21}") // ⬡
        #expect(AIProvider.claude.displayName == "Claude")
        #expect(AIProvider.codex.displayName == "Codex")
        #expect(AIProvider.claude.secondaryWindowLabel == "7-Day")
        #expect(AIProvider.codex.secondaryWindowLabel == "Weekly")
        #expect(AIProvider.claude.secondaryWindowShortCode == "7D")
        #expect(AIProvider.codex.secondaryWindowShortCode == "WK")
    }

    @Test func accountRecord_decodesLegacyJSONWithoutProvider() throws {
        // Exactly what v2.6.1 persisted — no `provider` key.
        let legacy = Data("""
        [{"id":"org-abc","displayName":"Kyle","billingType":"pro","addedAt":1234567}]
        """.utf8)
        let decoded = try JSONDecoder().decode([AccountRecord].self, from: legacy)
        #expect(decoded[0].provider == .claude)
        #expect(decoded[0].id == "org-abc")
    }

    @Test func accountRecord_roundTripsCodexProvider() throws {
        let record = AccountRecord(id: "uuid-1", displayName: nil, billingType: "team", addedAt: Date(), provider: .codex)
        let data = try JSONEncoder().encode(record)
        let back = try JSONDecoder().decode(AccountRecord.self, from: data)
        #expect(back.provider == .codex)
    }
}

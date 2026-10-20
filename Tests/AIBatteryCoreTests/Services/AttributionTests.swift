import Foundation
import Testing
@testable import AIBatteryCore

@Suite("Attribution")
struct AttributionTests {
    private func entry(_ account: String?, ts: TimeInterval) -> AssistantUsageEntry {
        AssistantUsageEntry(
            timestamp: Date(timeIntervalSince1970: ts), model: "gpt-6-astra", messageId: UUID().uuidString,
            inputTokens: 1, outputTokens: 1, cacheReadTokens: 0, cacheWriteTokens: 0,
            sessionId: "s", cwd: "/p", gitBranch: nil, toolCallCount: 0, creatorAccountId: account
        )
    }

    @Test func all_returnsInputUntouched() {
        let entries = [entry("a", ts: 1), entry(nil, ts: 2), entry("b", ts: 3)]
        let (kept, unattributed) = Attribution.all.partition(entries)
        #expect(kept.map(\.messageId) == entries.map(\.messageId))
        #expect(unattributed == 0)
        #expect(!Attribution.all.isAttributed)
    }

    @Test func account_keepsOwn_countsNil_dropsForeignUncounted_preservesOrder() {
        let entries = [entry("a", ts: 1), entry(nil, ts: 2), entry("b", ts: 3), entry("a", ts: 4), entry(nil, ts: 5)]
        let (kept, unattributed) = Attribution.account("a").partition(entries)
        #expect(kept.map(\.timestamp.timeIntervalSince1970) == [1, 4])
        #expect(unattributed == 2)
        #expect(Attribution.account("a").isAttributed)
    }

    @Test func account_onEmptyInput() {
        let (kept, unattributed) = Attribution.account("a").partition([])
        #expect(kept.isEmpty && unattributed == 0)
    }
}

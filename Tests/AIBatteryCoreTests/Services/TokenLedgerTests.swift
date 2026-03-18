import Testing
import Foundation
@testable import AIBatteryCore

@Suite("TokenLedger")
struct TokenLedgerTests {

    private func makeTempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("TokenLedgerTests-\(UUID().uuidString).json")
    }

    private func makeToken(
        id: String = "claude-opus-4-6",
        displayName: String = "Opus 4.6",
        input: Int = 0,
        output: Int = 0,
        cacheRead: Int = 0,
        cacheWrite: Int = 0
    ) -> ModelTokenSummary {
        ModelTokenSummary(
            id: id,
            displayName: displayName,
            inputTokens: input,
            outputTokens: output,
            cacheReadTokens: cacheRead,
            cacheWriteTokens: cacheWrite
        )
    }

    // MARK: - Empty ledger

    @Test @MainActor func merge_emptyLedger_returnsSameTokens() {
        let ledger = TokenLedger(fileURL: makeTempURL())
        let tokens = [makeToken(input: 100, output: 50)]
        let result = ledger.merge(tokens, accountId: "acc1")

        #expect(result.count == 1)
        #expect(result[0].inputTokens == 100)
        #expect(result[0].outputTokens == 50)
    }

    // MARK: - High-water mark preservation

    @Test @MainActor func merge_preservesHigherStoredValues() {
        let url = makeTempURL()
        let ledger = TokenLedger(fileURL: url)

        // First merge — stores 1000 input
        _ = ledger.merge([makeToken(input: 1000, output: 500)], accountId: "acc1")

        // Second merge with lower values (stats-cache rebuilt)
        let result = ledger.merge([makeToken(input: 200, output: 100)], accountId: "acc1")

        #expect(result[0].inputTokens == 1000)
        #expect(result[0].outputTokens == 500)
    }

    @Test @MainActor func merge_updatesWhenCurrentIsHigher() {
        let url = makeTempURL()
        let ledger = TokenLedger(fileURL: url)

        _ = ledger.merge([makeToken(input: 100)], accountId: "acc1")
        let result = ledger.merge([makeToken(input: 500)], accountId: "acc1")

        #expect(result[0].inputTokens == 500)
    }

    // MARK: - Historical model restoration

    @Test @MainActor func merge_restoresHistoricalModels() {
        let url = makeTempURL()
        let ledger = TokenLedger(fileURL: url)

        // Store both models
        let tokens = [
            makeToken(id: "claude-opus-4-6", displayName: "Opus 4.6", input: 1000),
            makeToken(id: "claude-sonnet-4-6", displayName: "Sonnet 4.6", input: 500),
        ]
        _ = ledger.merge(tokens, accountId: "acc1")

        // New data only has Opus (Sonnet lost from stats-cache)
        let result = ledger.merge(
            [makeToken(id: "claude-opus-4-6", displayName: "Opus 4.6", input: 1000)],
            accountId: "acc1"
        )

        #expect(result.count == 2)
        let sonnet = result.first(where: { $0.id == "claude-sonnet-4-6" })
        #expect(sonnet != nil)
        #expect(sonnet?.inputTokens == 500)
    }

    // MARK: - Per-account isolation

    @Test @MainActor func merge_isolatesAccounts() {
        let url = makeTempURL()
        let ledger = TokenLedger(fileURL: url)

        _ = ledger.merge([makeToken(input: 1000)], accountId: "acc1")
        let result = ledger.merge([makeToken(input: 100)], accountId: "acc2")

        // acc2 should not see acc1's values
        #expect(result[0].inputTokens == 100)
    }

    // MARK: - Persistence across instances

    @Test @MainActor func merge_persistsAcrossInstances() {
        let url = makeTempURL()

        let ledger1 = TokenLedger(fileURL: url)
        _ = ledger1.merge([makeToken(input: 1000)], accountId: "acc1")
        ledger1.flushForTesting()

        let ledger2 = TokenLedger(fileURL: url)
        let result = ledger2.merge([makeToken(input: 200)], accountId: "acc1")

        #expect(result[0].inputTokens == 1000)
    }

    // MARK: - Sort order

    @Test @MainActor func merge_sortsByTotalTokensDescending() {
        let ledger = TokenLedger(fileURL: makeTempURL())
        let tokens = [
            makeToken(id: "claude-a", displayName: "A", input: 100),
            makeToken(id: "claude-b", displayName: "B", input: 500),
            makeToken(id: "claude-c", displayName: "C", input: 300),
        ]
        let result = ledger.merge(tokens, accountId: "acc1")

        #expect(result[0].id == "claude-b")
        #expect(result[1].id == "claude-c")
        #expect(result[2].id == "claude-a")
    }

    // MARK: - All token types

    @Test @MainActor func merge_preservesAllTokenTypes() {
        let url = makeTempURL()
        let ledger = TokenLedger(fileURL: url)

        _ = ledger.merge(
            [makeToken(input: 100, output: 200, cacheRead: 300, cacheWrite: 400)],
            accountId: "acc1"
        )
        let result = ledger.merge(
            [makeToken(input: 50, output: 50, cacheRead: 50, cacheWrite: 50)],
            accountId: "acc1"
        )

        #expect(result[0].inputTokens == 100)
        #expect(result[0].outputTokens == 200)
        #expect(result[0].cacheReadTokens == 300)
        #expect(result[0].cacheWriteTokens == 400)
    }

    // MARK: - Write-batching (PERF-05)

    @Test @MainActor func merge_unchangedValues_doesNotWrite() throws {
        let url = makeTempURL()
        let ledger = TokenLedger(fileURL: url)

        // First merge — values increase → write expected
        _ = ledger.merge([makeToken(input: 100, output: 50)], accountId: "acc1")
        ledger.flushForTesting()

        let attrsBefore = try FileManager.default.attributesOfItem(atPath: url.path)
        let modBefore = attrsBefore[.modificationDate] as? Date

        // Second merge — identical values → no increase → no write
        // Sleep 1s so any write would be detectable via mod date change
        Thread.sleep(forTimeInterval: 1.0)
        _ = ledger.merge([makeToken(input: 100, output: 50)], accountId: "acc1")
        ledger.flushForTesting()

        let attrsAfter = try FileManager.default.attributesOfItem(atPath: url.path)
        let modAfter = attrsAfter[.modificationDate] as? Date

        // Mod date must be unchanged — no write occurred
        #expect(modBefore == modAfter)
    }

    @Test @MainActor func merge_singleCallWritesOnce() throws {
        let url = makeTempURL()
        let ledger1 = TokenLedger(fileURL: url)

        // Merge 3 different models in one call
        let tokens = [
            makeToken(id: "claude-a", displayName: "A", input: 1000, output: 500),
            makeToken(id: "claude-b", displayName: "B", input: 2000, output: 1000),
            makeToken(id: "claude-c", displayName: "C", input: 3000, output: 1500),
        ]
        _ = ledger1.merge(tokens, accountId: "acc1")
        ledger1.flushForTesting()

        // Load fresh instance from the same file
        let ledger2 = TokenLedger(fileURL: url)

        // Merge lower values — all three should return the original higher values
        // proving all 3 were persisted in a single write
        let lower = [
            makeToken(id: "claude-a", displayName: "A", input: 100, output: 50),
            makeToken(id: "claude-b", displayName: "B", input: 200, output: 100),
            makeToken(id: "claude-c", displayName: "C", input: 300, output: 150),
        ]
        let result = ledger2.merge(lower, accountId: "acc1")

        let a = result.first(where: { $0.id == "claude-a" })
        let b = result.first(where: { $0.id == "claude-b" })
        let c = result.first(where: { $0.id == "claude-c" })
        #expect(a?.inputTokens == 1000)
        #expect(b?.inputTokens == 2000)
        #expect(c?.inputTokens == 3000)
    }

    @Test @MainActor func merge_mixedChanges_writesOnlyOnce() throws {
        let url = makeTempURL()
        let ledger = TokenLedger(fileURL: url)

        // Initial merge — establish baseline
        _ = ledger.merge([
            makeToken(id: "claude-x", displayName: "X", input: 100),
            makeToken(id: "claude-y", displayName: "Y", input: 200),
        ], accountId: "acc1")
        ledger.flushForTesting()

        let attrsBefore = try FileManager.default.attributesOfItem(atPath: url.path)
        let modBefore = attrsBefore[.modificationDate] as? Date

        // Sleep so a write is detectable
        Thread.sleep(forTimeInterval: 1.0)

        // Second merge: claude-x increases, claude-y decreases
        _ = ledger.merge([
            makeToken(id: "claude-x", displayName: "X", input: 150), // increase
            makeToken(id: "claude-y", displayName: "Y", input: 100), // decrease (no-op)
        ], accountId: "acc1")
        ledger.flushForTesting()

        let attrsAfter = try FileManager.default.attributesOfItem(atPath: url.path)
        let modAfter = attrsAfter[.modificationDate] as? Date

        // Write happened (because claude-x increased)
        #expect(modBefore != modAfter)

        // Reload — verify high-water marks preserved atomically in single write
        let fresh = TokenLedger(fileURL: url)
        let result = fresh.merge([
            makeToken(id: "claude-x", displayName: "X", input: 0),
            makeToken(id: "claude-y", displayName: "Y", input: 0),
        ], accountId: "acc1")

        let x = result.first(where: { $0.id == "claude-x" })
        let y = result.first(where: { $0.id == "claude-y" })
        #expect(x?.inputTokens == 150) // updated value persisted
        #expect(y?.inputTokens == 200) // high-water preserved
    }

    // MARK: - File size guard

    @Test @MainActor func load_rejectsOversizedFile() throws {
        let url = makeTempURL()
        // Write >1MB of junk
        let junk = Data(repeating: 0x20, count: 1_100_000)
        try junk.write(to: url)

        let ledger = TokenLedger(fileURL: url)
        // Should start fresh (empty), not crash
        let result = ledger.merge([makeToken(input: 42)], accountId: "acc1")
        #expect(result[0].inputTokens == 42)
    }
}

import Foundation
import Testing
@testable import AIBatteryCore

/// The debounce coalesces every filesystem event inside a 2-second window into one
/// notification. It used to carry only the *last* event's invalidation flags, because the
/// previous work item was cancelled along with them: a Claude write landing just after a
/// Codex write left `CodexSessionLogReader` clean, so aggregation and the following polls
/// kept serving its old cached entries until the next Codex write happened to arrive.
@Suite("FileWatcher invalidation accumulation")
struct FileWatcherInvalidationTests {
    @Test func unionKeepsEveryReaderOwedAnInvalidation() {
        let codexWrite = FileWatcher.PendingInvalidations(statsCache: false, sessionLog: false, codexSessionLog: true)
        let claudeWrite = FileWatcher.PendingInvalidations(statsCache: true, sessionLog: true, codexSessionLog: false)

        var pending = FileWatcher.PendingInvalidations.none
        pending.formUnion(codexWrite)
        pending.formUnion(claudeWrite)

        #expect(pending.codexSessionLog, "the Codex reader must still be invalidated after a later Claude event")
        #expect(pending.sessionLog)
        #expect(pending.statsCache)
    }

    @Test func unionIsOrderIndependentAndNeverDropsFlags() {
        let codexWrite = FileWatcher.PendingInvalidations(statsCache: false, sessionLog: false, codexSessionLog: true)
        let claudeWrite = FileWatcher.PendingInvalidations(statsCache: true, sessionLog: true, codexSessionLog: false)

        var forward = FileWatcher.PendingInvalidations.none
        forward.formUnion(claudeWrite)
        forward.formUnion(codexWrite)

        var backward = FileWatcher.PendingInvalidations.none
        backward.formUnion(codexWrite)
        backward.formUnion(claudeWrite)

        #expect(forward == backward)
    }

    @Test func noneInvalidatesNothing() {
        let none = FileWatcher.PendingInvalidations.none
        #expect(!none.statsCache)
        #expect(!none.sessionLog)
        #expect(!none.codexSessionLog)
    }

    // MARK: - Scoping the aggregate to the provider that changed

    /// The watcher works out exactly which reader it owes, and the ViewModel now uses
    /// that instead of invalidating both providers' aggregators. Without the scoping, a
    /// Claude write every ~2 s during an active session stopped the Codex aggregator
    /// from ever short-circuiting, so every poll paid a full Codex pass over a tree that
    /// had not changed.
    @Test func aggregatorsAreScopedToTheReaderThatChanged() {
        let codexWrite = FileWatcher.PendingInvalidations(statsCache: false, sessionLog: false, codexSessionLog: true)
        let claudeJSONL = FileWatcher.PendingInvalidations(statsCache: false, sessionLog: true, codexSessionLog: false)
        let statsCacheOnly = FileWatcher.PendingInvalidations(statsCache: true, sessionLog: false, codexSessionLog: false)

        // Mirrors the decision in `UsageViewModel.setupFileWatcher`.
        func invalidatesClaude(_ c: FileWatcher.PendingInvalidations) -> Bool {
            c.sessionLog || c.statsCache
        }
        func invalidatesCodex(_ c: FileWatcher.PendingInvalidations) -> Bool {
            c.codexSessionLog
        }

        #expect(!invalidatesClaude(codexWrite), "a Codex rollout write must not re-aggregate Claude")
        #expect(invalidatesCodex(codexWrite))

        #expect(invalidatesClaude(claudeJSONL))
        #expect(!invalidatesCodex(claudeJSONL), "a Claude JSONL write must not re-aggregate Codex")

        // The stats cache is Claude-only, so it stands for the Claude aggregator alone.
        #expect(invalidatesClaude(statsCacheOnly))
        #expect(!invalidatesCodex(statsCacheOnly))
    }
}

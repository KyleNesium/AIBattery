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
}

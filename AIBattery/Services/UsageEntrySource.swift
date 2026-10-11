import Foundation

/// The reader seam `UsageAggregator` consumes. `SessionLogReader` (Claude Code
/// JSONL under `~/.claude/projects`) and `CodexSessionLogReader` (Codex CLI
/// rollouts under `~/.codex/sessions`) both produce the same `AssistantUsageEntry`
/// stream, so the aggregator runs unchanged on either provider's local data.
///
/// Implementations are NOT `@MainActor` — file I/O must never block the UI — and
/// guard their own mutable state (`@unchecked Sendable` + `NSLock`).
protocol UsageEntrySource: AnyObject, Sendable {
    /// All usage entries across every discovered file, sorted by timestamp ascending.
    func readAllUsageEntries() -> [AssistantUsageEntry]
    /// Mark caches dirty so the next read re-scans. Must be non-blocking (called from
    /// `FileWatcher` on the main thread while a background scan may hold the lock).
    func invalidate()
    /// Corrupt / skipped line count from the most recent `readAllUsageEntries()` call.
    var lastCorruptLineCount: Int { get }
}

extension SessionLogReader: UsageEntrySource {}

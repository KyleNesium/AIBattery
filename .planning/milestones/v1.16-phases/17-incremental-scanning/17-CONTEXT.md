# Phase 17: Incremental Scanning - Context

**Gathered:** 2026-03-25
**Status:** Ready for planning

<domain>
## Phase Boundary

Eliminate the JSONL re-scan bottleneck: SessionLogReader currently re-parses all 3,103 files (2 GB) every polling cycle because the LRU cache (200 entries) constantly evicts and `cachedAllEntries` is blown away on any file change. After this phase, only changed files are re-parsed.

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion

All implementation choices are at Claude's discretion — pure infrastructure/performance phase. Key constraints from profiling:

- LRU cache (200 entries) far too small for 3,103 files — expand or remove limit
- `cachedAllEntries` invalidation is all-or-nothing — needs incremental merge
- `Collection.firstIndex(of:)` byte scanning in readSessionFile dominates CPU — must be skipped for unchanged files
- Per-file cache already fingerprints (modDate, fileSize) — this is the right primitive, just needs to cover all files
- Thread safety via NSLock must be preserved

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `SessionLogReader.cache: [String: (Date, UInt64, [AssistantUsageEntry])]` — per-file fingerprint already exists
- `discoverJSONLFiles()` with directory mod-date tracking and TTL — reusable for incremental discovery
- `UsageAggregator` fingerprint-based skip (statsCacheModDate, lastRateLimits) — same pattern at higher level
- NSLock-based thread safety with `pendingInvalidation` flag

### Established Patterns
- Fingerprint-first: check cheap metadata before expensive I/O (used in both SessionLogReader and UsageAggregator)
- `@unchecked Sendable` + NSLock for thread-safe services
- FileWatcher → invalidate() → next poll re-reads

### Integration Points
- `UsageAggregator.aggregate()` calls `sessionLogReader.readAllUsageEntries()`
- `FileWatcher.debounceNotify()` calls `sessionLogReader.invalidate()` and `aggregator.invalidate()`
- `UsageViewModel.aggregateOffMain()` serializes calls via `inflightAggregation` task

</code_context>

<specifics>
## Specific Ideas

No specific requirements — open to standard approaches. Key metric: aggregation under 100ms when no files changed.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

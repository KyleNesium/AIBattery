# Phase 18: Memory Optimization - Context

**Gathered:** 2026-03-25
**Status:** Ready for planning

<domain>
## Phase Boundary

Ensure AIBattery holds under 100 MB RSS during normal operation by evicting parsed entries from inactive sessions. Note: Phase 17 measured RSS at 62 MB, suggesting the incremental caching changes may have already reduced memory significantly from the original 409 MB baseline.

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion
All implementation choices are at Claude's discretion — pure infrastructure phase. Key constraints:

- SessionLogReader.cache holds per-file (modDate, fileSize, [AssistantUsageEntry]) for all 3,103 files
- cachedAllEntries holds the merged/deduplicated result array
- Current RSS measured at 62 MB (already below 100 MB target) — may need only verification, not major surgery
- If eviction is needed: evict parsed entries from sessions not accessed in current polling window
- Thread safety via NSLock must be preserved
- Correctness: totals must remain accurate after eviction

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `SessionLogReader.cache: [String: (Date, UInt64, [AssistantUsageEntry])]` — per-file fingerprint + entries
- `cachedAllEntries: [AssistantUsageEntry]?` — merged result, cleared on invalidation
- `UsageAggregator.cachedSnapshot` — prevents redundant aggregation when nothing changed
- isDirty flag pattern for lazy recomputation

### Established Patterns
- Fingerprint-first: check cheap metadata before expensive I/O
- `@unchecked Sendable` + NSLock for thread-safe services
- FileWatcher invalidate() -> next poll re-reads

### Integration Points
- `UsageAggregator.aggregate()` calls `sessionLogReader.readAllUsageEntries()`
- `FileWatcher.debounceNotify()` calls invalidate() on both reader and aggregator
- `UsageViewModel.aggregateOffMain()` serializes calls via `inflightAggregation` task

</code_context>

<specifics>
## Specific Ideas

No specific requirements — infrastructure phase. Phase 17 already achieved 62 MB RSS; this phase validates and adds eviction if needed.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

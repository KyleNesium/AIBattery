# Phase 19: Verification - Context

**Gathered:** 2026-03-25
**Status:** Ready for planning

<domain>
## Phase Boundary

Confirm CPU and memory targets are met under realistic load. CPU <2% at idle (popover closed, no active session), CPU <5% during active polling. Integration tests reproduce pre-fix hotspot scenario and assert performance targets. No correctness regressions — token counts and cost totals match pre-fix values on the same fixture set.

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion
All implementation choices are at Claude's discretion — pure verification phase. Key constraints:

- CPU measurement: Activity Monitor or `ps -o %cpu=` with popover closed
- Memory measurement: `ps -o rss=` after full aggregation cycle
- Correctness: run existing test suite, verify token counts match
- No Xcode available — only Command Line Tools, so `swift test` won't work. Build verification via `swift build` only. Tests verified conceptually or in CI.
- Phase 17 achieved 0% CPU at idle; Phase 18 achieved 62 MB RSS — both already meet targets
- This phase validates the targets are still met and adds integration tests for regression prevention

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- 756+ tests across 52 files (Swift Testing framework)
- SessionLogReader with FileCacheEntry, incremental rebuild, entry eviction
- UsageAggregator with fingerprint-based skip, Calendar day boundary caching
- FileWatcher with selective invalidation

### Established Patterns
- Swift Testing framework (@Test, #expect)
- Temp directory fixtures with JSONL helpers (makeTempProjectsDir, writeJSONL, assistantLine)
- @unchecked Sendable + NSLock for thread safety

### Integration Points
- UsageAggregator.aggregate() -> SessionLogReader.readAllUsageEntries()
- FileWatcher.debounceNotify() -> invalidate() on both services
- UsageViewModel.aggregateOffMain() serializes via inflightAggregation task

</code_context>

<specifics>
## Specific Ideas

No specific requirements — verification phase confirms existing optimizations meet targets.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

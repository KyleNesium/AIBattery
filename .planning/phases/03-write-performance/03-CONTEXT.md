# Phase 3: Write Performance - Context

**Gathered:** 2026-03-18
**Status:** Ready for planning

<domain>
## Phase Boundary

Optimize write performance in TokenLedger and buildProjectTokens. Codebase scout reveals both are already well-optimized — TokenLedger writes only on value increases (high-water-mark), buildProjectTokens uses a pre-built map from a unified single-pass. The phase scope should validate these optimizations, add any remaining improvements, and ensure the fingerprint skip is robust.

</domain>

<decisions>
## Implementation Decisions

### TokenLedger Batching (PERF-05)
- `TokenLedger.merge()` already writes only when values increase (high-water-mark at lines 84-86)
- It writes once per `merge()` call if ANY value increased — this is already effectively batched
- Remaining optimization: if `merge()` is called multiple times per aggregation cycle, coalesce to a single write
- Verify: is `merge()` called once or multiple times per cycle? If once, this is already optimal — document it
- If multiple calls: add a dirty flag + flush pattern (mark dirty in merge, flush at end of aggregation)

### buildProjectTokens Iteration (PERF-06)
- `buildProjectTokensFromMap()` at lines 350-376 already works from pre-accumulated map, NOT raw JSONL
- The unified single-pass at lines 96-170 iterates `allEntries` once per aggregation
- Fingerprint skip at UsageViewModel lines 44-56 prevents re-aggregation when nothing changed
- Remaining optimization: within the aggregation itself, could track a "last processed entry index" to skip already-processed entries on incremental updates
- Alternative: if fingerprint skip already covers >90% of cycles, incremental processing adds complexity for little gain

### Claude's Discretion
- Whether incremental entry processing is worth the complexity given fingerprint skip effectiveness
- Exact mechanism for coalescing TokenLedger writes if needed
- Test strategy for verifying performance characteristics

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `TokenLedger.merge()` — high-water-mark comparison + async atomic write (lines 31-90)
- `TokenLedger.save()` — `Task.detached(priority: .utility)` with `.atomic` write (lines 112-122)
- `UsageAggregator` fingerprint skip — 4-way check (stats mod date, rate limits, idle minutes, account ID)
- `SessionLogReader.cachedAllEntries` — eliminates repeated disk I/O
- `buildProjectTokensFromMap()` — O(projects × models) from pre-built map

### Established Patterns
- Async background writes via `Task.detached`
- Cache invalidation via FileWatcher
- Fingerprint-based skip (cheap checks before expensive work)
- `@MainActor` isolation on services

### Integration Points
- `UsageAggregator.aggregate()` calls `TokenLedger.merge()`
- `UsageViewModel.refresh()` triggers aggregation cycle
- FileWatcher invalidates caches, restarts polling

</code_context>

<specifics>
## Specific Ideas

Given both areas are already well-optimized, this phase may result in:
1. Verifying current behavior meets the success criteria (already batched, already skips redundant iteration)
2. Adding tests that prove the performance characteristics
3. Minor improvements if merge() is called multiple times per cycle

</specifics>

<deferred>
## Deferred Ideas

- Full incremental JSONL processing (tracking last-processed offset) — high complexity, low gain given fingerprint skip

</deferred>

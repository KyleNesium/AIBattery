# Phase 4: Polling & Discovery Hardening - Context

**Gathered:** 2026-03-18
**Status:** Ready for planning

<domain>
## Phase Boundary

Fix three polling/discovery issues: (1) RateLimitFetcher doesn't persist the working model after 429+headers success — causes unnecessary re-probing; (2) AdaptivePollingState resets on any data change but the real issue is it resets via FileWatcher even when aggregation produces identical results; (3) SessionLogReader discovery cache relies solely on directory mod-dates — add a TTL fallback for robustness.

</domain>

<decisions>
## Implementation Decisions

### RateLimitFetcher Probe (PERF-07)
- On 429+headers success (line 200-210): call `saveWorkingModel()` so subsequent fetches skip the probe loop
- On 400+rate-limit-headers success (line 244-252): same treatment — persist the model
- The `tryFetch` → `.success()` path at line 108 already persists — just need the same pattern for 429 and 400-with-headers paths
- This is a 2-line fix in each path

### AdaptivePollingState (PERF-08)
- The reset logic itself is fine — `unchangedCycles` tracks consecutive unchanged cycles correctly
- The real issue: FileWatcher fires → `unchangedCycles = 0` → polling resets to base interval → aggregation runs → produces same snapshot → cycle wasted
- Fix: don't reset `unchangedCycles` in the FileWatcher handler. Instead, let the aggregation run and check `hasDataChanged`. If data didn't actually change, `unchangedCycles` increments naturally
- This means: remove `adaptivePolling.reset()` from FileWatcher handler (UsageViewModel line ~218), keep it only on system wake and manual interval change
- FileWatcher still triggers a refresh (invalidates aggregator cache), but doesn't reset the adaptive backoff

### SessionLogReader Discovery (PERF-09)
- Directory mod-date check is the primary fast path — keep it
- Add a TTL-based fallback: if more than 60s since last full enumeration, re-enumerate regardless of mod-dates
- This catches new files in directories where mtime didn't update (rare but possible on some filesystems)
- Track `lastFullEnumerationDate` — if `Date().timeIntervalSince(lastFullEnumerationDate) > 60`, force re-enumeration
- FileWatcher invalidation continues to work as before (clears everything)

### Claude's Discretion
- Exact TTL value for discovery fallback (60s suggested, could be 30-120s)
- Whether to log when TTL-based re-enumeration finds new files (useful for debugging)
- Test approach for FileWatcher/adaptive polling interaction

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `RateLimitFetcher.saveWorkingModel()` — already exists, just needs to be called in 2 more paths
- `AdaptivePollingState` — clean state machine at lines 13-24
- `SessionLogReader.discoveryDirModDatesChanged()` — existing fast-path check
- `SessionLogReader.discoverJSONLFiles()` — existing full enumeration

### Established Patterns
- Working model persistence: `aibattery_probeModel_{accountId}` in UserDefaults
- Adaptive polling: `unchangedCycles` counter with exponential backoff capped at 300s
- Discovery cache: dir mod-dates map + file-level LRU cache (200 entries)

### Integration Points
- `UsageViewModel` manages FileWatcher → adaptive polling → aggregation cycle
- `SessionLogReader.invalidate()` called by FileWatcher
- `RateLimitFetcher` called by `UsageViewModel.refresh()` before aggregation

</code_context>

<specifics>
## Specific Ideas

No specific requirements — well-defined fixes with clear patterns.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

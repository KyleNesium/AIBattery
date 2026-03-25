---
gsd_state_version: 1.0
milestone: v1.16
milestone_name: JSONL Performance
status: unknown
stopped_at: Completed 19-01-PLAN.md (integration tests + verification)
last_updated: "2026-03-25T11:43:44.674Z"
progress:
  total_phases: 3
  completed_phases: 3
  total_plans: 4
  completed_plans: 4
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-25)

**Core value:** Show Claude API usage clearly and instantly from the menu bar
**Current focus:** Phase 19 — verification

## Current Position

Phase: 19 (verification) — EXECUTING
Plan: 1 of 1

## Accumulated Context

### Decisions

- [v1.9.4]: Timer.publish on SwiftUI struct causes freeze — always use TimelineView instead
- [Phase 12]: PanelToggleState value type makes toggle desync structurally impossible
- [v1.14]: dailyActivity as loading signal for isEmpty
- [v1.15]: Breath timer removed entirely — static broken star for exhausted state
- [v1.9.9]: NSLock on UsageAggregator + task serialization in UsageViewModel
- [v1.16 scoping]: SQLite/persistent index ruled out — mod-date fingerprint caching is sufficient
- [v1.16 scoping]: FileWatcher rewrite ruled out — CPU hotspot is JSONL scan, not FSEvents I/O
- [Phase 17-01]: Unbounded per-file cache — 3,103 entries is trivial vs 200-entry LRU causing 94% eviction
- [Phase 17-01]: isDirty flag instead of clearing cachedAllEntries — avoids full re-merge when only one file changed
- [Phase 17-02]: Per-directory file cache (discoveredFilesByDir) enables selective re-enumeration of changed dirs only
- [Phase 17-02]: Calendar.startOfDay() cached across entries in aggregate loop — ICU lock contention was hidden CPU hotspot
- [Phase 19-verification]: Integration tests use real FileManager I/O to exercise the full incremental pipeline end-to-end

### Blockers/Concerns

- [Phase 17]: ~~LRU cache (200 entries) far too small for 3,103 files~~ RESOLVED — unbounded cache in 17-01
- [Phase 17]: ~~Collection.firstIndex(of:) byte scanning dominates readSessionFile~~ RESOLVED — bypassed for unchanged files in 17-01
- [Phase 18]: 409 MB RSS from retaining all parsed entries — Phase 18 must evict inactive session data (note: current RSS measured at 62 MB, may be partially pre-solved)

## Session Continuity

Last session: 2026-03-25T11:26:17.326Z
Stopped at: Completed 19-01-PLAN.md (integration tests + verification)
Resume file: None

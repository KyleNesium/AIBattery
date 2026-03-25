---
gsd_state_version: 1.0
milestone: v1.16
milestone_name: JSONL Performance
status: executing
stopped_at: Completed 17-01-PLAN.md (incremental scanning)
last_updated: "2026-03-25T09:35:26.769Z"
progress:
  total_phases: 3
  completed_phases: 0
  total_plans: 2
  completed_plans: 1
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-25)

**Core value:** Show Claude API usage clearly and instantly from the menu bar
**Current focus:** Phase 17 — Incremental Scanning

## Current Position

Phase: 17 (Incremental Scanning) — EXECUTING
Current Plan: 2 of 2

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

### Blockers/Concerns

- [Phase 17]: LRU cache (200 entries) far too small for 3,103 files — must expand or eliminate
- [Phase 17]: Collection.firstIndex(of:) byte scanning dominates readSessionFile — must be bypassed for unchanged files
- [Phase 18]: 409 MB RSS from retaining all parsed entries — Phase 18 must evict inactive session data

## Session Continuity

Last session: 2026-03-25
Stopped at: Completed 17-01-PLAN.md (incremental scanning)
Resume file: None

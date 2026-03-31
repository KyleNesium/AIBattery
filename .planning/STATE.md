---
gsd_state_version: 1.0
milestone: v2.0.7
milestone_name: Smart Auto Mode
status: unknown
stopped_at: null
last_updated: "2026-03-31"
progress:
  total_phases: 0
  completed_phases: 0
  total_plans: 0
  completed_plans: 0
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-31)

**Core value:** Show Claude API usage clearly and instantly from the menu bar
**Current focus:** Defining requirements for v2.0.7 Smart Auto Mode

## Current Position

Phase: Not started (defining requirements)
Plan: —
Status: Defining requirements
Last activity: 2026-03-31 — Milestone v2.0.7 started

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

(none)

## Session Continuity

Last session: 2026-03-31
Stopped at: null
Resume file: None

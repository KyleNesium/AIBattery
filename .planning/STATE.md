---
gsd_state_version: 1.0
milestone: v1.16
milestone_name: JSONL Performance
status: ready_to_plan
stopped_at: null
last_updated: "2026-03-25"
progress:
  total_phases: 3
  completed_phases: 0
  total_plans: 0
  completed_plans: 0
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-25)

**Core value:** Show Claude API usage clearly and instantly from the menu bar
**Current focus:** Phase 17 — Incremental Scanning

## Current Position

Phase: 17 of 19 (Incremental Scanning)
Plan: 0 of ? in current phase
Status: Ready to plan
Last activity: 2026-03-25 — v1.16 roadmap created; v1.15 shipped (Phases 15–16 complete)

Progress: [░░░░░░░░░░] 0% (v1.16 phases; 0 of 3 complete)

## Accumulated Context

### Decisions

- [v1.9.4]: Timer.publish on SwiftUI struct causes freeze — always use TimelineView instead
- [Phase 12]: PanelToggleState value type makes toggle desync structurally impossible
- [v1.14]: dailyActivity as loading signal for isEmpty
- [v1.15]: Breath timer removed entirely — static broken star for exhausted state
- [v1.9.9]: NSLock on UsageAggregator + task serialization in UsageViewModel
- [v1.16 scoping]: SQLite/persistent index ruled out — mod-date fingerprint caching is sufficient
- [v1.16 scoping]: FileWatcher rewrite ruled out — CPU hotspot is JSONL scan, not FSEvents I/O

### Blockers/Concerns

- [Phase 17]: LRU cache (200 entries) far too small for 3,103 files — must expand or eliminate
- [Phase 17]: Collection.firstIndex(of:) byte scanning dominates readSessionFile — must be bypassed for unchanged files
- [Phase 18]: 409 MB RSS from retaining all parsed entries — Phase 18 must evict inactive session data

## Session Continuity

Last session: 2026-03-25
Stopped at: Roadmap created for v1.16; no plans written yet
Resume file: None

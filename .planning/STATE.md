---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: unknown
stopped_at: Completed 20-01-PLAN.md
last_updated: "2026-04-01T06:20:23.051Z"
progress:
  total_phases: 2
  completed_phases: 2
  total_plans: 2
  completed_plans: 2
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-31)

**Core value:** Show Claude API usage clearly and instantly from the menu bar
**Current focus:** Phase 21 — hysteresis

## Current Position

Phase: 21 (hysteresis) — EXECUTING
Plan: 1 of 1

## Accumulated Context

### Decisions

- [v1.9.4]: Timer.publish on SwiftUI struct causes freeze — always use TimelineView instead
- [Phase 12]: PanelToggleState value type makes toggle desync structurally impossible
- [v1.16 scoping]: Unbounded per-file cache — 3,103 entries is trivial vs 200-entry LRU causing 94% eviction
- [Phase 17-01]: isDirty flag instead of clearing cachedAllEntries — avoids full re-merge when only one file changed
- [Phase 17-02]: Per-directory discovery cache enables selective re-enumeration of changed dirs only
- [Phase 19-verification]: Integration tests use real FileManager I/O for full incremental pipeline
- [Phase 20-01]: 80% RL threshold replaces 95% near-exhaustion — catches capacity pressure earlier
- [Phase 20-01]: 30-minute session staleness window gates context health display
- [Phase 20-01]: Deterministic 4-tier escalation ladder replaces opaque urgency scoring

### Key Context for v2.0.7

- All 6 requirements refactor `autoResolvedMode` computed property in `UsageSnapshot.swift`
- AUTO-04 (hysteresis) needs cross-poll state storage — separated into Phase 21 for clarity
- AUTO-05 (session staleness) uses existing `lastActivity` field on `TokenHealthStatus`
- Existing tests in `UsageSnapshotTests.swift` must be updated to match new logic
- Phase 20 is pure logic replacement (no new state needed); Phase 21 adds a state value

### Blockers/Concerns

(none)

## Session Continuity

Last session: 2026-03-31T22:16:29.774Z
Stopped at: Completed 20-01-PLAN.md
Resume file: None

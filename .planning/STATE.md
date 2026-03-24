---
gsd_state_version: 1.0
milestone: v1.15
milestone_name: Performance
status: defining_requirements
stopped_at: null
last_updated: "2026-03-24T14:10:00.000Z"
progress:
  total_phases: 0
  completed_phases: 0
  total_plans: 0
  completed_plans: 0
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-24)

**Core value:** Show Claude API usage clearly and instantly from the menu bar
**Current focus:** Defining requirements for v1.15 Performance

## Current Position

Phase: Not started (defining requirements)
Plan: —
Status: Defining requirements
Last activity: 2026-03-24 — Milestone v1.15 Performance started (CPU spike investigation complete)

## Accumulated Context

### Decisions

- [v1.9.4]: Timer.publish on SwiftUI struct causes freeze — always use TimelineView instead
- [Phase 12]: PanelToggleState value type makes toggle desync structurally impossible
- [v1.14]: dailyActivity as loading signal for isEmpty
- [v1.14]: stride(by: .month, count: 3) for 12M chart labels

### Blockers/Concerns

- PopoverFooterView uses TimelineView — highest hang-regression risk
- Breath timer has no panel visibility check — primary CPU hot path

## Session Continuity

Last session: 2026-03-24
Stopped at: Defining requirements for v1.15
Resume file: None

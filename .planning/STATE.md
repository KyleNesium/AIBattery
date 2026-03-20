---
gsd_state_version: 1.0
milestone: v1.13
milestone_name: Responsiveness
status: unknown
stopped_at: Completed 12-01-PLAN.md
last_updated: "2026-03-20T08:03:57.762Z"
progress:
  total_phases: 1
  completed_phases: 1
  total_plans: 2
  completed_plans: 2
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-20)

**Core value:** Show Claude API usage clearly and instantly from the menu bar
**Current focus:** Phase 12 — responsiveness

## Current Position

Phase: 12 (responsiveness) — EXECUTING
Plan: 1 of 2

## Accumulated Context

### Decisions

- [v1.9.4]: panel.isVisible toggle made it WORSE — reverted. isPanelShowing boolean is correct approach.
- [v1.9.4]: Timer.publish on SwiftUI struct causes freeze — always use TimelineView instead
- [v1.12]: Frame resize debounced + gated on isPanelShowing
- [v1.12]: NSApp.activate after makeKeyAndOrderFront (non-blocking)
- [Phase 12]: Use if panelHasAppeared branch over .hidden() — SwiftUI skips instantiation entirely; .hidden() still renders
- [Phase 12]: Use DispatchQueue.main.async (not .task) for deferred render — fires reliably after window compositing
- [Phase 12]: DeferredRenderState: pure value-type struct with mutating methods for testable @State logic without mocks
- [Phase 12-responsiveness]: PanelToggleState extracted as value type — all dismiss paths sync via PopoverPanel.onDismiss callback, making desync structurally impossible
- [Phase 12-01]: os_signpost(.pointsOfInterest) brackets makeKeyAndOrderFront for Instruments panel latency profiling

### Blockers/Concerns

- User reports intermittent hang still occurs despite v1.12 fixes — root cause not yet identified

## Session Continuity

Last session: 2026-03-20T08:03:57.759Z
Stopped at: Completed 12-01-PLAN.md
Resume file: None

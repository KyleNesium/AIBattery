# Roadmap: AIBattery

## Milestones

- ✅ **v1.0–v1.9.2** — Pre-GSD (shipped 2026-03-17)
- ✅ **v1.10 Bugs & Performance** — Phases 1-5 (shipped 2026-03-19) → [archive](milestones/v1.10-ROADMAP.md)
- ✅ **v1.11 Polish & Consistency** — Phases 6-9 (shipped 2026-03-19) → [archive](milestones/v1.11-ROADMAP.md)
- 🚧 **v1.12 Performance & Cleanup** — Phases 10-11 (in progress)

## Phases

<details>
<summary>✅ v1.10 Bugs & Performance (Phases 1-5) - SHIPPED 2026-03-19</summary>

See [milestones/v1.10-ROADMAP.md](milestones/v1.10-ROADMAP.md) for full phase details.

</details>

<details>
<summary>✅ v1.11 Polish & Consistency (Phases 6-9) - SHIPPED 2026-03-19</summary>

See [milestones/v1.11-ROADMAP.md](milestones/v1.11-ROADMAP.md) for full phase details.

- [x] Phase 6: Design System (2/2 plans) — completed 2026-03-19
- [x] Phase 7: Visual Polish (2/2 plans) — completed 2026-03-19
- [x] Phase 8: File Extraction (2/2 plans) — completed 2026-03-19
- [x] Phase 9: Wrap-Up (1/1 plan) — completed 2026-03-19

</details>

### v1.12 Performance & Cleanup (In Progress)

**Milestone Goal:** Eliminate remaining popover lag, gate periodic updates on panel visibility, and clean up dead code from v1.11.

- [x] **Phase 10: Popover Performance** - Eliminate lag and gate periodic updates on panel visibility (completed 2026-03-19)
- [x] **Phase 11: Code Cleanup** - Remove dead code and sync specs and README (completed 2026-03-19)

## Phase Details

### Phase 10: Popover Performance
**Goal**: The popover opens and closes instantly with no unnecessary background work while hidden
**Depends on**: Phase 9 (v1.11 complete)
**Requirements**: PERF-10, PERF-11, PERF-12
**Success Criteria** (what must be TRUE):
  1. Popover opens with no perceptible lag — feels native and instantaneous
  2. TimelineViews and periodic timers stop ticking when the popover is closed
  3. Popover render triggers fewer SwiftUI layout passes (GeometryReader count reduced)
**Plans:** 1/1 plans complete
Plans:
- [x] 10-01-PLAN.md — Extract GaugeBar component, verify v1.9.4 performance fixes

### Phase 11: Code Cleanup
**Goal**: Codebase is free of dead code and all specs and README reflect current state
**Depends on**: Phase 10
**Requirements**: CQ-03, CQ-04, CQ-05
**Success Criteria** (what must be TRUE):
  1. `sectionPadding()` extension and `PopoverLoadingView` struct are gone from the codebase
  2. CONSTANTS.md and UI_SPEC.md match actual animation durations and performance behavior
  3. README test coverage section is accurate
**Plans:** 1/1 plans complete
Plans:
- [ ] 11-01-PLAN.md — Remove dead code, sync specs and README

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1-5. v1.10 phases | v1.10 | 7/7 | Complete | 2026-03-19 |
| 6-9. v1.11 phases | v1.11 | 7/7 | Complete | 2026-03-19 |
| 10. Popover Performance | v1.12 | 1/1 | Complete | 2026-03-19 |
| 11. Code Cleanup | 1/1 | Complete   | 2026-03-19 | - |

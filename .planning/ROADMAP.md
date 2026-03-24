# Roadmap: AIBattery

## Milestones

- ✅ **v1.0–v1.9.2** - Phases 1–0 (pre-GSD, shipped)
- ✅ **v1.10 Bugs & Performance** - Phases 1–5 (shipped 2026-03-19)
- ✅ **v1.11 Polish & Consistency** - Phases 6–9 (shipped 2026-03-19)
- ✅ **v1.12 Performance & Cleanup** - Phases 10–11 (shipped 2026-03-19)
- ✅ **v1.13 Responsiveness** - Phase 12 (shipped 2026-03-20)
- ✅ **v1.14 Visual Polish** - Phases 13–14 (shipped 2026-03-24)
- 🚧 **v1.15 Performance** - Phases 15–16 (in progress)

## Phases

<details>
<summary>✅ v1.10–v1.14 (Phases 1–14) - SHIPPED 2026-03-24</summary>

Previous milestones tracked in MILESTONES.md. Phase numbering continues from 14.

</details>

### 🚧 v1.15 Performance (In Progress)

**Milestone Goal:** Eliminate 83% CPU usage at idle — kill runaway timers and gate all background work on visibility.

## Phase Details

- [ ] **Phase 15: Breath Timer Fix** - Gate breath animation on popover visibility — stop rendering when panel is closed
- [ ] **Phase 16: Idle and Lock Detection** - Pause all timers on screen lock or 5-minute system idle; resume on wake

### Phase 15: Breath Timer Fix
**Goal**: Users see zero background CPU cost from the breath animation when the popover is closed
**Depends on**: Phase 14
**Requirements**: PERF-01
**Success Criteria** (what must be TRUE):
  1. CPU usage drops from ~83% idle to background-normal when the popover is closed
  2. The menu bar icon renders no animation frames while the popover is closed
  3. The breath animation resumes immediately and correctly when the popover opens
**Plans**: 1 plan

Plans:
- [ ] 15-01-PLAN.md — Gate breath timer on popover visibility; update spec and README test coverage

### Phase 16: Idle and Lock Detection
**Goal**: Users see AIBattery consume no CPU when their machine is locked or idle for more than 5 minutes
**Depends on**: Phase 15
**Requirements**: PERF-02
**Success Criteria** (what must be TRUE):
  1. All timers (polling, file watcher fallback) stop firing when the screen is locked
  2. All timers stop firing after 5 minutes of system idle with no user activity
  3. Timers resume and the display refreshes on screen wake or user activity
  4. No timer drift or missed updates occur after resume
**Plans**: TBD

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 12. Responsiveness | v1.13 | 2/2 | Complete | 2026-03-20 |
| 13. Chart & Data Fixes | v1.14 | 2/2 | Complete | 2026-03-24 |
| 14. Layout Consistency | v1.14 | 0/0 | Complete | 2026-03-24 |
| 15. Breath Timer Fix | v1.15 | 0/1 | Not started | - |
| 16. Idle and Lock Detection | v1.15 | 0/? | Not started | - |

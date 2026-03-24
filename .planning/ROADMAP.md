# Roadmap: AIBattery

## Milestones

- ✅ **v1.0–v1.9.2** - Phases 1–0 (pre-GSD, shipped)
- ✅ **v1.10 Bugs & Performance** - Phases 1–5 (shipped 2026-03-19)
- ✅ **v1.11 Polish & Consistency** - Phases 6–9 (shipped 2026-03-19)
- ✅ **v1.12 Performance & Cleanup** - Phases 10–11 (shipped 2026-03-19)
- ✅ **v1.13 Responsiveness** - Phase 12 (shipped 2026-03-20)
- 🚧 **v1.14 Visual Polish** - Phases 13–14 (in progress)

## Phases

<details>
<summary>✅ v1.10–v1.13 (Phases 1–12) - SHIPPED 2026-03-20</summary>

Previous milestones tracked in MILESTONES.md. Phase numbering continues from 12.

</details>

### 🚧 v1.14 Visual Polish (In Progress)

**Milestone Goal:** Fix chart readability, false empty states, and layout spacing inconsistencies — surgical fixes only, no architectural changes.

- [x] **Phase 13: Chart & Data Fixes** - Fix 24H false empty state, 24H axis label spacing, and 12M month label collision (completed 2026-03-24)
- [ ] **Phase 14: Layout Consistency** - Fix uneven vertical padding between rate limit sections

## Phase Details

### Phase 13: Chart & Data Fixes
**Goal**: Insights charts display accurate data and readable labels at all times
**Depends on**: Phase 12 (v1.13 Responsiveness baseline)
**Requirements**: DATA-01, CHART-02, CHART-01
**Success Criteria** (what must be TRUE):
  1. Opening the 24H chart immediately after app relaunch (with prior-day activity logged) shows a chart — not "No activity"
  2. The 24H chart x-axis shows exactly 4 labels at midnight, 06:00, 12:00, and 18:00 with equal pixel gaps between them
  3. The 12M chart x-axis shows quarterly month labels (4 labels, one per quarter) with no clipping or overlapping text at the 275pt popover width
  4. After JSONL scan completes on cold start, the 24H chart updates to reflect actual hourly data
**Plans**: 2 plans
Plans:
- [ ] 13-01-PLAN.md — TDD wave 0: stubs + failing tests for DATA-01, CHART-02, CHART-01
- [ ] 13-02-PLAN.md — Implement all three fixes; full suite green + visual verification

### Phase 14: Layout Consistency
**Goal**: Rate limit sections have uniform vertical spacing regardless of which mode is shown
**Depends on**: Phase 13
**Requirements**: LAYOUT-01
**Success Criteria** (what must be TRUE):
  1. Visual gap between adjacent rate limit sections is equal across all three mode orderings (auto mode, 5h, 7d)
  2. The spacing change applies only to MetricToggleView bottom padding — no other section spacing changes
**Plans**: TBD

## Progress

**Execution Order:** 13 → 14

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 12. Responsiveness | v1.13 | 2/2 | Complete | 2026-03-20 |
| 13. Chart & Data Fixes | 1/2 | Complete    | 2026-03-24 | - |
| 14. Layout Consistency | v1.14 | 0/TBD | Not started | - |

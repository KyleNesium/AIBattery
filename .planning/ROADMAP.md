# Roadmap: AIBattery

## Milestones

- ✅ **v1.0–v1.9.2** — Pre-GSD (shipped 2026-03-17)
- ✅ **v1.10 Bugs & Performance** — Phases 1-5 (shipped 2026-03-19) → [archive](milestones/v1.10-ROADMAP.md)
- 🚧 **v1.11 Polish & Consistency** — Phases 6-9 (in progress)

## Phases

<details>
<summary>✅ v1.10 Bugs & Performance (Phases 1-5) - SHIPPED 2026-03-19</summary>

See [milestones/v1.10-ROADMAP.md](milestones/v1.10-ROADMAP.md) for full phase details.

</details>

### 🚧 v1.11 Polish & Consistency (In Progress)

**Milestone Goal:** Unify typography, spacing, and visual consistency across the popover UI while extracting large files and guarding performance.

- [ ] **Phase 6: Design System** - Typography and spacing constants replace inline values; all sections use consistent outer padding; no text below 8pt
- [ ] **Phase 7: Visual Polish** - Uniform section dividers, headers, and collapse behavior; subtle expand/collapse and metric-change animations
- [ ] **Phase 8: File Extraction** - UsagePopoverView and ActivityChartView broken into focused sub-views under 400 lines each
- [ ] **Phase 9: Wrap-Up** - Spec files reflect all structural changes; all new animations gated on panel visibility

## Phase Details

### Phase 6: Design System
**Goal**: Typography and spacing live in named constants — no more inline font/spacing literals scattered across views
**Depends on**: Nothing (first phase of milestone)
**Requirements**: DS-01, DS-02, DS-03, UI-05
**Success Criteria** (what must be TRUE):
  1. A `DesignSystem` (or equivalent) type exposes named font styles (e.g., `.sectionHeader`, `.monoValue`, `.tinyLabel`) used across all views — no bare `.font(.system(size: N))` calls remain
  2. A unified spacing scale (section, gap, tight, padding) replaces all hardcoded numeric spacing values
  3. Every popover section uses the same horizontal and vertical outer padding pattern — visually consistent margins
  4. No visible text in the popover renders below 8pt; the previous size-6 edge case no longer appears
**Plans:** 2 plans

Plans:
- [ ] 06-01-PLAN.md — Create Typography, Spacing, and Layout constant enums with snapshot tests
- [ ] 06-02-PLAN.md — Migrate all view files to use design system constants

### Phase 7: Visual Polish
**Goal**: All popover sections look and behave consistently, with subtle animations that enhance rather than distract
**Depends on**: Phase 6
**Requirements**: UI-06, UI-07
**Success Criteria** (what must be TRUE):
  1. Dividers, header label styles, and collapse chevrons are visually identical across all popover sections
  2. Expanding or collapsing any section plays a smooth, subtle animation (no abrupt jumps)
  3. Metric values that change during a poll cycle transition smoothly rather than snapping
  4. Animations do not measurably slow section expand/collapse interaction — feel instant on typical hardware
**Plans**: TBD

### Phase 8: File Extraction
**Goal**: Large view files are split into focused, composable sub-views that stay under 400 lines each
**Depends on**: Phase 6
**Requirements**: CQ-01
**Success Criteria** (what must be TRUE):
  1. `UsagePopoverView.swift` is under 400 lines; extracted sub-views compile and render identically to the original
  2. `ActivityChartView.swift` is under 400 lines; extracted sub-views compile and render identically to the original
  3. All existing tests continue to pass after extraction — no behavioral regressions
**Plans**: TBD

### Phase 9: Wrap-Up
**Goal**: Specs reflect the new structure and all animations are confirmed inert when the panel is hidden
**Depends on**: Phase 7, Phase 8
**Requirements**: CQ-02, PG-01
**Success Criteria** (what must be TRUE):
  1. `UI_SPEC.md` documents the design system constants, updated section layout, and animation behavior
  2. `ARCHITECTURE.md` reflects any structural changes from file extraction
  3. With the panel closed, CPU usage during a poll cycle is no higher than before animations were added — verified by running the app with Instruments or timed polling
**Plans**: TBD

## Progress

**Execution Order:** 6 → 7 → 8 → 9 (7 and 8 can run in parallel after 6)

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 6. Design System | v1.11 | 0/2 | Planning complete | - |
| 7. Visual Polish | v1.11 | 0/? | Not started | - |
| 8. File Extraction | v1.11 | 0/? | Not started | - |
| 9. Wrap-Up | v1.11 | 0/? | Not started | - |

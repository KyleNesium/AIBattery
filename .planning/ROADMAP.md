# Roadmap: AIBattery

## Milestones

- ✅ **v1.0–v1.9.2** - Phases 1–0 (pre-GSD, shipped)
- ✅ **v1.10 Bugs & Performance** - Phases 1–5 (shipped 2026-03-19)
- ✅ **v1.11 Polish & Consistency** - Phases 6–9 (shipped 2026-03-19)
- ✅ **v1.12 Performance & Cleanup** - Phases 10–11 (shipped 2026-03-19)
- ✅ **v1.13 Responsiveness** - Phase 12 (shipped 2026-03-20)
- 🚧 **v1.14 Polish & UX** - Phases 13–17 (in progress)

## Phases

<details>
<summary>✅ v1.10–v1.13 (Phases 1–12) - SHIPPED 2026-03-20</summary>

Previous milestones tracked in MILESTONES.md. Phase numbering continues from 12.

</details>

### 🚧 v1.14 Polish & UX (In Progress)

**Milestone Goal:** Comprehensive polish pass — close reliability gaps first, then integrate system preferences, refine visuals, improve UX clarity, and end with a code quality sweep.

- [ ] **Phase 13: Reliability** - Fix intermittent panel no-open and any remaining UI freeze
- [ ] **Phase 14: System Preference Integration** - Respect Reduce Motion and Increase Contrast system settings
- [ ] **Phase 15: Visual Polish** - Consistent number formatting, stale data indicator, pointer cursor audit
- [ ] **Phase 16: UX Clarity** - Contextual error messages and tooltip completeness
- [ ] **Phase 17: Code Quality Sweep** - Spec sync and design token literal audit

## Phase Details

### Phase 13: Reliability
**Goal**: Menu bar icon click always opens the panel and panel interaction never hangs
**Depends on**: Phase 12 (v1.13 Responsiveness baseline)
**Requirements**: REL-01, REL-02
**Success Criteria** (what must be TRUE):
  1. Clicking the menu bar icon opens the panel every time — no silent no-ops
  2. Panel interaction (scrolling, collapsing sections, clicking buttons) does not freeze or hang
  3. Repeated rapid open/close cycles complete without visual glitch or stuck state
**Plans:** 1 plan

Plans:
- [ ] 13-01-PLAN.md — Guard window + debounce + async activation fix for panel toggle reliability

### Phase 14: System Preference Integration
**Goal**: Users who enable Reduce Motion or Increase Contrast in System Settings see those preferences respected throughout the app
**Depends on**: Phase 13
**Requirements**: A11Y-01, A11Y-02
**Success Criteria** (what must be TRUE):
  1. With Reduce Motion enabled in System Settings, all animations in the popover are suppressed or replaced with instant transitions
  2. With Increase Contrast enabled in System Settings, borders and fills in the popover are visibly bolder/stronger
  3. Toggling either preference while the app is running takes effect on the next panel open
**Plans**: TBD

### Phase 15: Visual Polish
**Goal**: Numbers, indicators, and interactive elements are visually consistent and unambiguous
**Depends on**: Phase 14
**Requirements**: VIS-01, VIS-02, VIS-03
**Success Criteria** (what must be TRUE):
  1. All token counts, cost values, and time durations display without formatting edge cases (sub-1M tokens show correctly, sub-$1 costs do not round to $0.00, edge-case times are human-readable)
  2. When displayed data is stale (older than cache TTL), the panel shows a visual indicator that data is not fresh
  3. Every clickable non-button element (links, copyable values, collapsible headers) shows a pointer cursor on hover
**Plans**: TBD

### Phase 16: UX Clarity
**Goal**: Users understand what went wrong and what each value means without consulting external documentation
**Depends on**: Phase 15
**Requirements**: UXC-01, UXC-02
**Success Criteria** (what must be TRUE):
  1. Error messages distinguish between timeout, auth failure, and network failure — not a single generic "error" label
  2. Non-obvious values (burn rate, cache hit %, context binding) have `.help()` tooltips that appear on hover
**Plans**: TBD

### Phase 17: Code Quality Sweep
**Goal**: All spec files accurately describe the code as shipped in v1.14, and no inline literals bypass the design token system
**Depends on**: Phase 16
**Requirements**: CQ-01, CQ-02
**Success Criteria** (what must be TRUE):
  1. spec/CONSTANTS.md, spec/UI_SPEC.md, spec/ARCHITECTURE.md, and spec/DATA_LAYER.md all match the current codebase state with no known drift
  2. A grep for raw numeric literals in padding, font size, and animation duration positions returns no results outside of the Utilities/ design token files
**Plans**: TBD

## Progress

**Execution Order:** 13 → 14 → 15 → 16 → 17

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 12. Responsiveness | v1.13 | 2/2 | Complete | 2026-03-20 |
| 13. Reliability | v1.14 | 0/1 | Not started | - |
| 14. System Preference Integration | v1.14 | 0/TBD | Not started | - |
| 15. Visual Polish | v1.14 | 0/TBD | Not started | - |
| 16. UX Clarity | v1.14 | 0/TBD | Not started | - |
| 17. Code Quality Sweep | v1.14 | 0/TBD | Not started | - |

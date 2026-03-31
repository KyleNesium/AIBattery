# Roadmap: AIBattery

## Milestones

- ✅ **v1.0–v1.9.2** - Phases 1–0 (pre-GSD, shipped)
- ✅ **v1.10 Bugs & Performance** - Phases 1–5 (shipped 2026-03-19)
- ✅ **v1.11 Polish & Consistency** - Phases 6–9 (shipped 2026-03-19)
- ✅ **v1.12 Performance & Cleanup** - Phases 10–11 (shipped 2026-03-19)
- ✅ **v1.13 Responsiveness** - Phase 12 (shipped 2026-03-20)
- ✅ **v1.14 Visual Polish** - Phases 13–14 (shipped 2026-03-24)
- ✅ **v1.15 Performance** - Phases 15–16 (shipped 2026-03-25)
- ✅ **v1.16 JSONL Performance** - Phases 17–19 (shipped 2026-03-25)
- 🚧 **v2.0.7 Smart Auto Mode** - Phases 20–21 (in progress)

## Phases

<details>
<summary>✅ v1.10–v1.16 (Phases 1–19) - SHIPPED 2026-03-25</summary>

Previous milestones tracked in MILESTONES.md. Phase numbering continues from 19.

</details>

### 🚧 v2.0.7 Smart Auto Mode (In Progress)

**Milestone Goal:** Make auto mode intelligent — replace urgency scoring with a clear escalation ladder, add active session awareness, and add hysteresis to prevent flip-flopping between polls.

## Phase Details

- [x] **Phase 20: Escalation Logic** - Replace urgency scoring with a deterministic escalation ladder; add session awareness and remove time-to-limit boost (completed 2026-03-31)
- [ ] **Phase 21: Hysteresis** - Add cross-poll state storage so the selected mode stays stable until a clearly better option emerges

### Phase 20: Escalation Logic
**Goal**: Auto mode selects the right metric to display via a deterministic ladder instead of scoring math, and only considers context health when a session is actively in use
**Depends on**: Phase 19
**Requirements**: AUTO-01, AUTO-02, AUTO-03, AUTO-05, AUTO-06
**Success Criteria** (what must be TRUE):
  1. When no Claude Code session has been active in the last 30 minutes, auto mode never shows the context health view
  2. When no metric is urgent, auto mode shows the binding (highest-consumed) rate limit — not an empty or default state
  3. When the API is throttled, auto mode shows the throttle countdown regardless of other metrics
  4. When rate limit usage reaches 80% or above, auto mode escalates to the rate limit view
  5. When active context usage reaches 60% or above (and no higher-priority condition applies), auto mode shows the context health view
**Plans:** 1/1 plans complete
Plans:
- [x] 20-01-PLAN.md — Replace urgency scoring with deterministic escalation ladder (TDD)

### Phase 21: Hysteresis
**Goal**: Auto mode does not flip between views on consecutive polls when values hover near a threshold
**Depends on**: Phase 20
**Requirements**: AUTO-04
**Success Criteria** (what must be TRUE):
  1. When auto mode is showing the rate limit view and usage dips just below 80%, the view does not immediately switch away — it stays until the gap exceeds 10 percentage points
  2. When auto mode switches to a new view, it does not revert to the previous view on the very next poll unless the new view's condition clearly falls away
  3. All existing auto mode behavior is covered by tests updated to assert the new escalation + hysteresis logic
**Plans:** 1 plan
Plans:
- [ ] 21-01-PLAN.md — Hysteresis logic with 10pp de-escalation band (TDD)

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 12. Responsiveness | v1.13 | 2/2 | Complete | 2026-03-20 |
| 13. Chart & Data Fixes | v1.14 | 2/2 | Complete | 2026-03-24 |
| 14. Layout Consistency | v1.14 | 0/0 | Complete | 2026-03-24 |
| 15. Breath Timer Fix | v1.15 | 1/1 | Complete | 2026-03-24 |
| 16. Idle and Lock Detection | v1.15 | 0/? | Complete | 2026-03-25 |
| 17. Incremental Scanning | v1.16 | 2/2 | Complete | 2026-03-25 |
| 18. Memory Optimization | v1.16 | 1/1 | Complete | 2026-03-25 |
| 19. Verification | v1.16 | 1/1 | Complete | 2026-03-25 |
| 20. Escalation Logic | v2.0.7 | 1/1 | Complete | 2026-03-31 |
| 21. Hysteresis | v2.0.7 | 0/1 | Not started | - |

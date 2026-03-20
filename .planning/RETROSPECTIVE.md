# Project Retrospective

*A living document updated after each milestone. Lessons feed forward into future planning.*

## Milestone: v1.11 — Polish & Consistency

**Shipped:** 2026-03-19
**Phases:** 4 | **Plans:** 7 | **Commits:** ~37

### What Was Built
- Design token system (Typography 15 tokens, Spacing 6, Layout 7, MotionConstants 2) with 28 snapshot tests
- Full view migration — 148+ inline font calls and 52+ spacing calls replaced across 16 files
- Visual consistency — StyledDivider (19 callsites), section fade animations, numericText digit transitions
- File extraction — UsagePopoverView 666→210 lines, ActivityChartView 711→185 lines
- Spec sync — all 3 spec files updated, PG-01 animation audit documented

### What Worked
- Infrastructure phases (6, 8, 9) correctly identified as needing no user discussion — skipped straight to minimal context
- Phase 8 parallel execution (both plans in Wave 1) cut execution time in half
- Phase 6 "one-pass atomic migration" strategy avoided partial-migration inconsistency
- Extension-based extraction for ActivityChartView avoided @State/Binding complexity

### What Was Inefficient
- `sectionPadding()` convenience extension created in Phase 6 but never adopted in Phase 6 migration — dead code
- `PopoverLoadingView` extracted in Phase 8 but never wired (simpler inline version kept) — dead code
- Phase 7 research spent time confirming `contentTransition(.numericText())` macOS availability — could have been caught earlier in Phase 6 scout

### Patterns Established
- Design tokens follow ThemeColors pattern: caseless enum, static properties, sibling Utilities/ file
- MotionConstants centralize animation timing — `.standard` (0.2s) and `.snappy` (0.15s) cover all cases
- Extension-based extraction when views share @State; standalone struct extraction when data flows via init params
- StyledDivider as reusable component for consistent visual dividers

### Key Lessons
1. Infrastructure detection works well — 3 of 4 phases correctly auto-classified, saving discussion time
2. Orphaned exports are acceptable tech debt when the alternative is blocking the phase for cleanup
3. Visual polish phases need human validation — automated checks can't confirm animation quality

### Cost Observations
- Model mix: opus for planning, sonnet for research/execution/verification
- All 4 phases executed in a single autonomous session
- Parallel execution where dependencies allowed (Phase 8 plans, Phase 7+8 could have been parallel)

---

## Milestone: v1.13 — Responsiveness

**Shipped:** 2026-03-20
**Phases:** 1 | **Plans:** 2

### What Was Built
- PanelToggleState value-type state machine replacing isPanelShowing boolean — 8 tests
- PopoverPanel.orderOut override with onDismiss callback catching all 5 dismiss paths
- DeferredRenderState gating InsightsView and ProjectUsageSection with async hop — 5 tests
- os_signpost instrumentation for Instruments profiling of panel open latency

### What Worked
- Single-phase milestone with 2 parallel plans — clean separation (StatusBarManager vs UsagePopoverView)
- Value-type state machines (PanelToggleState, DeferredRenderState) made logic fully testable without AppKit
- Plan 12-02 auto-detected and fixed incomplete PanelToggleState integration from Plan 12-01's parallel execution

### What Was Inefficient
- v1.12 already addressed some responsiveness concerns — v1.13 scope overlapped slightly (PERF-10 vs RESP-01)
- UI-SPEC generated for a purely behavioral phase — added process overhead with minimal design value

### Patterns Established
- Value-type state machines for testable view state (PanelToggleState, DeferredRenderState)
- orderOut override as the canonical dismiss sync point for NSPanel subclasses
- Deferred rendering via `DispatchQueue.main.async` in `onAppear` — defers heavy work one run-loop

### Key Lessons
1. Toggle desync bugs need structural prevention (callback-based), not conditional fixes (boolean checks)
2. Behavioral/performance phases don't benefit from UI-SPEC — skip the gate for non-visual work
3. Parallel plans that touch different files but share types need cross-plan awareness of partial state

### Cost Observations
- Model mix: opus for planning, sonnet for research/execution/verification
- Single session, single wave — fastest milestone execution yet
- Both plans autonomous — no checkpoints needed

---

## Milestone: v1.12 — Performance & Cleanup

**Shipped:** 2026-03-19
**Phases:** 2 | **Plans:** 2

### What Was Built
- GaugeBar shared component replacing 5 duplicate GeometryReader patterns
- Dead code removal (sectionPadding, PopoverLoadingView)
- Spec sync for all performance and structural changes

### What Worked
- GaugeBar extraction was straightforward with clear before/after pattern
- Dead code identified systematically via unused symbol search

### Key Lessons
1. GeometryReader duplication is a reliable signal for component extraction
2. Dead code accumulates across milestones — periodic cleanup phases prevent drift

---

## Cross-Milestone Trends

| Milestone | Phases | Plans | Duration | Key Pattern |
|-----------|--------|-------|----------|-------------|
| v1.10 | 5 | 7 | ~3 hours | Bug fixes + performance |
| v1.11 | 4 | 7 | ~3 hours | Design system + refactoring |
| v1.12 | 2 | 2 | ~1 hour | Component extraction + cleanup |
| v1.13 | 1 | 2 | ~30 min | Toggle desync + deferred rendering |

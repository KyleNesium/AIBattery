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

## Cross-Milestone Trends

| Milestone | Phases | Plans | Duration | Key Pattern |
|-----------|--------|-------|----------|-------------|
| v1.10 | 5 | 7 | ~3 hours | Bug fixes + performance |
| v1.11 | 4 | 7 | ~3 hours | Design system + refactoring |

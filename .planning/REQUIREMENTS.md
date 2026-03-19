# Requirements: AIBattery

**Defined:** 2026-03-20
**Core Value:** Show Claude API usage clearly and instantly from the menu bar

## v1.12 Requirements

Requirements for performance and cleanup milestone. Each maps to roadmap phases.

### Performance

- [ ] **PERF-10**: Popover opens/closes as fast as native macOS menu bar extras — no perceptible lag
- [ ] **PERF-11**: All TimelineViews and periodic timers only tick while the popover panel is visible
- [ ] **PERF-12**: Minimize SwiftUI layout passes on popover open — reduce GeometryReader count where possible

### Code Quality

- [ ] **CQ-03**: Remove dead code — unused `sectionPadding()` extension and `PopoverLoadingView` struct
- [ ] **CQ-04**: Spec sync — update CONSTANTS.md and UI_SPEC.md for animation duration changes and performance fixes
- [ ] **CQ-05**: README test coverage section reflects current 706 tests / 45 files

## Future Requirements

(None deferred — all items scoped to this milestone)

## Out of Scope

| Feature | Reason |
|---------|--------|
| New features or metrics | This milestone is strictly performance and cleanup |
| CPU/energy profiling | Separate concern — focus on perceived popover snappiness |
| Memory footprint reduction | Not a current user pain point |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| PERF-10 | Phase 10 | Pending |
| PERF-11 | Phase 10 | Pending |
| PERF-12 | Phase 10 | Pending |
| CQ-03 | Phase 11 | Pending |
| CQ-04 | Phase 11 | Pending |
| CQ-05 | Phase 11 | Pending |

**Coverage:**
- v1.12 requirements: 6 total
- Mapped to phases: 6
- Unmapped: 0

---
*Requirements defined: 2026-03-20*

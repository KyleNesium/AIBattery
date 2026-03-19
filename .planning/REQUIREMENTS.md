# Requirements: AIBattery

**Defined:** 2026-03-19
**Core Value:** Show Claude API usage clearly and instantly from the menu bar

## v1.11 Requirements

Requirements for polish and consistency milestone. Each maps to roadmap phases.

### Design System

- [ ] **DS-01**: Typography constants — named font styles replacing 30+ inline `.font()` calls (e.g., `.sectionHeader`, `.monoValue`, `.tinyLabel`)
- [ ] **DS-02**: Spacing constants — unified scale replacing 8+ hardcoded spacing values (section, gap, tight, padding)
- [ ] **DS-03**: Consistent outer padding — all sections use the same horizontal/vertical pattern

### UI Polish

- [ ] **UI-05**: Minimum font size audit — no text below 8pt (size 6 edge case fixed)
- [ ] **UI-06**: Section visual consistency — uniform dividers, header styles, and collapse behavior across all popover sections
- [ ] **UI-07**: Subtle transition animations on section expand/collapse and metric changes (must not impact poll-cycle performance)

### Code Quality

- [ ] **CQ-01**: Extract large view files — break UsagePopoverView (666 lines) and ActivityChartView (704 lines) into focused sub-views under 400 lines each
- [ ] **CQ-02**: Spec sync — update UI_SPEC.md and ARCHITECTURE.md to reflect any structural changes

### Performance Guard

- [ ] **PG-01**: No animation runs when panel is closed — verify all new animations are gated on panel visibility

## Future Requirements

(None deferred — all items scoped to this milestone)

## Out of Scope

| Feature | Reason |
|---------|--------|
| New features or metrics | This milestone is strictly polish and consistency |
| Color palette changes | ThemeColors is already clean with colorblind support |
| Menu bar icon redesign | Icon system is well-built, no changes needed |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| DS-01 | — | Pending |
| DS-02 | — | Pending |
| DS-03 | — | Pending |
| UI-05 | — | Pending |
| UI-06 | — | Pending |
| UI-07 | — | Pending |
| CQ-01 | — | Pending |
| CQ-02 | — | Pending |
| PG-01 | — | Pending |

**Coverage:**
- v1.11 requirements: 9 total
- Mapped to phases: 0
- Unmapped: 9 ⚠️

---
*Requirements defined: 2026-03-19*
*Last updated: 2026-03-19 after initial definition*

# Requirements: AIBattery v1.14 Visual Polish

**Defined:** 2026-03-24
**Core Value:** Show Claude API usage clearly and instantly from the menu bar

## v1.14 Requirements

### Chart Readability

- [x] **CHART-01**: 12M chart shows quarterly month labels plus current month — no overlapping text
- [x] **CHART-02**: 24H chart shows 4 evenly-spaced hour labels in `HH:00` format (00:00, 06:00, 12:00, 18:00)

### Data Correctness

- [x] **DATA-01**: 24H chart never shows "No activity" when daily activity data exists — uses dailyActivity as loading signal

### Layout Consistency

- [ ] **LAYOUT-01**: Rate limit sections (auto mode, 5h, 7d) have equal vertical padding

## Future Requirements

### Deferred from v1.14

- **A11Y-01**: App respects system Reduce Motion preference — all animations gated
- **A11Y-02**: App respects system Increase Contrast preference — bolder borders/fills
- **UXC-01**: Error messages include specific failure cause (timeout, auth, network)
- **UXC-02**: All non-obvious values have `.help()` tooltips (burn rate, cache %, binding)
- **VIS-01**: Number formatting is consistent (sub-1M tokens, sub-$1 costs, edge-case times)
- **VIS-02**: Panel shows visual staleness indicator when data is old
- **VIS-03**: All clickable elements show pointer cursor consistently
- **CQ-01**: All spec files match current code after polish changes
- **CQ-02**: No inline literals bypass the design token system

## Out of Scope

| Feature | Reason |
|---------|--------|
| Persist todayHourCounts to UserDefaults | Overkill — dailyActivity loading signal is sufficient |
| Redesign chart tooltips | Current hover tooltips work; not in user-reported issues |
| Chart animation changes | Risk regression with existing MotionConstants system |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| CHART-01 | Phase 13 | Complete |
| CHART-02 | Phase 13 | Complete |
| DATA-01 | Phase 13 | Complete |
| LAYOUT-01 | Phase 14 | Pending |

**Coverage:**
- v1.14 requirements: 4 total
- Mapped to phases: 4
- Unmapped: 0

---
*Requirements defined: 2026-03-24*
*Last updated: 2026-03-24 — phase mapping added*

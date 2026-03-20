# Requirements: AIBattery v1.14 Polish & UX

**Defined:** 2026-03-20
**Core Value:** Show Claude API usage clearly and instantly from the menu bar

## v1.14 Requirements

### Reliability

- [ ] **REL-01**: Menu bar icon click always opens the panel — diagnose and fix intermittent no-open
- [ ] **REL-02**: No UI freeze or hang during normal panel interaction

### Accessibility

- [ ] **A11Y-01**: App respects system Reduce Motion preference — all animations gated
- [ ] **A11Y-02**: App respects system Increase Contrast preference — bolder borders/fills

### UX Clarity

- [ ] **UXC-01**: Error messages include specific failure cause (timeout, auth, network)
- [ ] **UXC-02**: All non-obvious values have `.help()` tooltips (burn rate, cache %, binding)

### Visual Polish

- [ ] **VIS-01**: Number formatting is consistent (sub-1M tokens, sub-$1 costs, edge-case times)
- [ ] **VIS-02**: Panel shows visual staleness indicator when data is old
- [ ] **VIS-03**: All clickable elements show pointer cursor consistently

### Code Quality

- [ ] **CQ-01**: All spec files match current code after polish changes
- [ ] **CQ-02**: No inline literals bypass the design token system

## Future Requirements

### Deferred from v1.14

- **A11Y-03**: VoiceOver full audit — complete coverage for Settings, MetricToggle, footer, menu bar button
- **UXC-03**: Section-level empty states — Projects (no JSONL cwd data), Context Health (no active sessions)
- **VIS-04**: Collapsed section summary audit — verify all sections show useful one-line summaries
- **VIS-05**: Smooth section reorder animation on auto-mode switch

## Out of Scope

| Feature | Reason |
|---------|--------|
| Global keyboard shortcut to open panel | Requires NSEvent global monitor, non-trivial; menu bar is easy to click |
| Copy-entire-section affordance | Individual values are already copyable |
| Dark/light mode override toggle | System appearance contract; macOS handles this |
| Custom color themes | Multiplies test surface; colorblind mode covers real need |
| Animation speed slider | System Reduce Motion covers 95% of real need |
| Font size slider | macOS Larger Text accessibility handles this at system level |
| CSV/JSON data export | JSONL files are the data source; document location instead |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| REL-01 | Phase 13 | Pending |
| REL-02 | Phase 13 | Pending |
| A11Y-01 | Phase 14 | Pending |
| A11Y-02 | Phase 14 | Pending |
| VIS-01 | Phase 15 | Pending |
| VIS-02 | Phase 15 | Pending |
| VIS-03 | Phase 15 | Pending |
| UXC-01 | Phase 16 | Pending |
| UXC-02 | Phase 16 | Pending |
| CQ-01 | Phase 17 | Pending |
| CQ-02 | Phase 17 | Pending |

**Coverage:**
- v1.14 requirements: 11 total
- Mapped to phases: 11
- Unmapped: 0

---
*Requirements defined: 2026-03-20*
*Last updated: 2026-03-20 — traceability mapped after roadmap creation*

# Requirements: AIBattery v1.15 Performance

**Defined:** 2026-03-24
**Core Value:** Show Claude API usage clearly and instantly from the menu bar

## v1.15 Requirements

### Timer Management

- [ ] **PERF-01**: Breath timer stops when popover is closed — no background icon rendering at 500ms/1s intervals

### Resource Gating

- [ ] **PERF-02**: All timers stop when screen is locked or app is idle >5min — resume on wake/activity

## Future Requirements

### Deferred from v1.15

- **PERF-03**: Suspend polling timer when popover closed — resume on open
- **PERF-04**: Consolidate FileWatcher fallback timer with main polling cycle
- **PERF-05**: Profile and optimize MenuBarIcon.statusBarImage rendering cost

## Out of Scope

| Feature | Reason |
|---------|--------|
| Rewrite FileWatcher to pure FSEvents | Current debounced approach works; CPU issue is timer-driven not I/O-driven |
| Background refresh scheduling | Over-engineering for a menu bar app — visibility gating is sufficient |
| Energy Impact API integration | Apple's Activity Monitor already shows this; not user-visible |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| PERF-01 | TBD | Pending |
| PERF-02 | TBD | Pending |

**Coverage:**
- v1.15 requirements: 2 total
- Mapped to phases: 0
- Unmapped: 2

---
*Requirements defined: 2026-03-24*
*Last updated: 2026-03-24 — initial definition*

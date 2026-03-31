# Requirements: AIBattery

**Defined:** 2026-03-31
**Core Value:** Show Claude API usage clearly and instantly from the menu bar

## v2.0.7 Requirements

Requirements for Smart Auto Mode. Each maps to roadmap phases.

### Auto Mode Resolution

- [ ] **AUTO-01**: Auto mode excludes context health when no active session exists (no sessions or all stale)
- [ ] **AUTO-02**: Auto mode defaults to binding rate limit (`representativeClaim`) when no metric is urgent
- [ ] **AUTO-03**: Auto mode uses escalation ladder (throttled → ≥80% RL → ≥60% active context → binding RL) instead of urgency scoring
- [ ] **AUTO-04**: Auto mode applies hysteresis — selected mode stays until another mode exceeds it by ≥10pp or current mode drops below its threshold
- [ ] **AUTO-05**: Context health only competes when at least one session has activity within the last 30 minutes
- [ ] **AUTO-06**: Time-to-limit boost scoring removed (escalation ladder handles urgency natively)

## Future Requirements

(None deferred — all scoped features included)

## Out of Scope

| Feature | Reason |
|---------|--------|
| User-configurable escalation thresholds | Adds settings complexity; hardcoded thresholds are sensible defaults |
| Per-session auto mode (show context for active session) | Would require session-level metric display, not just mode switching |
| Auto mode learning from user overrides | Over-engineering; clear escalation logic is predictable |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| AUTO-01 | Phase 20 | Pending |
| AUTO-02 | Phase 20 | Pending |
| AUTO-03 | Phase 20 | Pending |
| AUTO-04 | Phase 21 | Pending |
| AUTO-05 | Phase 20 | Pending |
| AUTO-06 | Phase 20 | Pending |

**Coverage:**
- v2.0.7 requirements: 6 total
- Mapped to phases: 6
- Unmapped: 0 ✓

---
*Requirements defined: 2026-03-31*
*Last updated: 2026-03-31 after roadmap creation*

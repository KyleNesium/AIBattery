# Requirements: AIBattery v1.16 JSONL Performance

**Defined:** 2026-03-25
**Core Value:** Show Claude API usage clearly and instantly from the menu bar

## v1.16 Requirements

### JSONL Scan Efficiency

- [ ] **SCAN-01**: Aggregation cycle completes in <100ms (currently takes seconds, consuming entire CPU core)
- [ ] **SCAN-02**: Only changed JSONL files are re-parsed on each cycle (incremental, not full re-scan)
- [ ] **SCAN-03**: File discovery uses mod-date comparison to skip unchanged directories

### Memory Efficiency

- [ ] **MEM-01**: RSS stays under 100 MB during normal operation (currently 409 MB)
- [ ] **MEM-02**: Parsed entries from old/inactive sessions are not held in memory permanently

### CPU at Idle

- [ ] **CPU-01**: CPU usage stays under 2% when popover is closed and no Claude Code session is active
- [ ] **CPU-02**: CPU usage stays under 5% during active polling with popover closed

## Previous Milestone (v1.15 — shipped)

- [x] **PERF-01**: Breath timer stops when popover is closed — v1.15
- [x] **PERF-02**: All timers stop when screen is locked or app is idle >5min — v1.15

## Future Requirements

- **PERF-03**: Suspend polling timer when popover closed — resume on open
- **PERF-04**: Consolidate FileWatcher fallback timer with main polling cycle

## Out of Scope

| Feature | Reason |
|---------|--------|
| SQLite/persistent index | Over-engineered for the problem; file mod-date caching is sufficient |
| Background daemon | Menu bar app should be lightweight, not a service |
| JSONL content parsing | Security/privacy boundary; token-count-only reads |
| Rewrite FileWatcher to pure FSEvents | Current debounced approach works; CPU issue is JSONL scan not I/O |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| SCAN-01 | TBD | Pending |
| SCAN-02 | TBD | Pending |
| SCAN-03 | TBD | Pending |
| MEM-01 | TBD | Pending |
| MEM-02 | TBD | Pending |
| CPU-01 | TBD | Pending |
| CPU-02 | TBD | Pending |

**Coverage:**
- v1.16 requirements: 7 total
- Mapped to phases: 0
- Unmapped: 7 ⚠️

---
*Requirements defined: 2026-03-25*
*Last updated: 2026-03-25 after initial definition*

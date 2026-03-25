# Roadmap: AIBattery

## Milestones

- ✅ **v1.0–v1.9.2** - Phases 1–0 (pre-GSD, shipped)
- ✅ **v1.10 Bugs & Performance** - Phases 1–5 (shipped 2026-03-19)
- ✅ **v1.11 Polish & Consistency** - Phases 6–9 (shipped 2026-03-19)
- ✅ **v1.12 Performance & Cleanup** - Phases 10–11 (shipped 2026-03-19)
- ✅ **v1.13 Responsiveness** - Phase 12 (shipped 2026-03-20)
- ✅ **v1.14 Visual Polish** - Phases 13–14 (shipped 2026-03-24)
- ✅ **v1.15 Performance** - Phases 15–16 (shipped 2026-03-25)
- 🚧 **v1.16 JSONL Performance** - Phases 17–19 (in progress)

## Phases

<details>
<summary>✅ v1.10–v1.15 (Phases 1–16) - SHIPPED 2026-03-25</summary>

Previous milestones tracked in MILESTONES.md. Phase numbering continues from 16.

</details>

### 🚧 v1.16 JSONL Performance (In Progress)

**Milestone Goal:** Reduce CPU usage from 83% to <2% at idle — SessionLogReader scans 3,103 JSONL files (2 GB) on every polling cycle, consuming an entire CPU core continuously.

## Phase Details

- [ ] **Phase 17: Incremental Scanning** - Only re-parse JSONL files that changed since last cycle; skip unchanged files via mod-date + size fingerprint
- [ ] **Phase 18: Memory Optimization** - Evict parsed entries for old/inactive sessions; store aggregated results not raw entries
- [ ] **Phase 19: Verification** - Confirm CPU and memory targets are met under realistic conditions; integration tests

### Phase 17: Incremental Scanning
**Goal**: Aggregation cycles skip unchanged files entirely, so only new or modified JSONL files are ever re-parsed
**Depends on**: Phase 16
**Requirements**: SCAN-01, SCAN-02, SCAN-03
**Success Criteria** (what must be TRUE):
  1. Opening the popover and seeing fresh data takes under 100ms for aggregation (currently takes seconds)
  2. On a polling cycle with no new Claude Code activity, zero JSONL files are re-parsed
  3. On a polling cycle where one session is active, only that session's file(s) are re-parsed
  4. Directory traversal uses mod-date comparison to skip unchanged subdirectories without opening them
**Plans:** 2/2 plans executed
Plans:
- [x] 17-01-PLAN.md — Remove LRU cache cap and implement incremental dirty-flag merge
- [x] 17-02-PLAN.md — Per-directory incremental discovery and performance verification

### Phase 18: Memory Optimization
**Goal**: AIBattery holds under 100 MB RSS during normal operation by not retaining parsed entries from old sessions
**Depends on**: Phase 17
**Requirements**: MEM-01, MEM-02
**Success Criteria** (what must be TRUE):
  1. RSS stays under 100 MB after a full aggregation cycle across all 3,103 files (currently 409 MB)
  2. Sessions not accessed in the current polling window do not have raw parsed entries in memory
  3. Evicting old session data does not cause a correctness regression — totals remain accurate
**Plans**: TBD

### Phase 19: Verification
**Goal**: CPU and memory targets are confirmed met under realistic load; any remaining hotspots are caught before release
**Depends on**: Phase 18
**Requirements**: CPU-01, CPU-02
**Success Criteria** (what must be TRUE):
  1. CPU stays under 2% for at least 5 minutes with popover closed and no active Claude Code session
  2. CPU stays under 5% during an active polling cycle with popover closed and a live session running
  3. Integration tests reproduce the pre-fix hotspot scenario and assert the performance targets
  4. No correctness regressions — token counts and cost totals match pre-fix values on the same fixture set
**Plans**: TBD

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 12. Responsiveness | v1.13 | 2/2 | Complete | 2026-03-20 |
| 13. Chart & Data Fixes | v1.14 | 2/2 | Complete | 2026-03-24 |
| 14. Layout Consistency | v1.14 | 0/0 | Complete | 2026-03-24 |
| 15. Breath Timer Fix | v1.15 | 1/1 | Complete | 2026-03-24 |
| 16. Idle and Lock Detection | v1.15 | 0/? | Complete | 2026-03-25 |
| 17. Incremental Scanning | v1.16 | 2/2 | Complete | 2026-03-25 |
| 18. Memory Optimization | v1.16 | 0/? | Not started | - |
| 19. Verification | v1.16 | 0/? | Not started | - |

# Roadmap: AIBattery

## Milestones

- ✅ **v1.0–v1.9.2** - Pre-GSD (shipped 2026-03-17)
- 🚧 **v1.10 Bugs & Performance** - Phases 1–5 (in progress)

## Phases

<details>
<summary>✅ v1.0–v1.9.2 Pre-GSD — SHIPPED 2026-03-17</summary>

All capabilities from OAuth through subagent JSONL discovery shipped before GSD adoption.
See MILESTONES.md for capability list.

Last phase: 0 (pre-GSD, no phase numbering)

</details>

### 🚧 v1.10 Bugs & Performance (In Progress)

**Milestone Goal:** Fix known bugs and optimize remaining performance bottlenecks for a more robust, efficient app.

- [x] **Phase 1: Context & Projection Fixes** - Correct bidirectional context-window detection and sub-50% time-to-limit projections (completed 2026-03-18)
- [x] **Phase 2: Data Accuracy Fixes** - Replace hardcoded probe model list with dynamic discovery and switch tool call counts to JSONL source (completed 2026-03-18)
- [x] **Phase 3: Write Performance** - Batch TokenLedger disk writes and eliminate redundant JSONL iteration in buildProjectTokens (completed 2026-03-18)
- [ ] **Phase 4: Polling & Discovery Hardening** - Minimize unnecessary probe API calls, prevent polling resets on minor churn, and detect new JSONL files when directory mod-time is unchanged
- [ ] **Phase 5: Spec Sync** - Bring spec files current with code (ThrottleTracker, AccountStore.canAddAccount)

## Phase Details

### Phase 1: Context & Projection Fixes
**Goal**: Session context health and time-to-limit projections are accurate across all utilization ranges and context tier changes
**Depends on**: Nothing (first phase)
**Requirements**: BUG-02, BUG-03
**Success Criteria** (what must be TRUE):
  1. Context window tier adjusts downward when session data shows fewer tokens than the current tier maximum
  2. Time-to-limit projection displays a value at any utilization percentage, including below 50%
  3. Context health indicator reflects the correct tier after downward adjustment without requiring app restart
**Plans**: 1 plan
Plans:
- [x] 01-01-PLAN.md — Bidirectional tier detection + projection threshold doc fix

### Phase 2: Data Accuracy Fixes
**Goal**: Rate limit probe uses a resilient model list, and today's tool call count reflects actual JSONL data
**Depends on**: Phase 1
**Requirements**: BUG-01, BUG-04
**Success Criteria** (what must be TRUE):
  1. Rate limit polling continues working after Anthropic deprecates a model ID in the probe list
  2. Today's tool call count matches tool_use blocks counted from JSONL session logs
  3. Probe model list updates without requiring an app release
**Plans**: 2 plans
Plans:
- [ ] 02-01-PLAN.md — Dynamic probe model list from JSONL-observed models
- [ ] 02-02-PLAN.md — JSONL-derived tool call counting with stats-cache merge

### Phase 3: Write Performance
**Goal**: TokenLedger writes are batched and buildProjectTokens avoids full JSONL re-iteration
**Depends on**: Phase 2
**Requirements**: PERF-05, PERF-06
**Success Criteria** (what must be TRUE):
  1. TokenLedger produces one disk write per aggregation cycle instead of one write per token value increase
  2. buildProjectTokens skips entries already counted in a previous pass when nothing has changed
  3. No regression in token count accuracy after batching changes
**Plans**: 1 plan
Plans:
- [ ] 03-01-PLAN.md — Verify write batching + iteration avoidance, add performance-characteristic tests

### Phase 4: Polling & Discovery Hardening
**Goal**: The polling subsystem makes fewer unnecessary API calls, doesn't thrash on minor data changes, and reliably finds new JSONL files
**Depends on**: Phase 3
**Requirements**: PERF-07, PERF-08, PERF-09
**Success Criteria** (what must be TRUE):
  1. RateLimitFetcher does not retry probe models unnecessarily when a valid response was already received
  2. Adaptive polling interval holds steady during active Claude usage instead of resetting to minimum on minor data fluctuations
  3. SessionLogReader detects a newly created JSONL file even when the parent directory mod-time has not changed
**Plans**: TBD

### Phase 5: Spec Sync
**Goal**: Spec files accurately describe the current codebase with no undocumented components or incorrect API signatures
**Depends on**: Phase 4
**Requirements**: BUG-05
**Success Criteria** (what must be TRUE):
  1. ThrottleTracker is documented in the relevant spec file
  2. AccountStore.canAddAccount signature and behavior match what is documented in the spec
  3. No other undocumented divergences remain between spec and code (verified by reading spec against source)
**Plans**: TBD

## Progress

**Execution Order:** 1 → 2 → 3 → 4 → 5

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Context & Projection Fixes | 1/1 | Complete   | 2026-03-18 | - |
| 2. Data Accuracy Fixes | 2/2 | Complete   | 2026-03-18 | - |
| 3. Write Performance | 1/1 | Complete   | 2026-03-18 | - |
| 4. Polling & Discovery Hardening | v1.10 | 0/TBD | Not started | - |
| 5. Spec Sync | v1.10 | 0/TBD | Not started | - |

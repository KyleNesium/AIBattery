# Requirements: AIBattery

**Defined:** 2026-03-18
**Core Value:** Show Claude API usage clearly and instantly from the menu bar

## v1.10 Requirements

Requirements for bugs and performance milestone. Each maps to roadmap phases.

### Bug Fixes

- [ ] **BUG-01**: Rate limit probe model list is dynamically maintained, not hardcoded — app recovers when Anthropic deprecates model IDs
- [x] **BUG-02**: Context window auto-detect adjusts downward when session data indicates a smaller tier
- [x] **BUG-03**: `estimatedTimeToLimit` provides projections below 50% utilization
- [ ] **BUG-04**: Today's tool call count reflects JSONL data, not just stats-cache
- [ ] **BUG-05**: Spec files reflect current code (ThrottleTracker documented, AccountStore.canAddAccount corrected)

### Performance

- [ ] **PERF-05**: `TokenLedger.merge()` batches disk writes instead of writing on every value increase
- [ ] **PERF-06**: `buildProjectTokens` avoids redundant full iteration of JSONL entries
- [ ] **PERF-07**: `RateLimitFetcher` probe fallback minimizes unnecessary API calls
- [ ] **PERF-08**: `AdaptivePollingState` doesn't reset on minor data changes during active churn
- [ ] **PERF-09**: `SessionLogReader` discovery detects new JSONL files even when directory mod-time is unchanged

## Future Requirements

(None deferred — all items scoped to this milestone)

## Out of Scope

| Feature | Reason |
|---------|--------|
| New UI features | This milestone is strictly bugs and performance |
| App Store distribution | Blocked by Apple Developer cert |
| View-level tests | Valuable but separate initiative |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| BUG-02 | Phase 1 | Complete |
| BUG-03 | Phase 1 | Complete |
| BUG-01 | Phase 2 | Pending |
| BUG-04 | Phase 2 | Pending |
| PERF-05 | Phase 3 | Pending |
| PERF-06 | Phase 3 | Pending |
| PERF-07 | Phase 4 | Pending |
| PERF-08 | Phase 4 | Pending |
| PERF-09 | Phase 4 | Pending |
| BUG-05 | Phase 5 | Pending |

**Coverage:**
- v1.10 requirements: 10 total
- Mapped to phases: 10
- Unmapped: 0 ✓

---
*Requirements defined: 2026-03-18*
*Last updated: 2026-03-18 after roadmap creation*

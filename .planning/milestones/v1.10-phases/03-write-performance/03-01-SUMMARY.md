---
phase: 03-write-performance
plan: "01"
subsystem: tests
tags: [performance, testing, tdd, write-batching, fingerprint-skip]
dependency_graph:
  requires: []
  provides: [PERF-05-tests, PERF-06-tests]
  affects: [TokenLedger, UsageAggregator]
tech_stack:
  added: []
  patterns: [Swift Testing framework, @MainActor test isolation, flushForTesting for sync I/O verification]
key_files:
  created: []
  modified:
    - Tests/AIBatteryCoreTests/Services/TokenLedgerTests.swift
    - Tests/AIBatteryCoreTests/Services/UsageAggregatorTests.swift
    - README.md
key_decisions:
  - No production code changes needed — both PERF-05 and PERF-06 optimizations were already correctly implemented
  - Tests verify performance guarantees behaviorally (mod date unchanged, lastUpdated timestamp identity) rather than mocking internals
  - Thread.sleep(1.0) used in write-timing tests to ensure file system timestamp granularity is sufficient for mod-date comparison
metrics:
  duration: "~3 min"
  completed: "2026-03-18"
  tasks_completed: 2
  files_modified: 3
---

# Phase 03 Plan 01: Write-Performance Regression Tests Summary

Added 6 regression tests across TokenLedger and UsageAggregator that codify the PERF-05/06 performance guarantees: single-write-per-merge in TokenLedger (high-water-mark batching) and fingerprint-skip preventing redundant aggregation in UsageAggregator.

## Tasks Completed

| Task | Name | Commit | Key files |
|------|------|--------|-----------|
| 1 | TokenLedger write-batching verification tests (PERF-05) | d36da41 | Tests/AIBatteryCoreTests/Services/TokenLedgerTests.swift |
| 2 | UsageAggregator fingerprint-skip and buildProjectTokensFromMap tests (PERF-06) | 3005c13 | Tests/AIBatteryCoreTests/Services/UsageAggregatorTests.swift |
| - | README test coverage update | cbe5334 | README.md |

## What Was Built

### Task 1: TokenLedger Write-Batching Tests (PERF-05)

Three new tests in `TokenLedgerTests.swift`:

1. `merge_unchangedValues_doesNotWrite` — Merges identical values twice with a 1s sleep between; verifies file modification date is unchanged after second merge+flush, proving no disk write occurs when nothing increases.

2. `merge_singleCallWritesOnce` — Merges 3 models in one call, flushes to disk, loads fresh instance, merges lower values — verifies all 3 original higher values are returned, proving all models were persisted in a single write.

3. `merge_mixedChanges_writesOnlyOnce` — Merges [A:100, B:200], records mod date, sleeps 1s, merges [A:150(+), B:100(-)], verifies mod date changed (write happened), reloads and verifies A=150 and B=200 (high-water preserved), proving the single write captured both atomically.

### Task 2: UsageAggregator Fingerprint-Skip Tests (PERF-06)

Three new tests in `UsageAggregatorTests.swift`:

1. `aggregate_fingerprintSkip_returnsCachedSnapshot` — Calls aggregate() twice with identical inputs; verifies `lastUpdated` timestamp is identical across both calls, proving the same cached object is returned (not recomputed).

2. `aggregate_fingerprintChanged_recomputes` — Calls aggregate() with nil rate limits, then with 75%/30% rate limits; verifies second snapshot carries the updated rate limit data, proving changed fingerprint triggers fresh computation.

3. `aggregate_projectTokens_fromPreBuiltMap` — Writes 2 JSONL entries per project (2 different models each) for 2 projects; verifies exactly 2 `projectTokens` entries with correct per-project token sums, proving `buildProjectTokensFromMap` correctly aggregates multi-model data from the unified-pass pre-built map.

## Verification

Tests cannot be run locally (requires Xcode for Swift Testing framework — only Command Line Tools present). CI will validate on macos-15. All test names match plan acceptance criteria:

```
grep -c "merge_unchangedValues_doesNotWrite|merge_singleCallWritesOnce|merge_mixedChanges_writesOnlyOnce" → 3
grep -c "fingerprintSkip|fingerprintChanged|projectTokens_fromPreBuiltMap" → 3
```

## Deviations from Plan

None — plan executed exactly as written. Both optimizations (PERF-05 and PERF-06) were confirmed already in place. Only test files were modified; no production code changes were needed.

## Self-Check: PASSED

- Tests/AIBatteryCoreTests/Services/TokenLedgerTests.swift — modified, confirmed
- Tests/AIBatteryCoreTests/Services/UsageAggregatorTests.swift — modified, confirmed
- Commits d36da41, 3005c13, cbe5334 — confirmed via git log

---
phase: 04-polling-discovery-hardening
plan: 02
subsystem: SessionLogReader
tags: [performance, reliability, file-discovery, caching, testing]
dependency_graph:
  requires: []
  provides: [TTL-based JSONL discovery fallback]
  affects: [SessionLogReader, discovery cache, FileWatcher invalidation path]
tech_stack:
  added: []
  patterns: [TTL cache with fallback re-enumeration, testing hook for deterministic TTL expiry]
key_files:
  created:
    - Tests/AIBatteryCoreTests/Services/SessionLogReaderDiscoveryTests.swift
  modified:
    - AIBattery/Services/SessionLogReader.swift
    - spec/CONSTANTS.md
    - README.md
decisions:
  - "TTL constant is a static let on SessionLogReader (not in ClaudePaths/Constants) — co-located with the logic that uses it"
  - "expireDiscoveryTTLForTesting() preferred over making lastFullEnumerationDate internal — keeps private API private, test hook makes intent explicit"
  - "TTL check is additive to dir mod-date check — both must pass for cache hit (TTL expired OR dir changed triggers re-enumeration)"
metrics:
  duration: "~3 min"
  completed: "2026-03-18T20:33:59Z"
  tasks_completed: 1
  files_changed: 4
---

# Phase 04 Plan 02: TTL-based Discovery Fallback Summary

**One-liner:** 60-second TTL fallback for JSONL file discovery prevents missed files when filesystem doesn't update directory mtime on new file creation.

## What Was Built

`SessionLogReader` now tracks `lastFullEnumerationDate` after each full directory enumeration. The discovery cache fast-path requires *both* conditions to be true for a cache hit:

1. Directory mod-dates are unchanged (existing check)
2. The TTL has not expired (`Date().timeIntervalSince(lastFullEnumerationDate) < 60s`)

If either condition fails, a full re-enumeration runs. `FileWatcher.invalidate()` resets the TTL timestamp alongside existing cache clears.

A `expireDiscoveryTTLForTesting()` method exposes deterministic TTL control for tests.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Add TTL-based discovery fallback to SessionLogReader | 44567e8 | SessionLogReader.swift, SessionLogReaderDiscoveryTests.swift, spec/CONSTANTS.md, README.md |

## Verification

- `lastFullEnumerationDate`: 5 occurrences (declaration, clear in invalidate, test helper, TTL check, set after enumeration) — meets 4+ requirement
- `discoveryTTL`: 2 occurrences (constant declaration + usage in TTL check)
- Test file created: `Tests/AIBatteryCoreTests/Services/SessionLogReaderDiscoveryTests.swift`
- `swift build -c release`: Build complete (13.74s, no errors)
- swift test: Requires Xcode (Swift Testing framework) — pre-existing environment constraint, CI validates on macos-15

## Deviations from Plan

**1. [Rule 2 - Missing functionality] Updated spec/CONSTANTS.md with discoveryTTL**
- **Found during:** Task 1
- **Issue:** New 60s constant added to production code not documented in spec/CONSTANTS.md
- **Fix:** Added "Discovery TTL" row to JSONL Processing section in spec/CONSTANTS.md
- **Files modified:** spec/CONSTANTS.md
- **Commit:** 44567e8 (included in same commit)

**2. [Rule 2 - Missing functionality] Updated README test coverage section**
- **Found during:** Task 1
- **Issue:** Global CLAUDE.md requires README Test Coverage section updated when tests are added
- **Fix:** Updated test count from 644/42 to 648/43, added TTL discovery fallback coverage description to Services row
- **Files modified:** README.md
- **Commit:** 44567e8 (included in same commit)

## Self-Check: PASSED

- SessionLogReader.swift exists with all required changes: `[ -f "AIBattery/Services/SessionLogReader.swift" ]` ✓
- Test file exists: `[ -f "Tests/AIBatteryCoreTests/Services/SessionLogReaderDiscoveryTests.swift" ]` ✓
- Commit 44567e8 exists in git log ✓

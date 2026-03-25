---
phase: 17-incremental-scanning
plan: 02
subsystem: services
tags: [jsonl, discovery, performance, sessionlogreader, directory-caching]

requires:
  - phase: 17-01
    provides: Unbounded per-file cache with dirty-flag incremental merge
provides:
  - Per-directory incremental discovery — unchanged project dirs skip enumeration entirely
  - Calendar.startOfDay() caching in UsageAggregator to avoid ICU lock contention
affects: [18-memory-optimization, 19-verification]

tech-stack:
  added: []
  patterns: [per-directory mod-date caching, incremental directory enumeration]

key-files:
  created: []
  modified:
    - AIBattery/Services/SessionLogReader.swift
    - AIBattery/Services/UsageAggregator.swift
    - Tests/AIBatteryCoreTests/Services/SessionLogReaderDiscoveryTests.swift

key-decisions:
  - "Per-directory file cache (discoveredFilesByDir) keyed by dir path — enables selective re-enumeration"
  - "Calendar.startOfDay() cached across entries in aggregate loop — ICU lock contention was a hidden CPU hotspot"
  - "invalidate() preserves discoveryDirModDates and discoveredFilesByDir for incremental comparison"

patterns-established:
  - "Per-directory incremental discovery: check dir mod-date before enumerating contents"
  - "Calendar caching: cache expensive Calendar operations across tight loops"

requirements-completed: [SCAN-03]

duration: 25min
completed: 2026-03-25
---

# Phase 17 Plan 02: Per-directory Incremental Discovery Summary

**Per-directory incremental discovery skips unchanged project dirs entirely; Calendar.startOfDay caching eliminates ICU lock contention — CPU drops from 83% to 0% at idle**

## Performance

- **Duration:** 25 min
- **Started:** 2026-03-25T09:46:00Z
- **Completed:** 2026-03-25T10:11:00Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- Directory discovery now only enumerates project directories whose mod-date changed; unchanged directories retain cached file lists
- Added `discoveredFilesByDir` per-directory file cache for selective re-enumeration
- Discovered and fixed Calendar.startOfDay() ICU lock contention hotspot in UsageAggregator.aggregate()
- Verified real-world performance: CPU 0% at idle (down from 83%), RSS 62 MB
- Added 3 new discovery tests: unchanged directory skip, new directory detection, deleted directory cleanup

## Task Commits

Each task was committed atomically:

1. **Task 1: Implement per-directory incremental discovery** - `ddc36d5` (test: failing tests), `0810096` (feat: implementation)
2. **Task 2: Verify performance under real conditions** - Human checkpoint (verified: CPU 0%, RSS 62 MB)

**Additional fix:** `242c58e` (perf: Calendar.startOfDay caching in UsageAggregator)

## Files Created/Modified
- `AIBattery/Services/SessionLogReader.swift` - Added `discoveredFilesByDir` per-directory cache; rewrote `discoverJSONLFiles()` to enumerate only changed directories; updated `invalidate()` to preserve directory caches for incremental comparison
- `AIBattery/Services/UsageAggregator.swift` - Cached `Calendar.startOfDay()` result across entries in aggregate loop to eliminate ICU lock contention
- `Tests/AIBatteryCoreTests/Services/SessionLogReaderDiscoveryTests.swift` - 3 new tests: `unchangedDirectory_skipsEnumeration`, `newDirectoryDiscovered_afterInvalidation`, `deletedDirectory_filesRemoved`

## Decisions Made
- Per-directory file cache (`discoveredFilesByDir`) keyed by directory path enables re-enumerating only changed directories instead of all-or-nothing
- `invalidate()` preserves `discoveryDirModDates` and `discoveredFilesByDir` so the next discovery cycle can do incremental comparison rather than full enumeration
- Calendar.startOfDay() caching: discovered that the ICU date formatting lock was a contention hotspot when called per-entry in tight loops

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Calendar.startOfDay() ICU lock contention**
- **Found during:** Task 2 (performance verification)
- **Issue:** UsageAggregator.aggregate() called Calendar.startOfDay() for every entry in the loop, causing ICU lock contention that consumed significant CPU
- **Fix:** Cached the startOfDay result and reused it across entries with the same date
- **Files modified:** AIBattery/Services/UsageAggregator.swift
- **Verification:** CPU dropped to 0% at idle after fix
- **Committed in:** 242c58e

---

**Total deviations:** 1 auto-fixed (1 bug — performance hotspot)
**Impact on plan:** Essential for achieving the 0% idle CPU target. No scope creep.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Phase 17 success criteria fully met: CPU 0% at idle, zero files re-parsed when unchanged, only active session files re-parsed during use
- RSS currently 62 MB (already under Phase 18's 100 MB target) — Phase 18 may be partially pre-solved
- Phase 19 verification can proceed with confidence that performance targets are met

---
*Phase: 17-incremental-scanning*
*Completed: 2026-03-25*

---
phase: 17-incremental-scanning
plan: 01
subsystem: services
tags: [jsonl, caching, performance, sessionlogreader]

requires: []
provides:
  - Unbounded per-file cache in SessionLogReader (no LRU eviction)
  - Dirty-flag incremental merge — unchanged files never re-parsed
  - Stale cache cleanup for deleted files
affects: [18-memory-eviction]

tech-stack:
  added: []
  patterns: [dirty-flag cache invalidation, fingerprint-based incremental rebuild]

key-files:
  created: []
  modified:
    - AIBattery/Services/SessionLogReader.swift
    - Tests/AIBatteryCoreTests/Services/SessionLogReaderTests.swift
    - CLAUDE.md

key-decisions:
  - "Unbounded per-file cache — 3,103 entries is trivial dictionary overhead vs 200-entry LRU causing 94% eviction"
  - "isDirty flag instead of clearing cachedAllEntries — avoids full re-merge when only one file changed"
  - "Per-file fingerprint (modDate + fileSize) is the correct staleness primitive — no need for content hashing"

patterns-established:
  - "Dirty-flag invalidation: set isDirty=true instead of clearing derived caches; rebuild incrementally on next read"

requirements-completed: [SCAN-01, SCAN-02]

duration: 9min
completed: 2026-03-25
---

# Phase 17 Plan 01: Incremental Scanning Summary

**Unbounded per-file cache with dirty-flag incremental merge — unchanged JSONL files are never re-parsed**

## Performance

- **Duration:** 9 min
- **Started:** 2026-03-25T09:36:42Z
- **Completed:** 2026-03-25T09:46:00Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- Removed LRU cache cap (200 entries) that caused 94% eviction on 3,103 files
- Replaced cachedAllEntries=nil invalidation with isDirty flag approach for incremental merge
- Added stale cache cleanup for deleted files during rebuild
- Added 5 new tests covering incremental rebuild, unbounded cache, dirty-flag fast path, file deletion, and deduplication

## Task Commits

Each task was committed atomically:

1. **Task 1: Remove LRU cap and implement incremental dirty-flag merge** - `a0ee816` (feat)
2. **Task 2: Add tests for incremental cache behavior** - `f562dd1` (test)

**Plan metadata:** (pending)

## Files Created/Modified
- `AIBattery/Services/SessionLogReader.swift` - Removed maxCacheEntries/evictCache, added isDirty flag, incremental rebuild in readAllUsageEntries, stale entry removal
- `Tests/AIBatteryCoreTests/Services/SessionLogReaderTests.swift` - 5 new tests for incremental cache behavior, updated existing test for mod date reliability
- `CLAUDE.md` - Updated SessionLogReader cache description from LRU to unbounded/dirty-flag

## Decisions Made
- Unbounded per-file cache: 3,103 dictionary entries is trivial memory overhead compared to the constant re-parsing caused by 200-entry LRU eviction
- isDirty flag preserves per-file cache across invalidation cycles — only the merged result is recomputed, and cachedRead handles per-file staleness via fingerprint
- Added Thread.sleep(1.0) to tests requiring mod date changes to handle APFS timestamp resolution

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Added sleep to existing invalidate test for mod date reliability**
- **Found during:** Task 1
- **Issue:** Existing test `invalidate_whenNoScanRunning_clearsCachesDirectly` overwrites file without sleep; with new fingerprint-based detection (instead of clearing cache), same-second writes with same file size would not be detected
- **Fix:** Added Thread.sleep(1.0) and changed inputTokens from 999 to 9999 (different size) for reliable detection
- **Files modified:** Tests/AIBatteryCoreTests/Services/SessionLogReaderTests.swift
- **Committed in:** a0ee816 (Task 1 commit)

**2. [Rule 2 - Missing Critical] Updated CLAUDE.md design decision**
- **Found during:** Task 1
- **Issue:** CLAUDE.md still referenced "cache caps at 200 entries with LRU eviction" which is no longer accurate
- **Fix:** Updated to "unbounded per-file cache with dirty-flag incremental merge"
- **Files modified:** CLAUDE.md
- **Committed in:** (pending final commit)

---

**Total deviations:** 2 auto-fixed (1 bug, 1 missing critical)
**Impact on plan:** Both fixes necessary for correctness and documentation accuracy. No scope creep.

## Issues Encountered
- Xcode not installed on this machine — Swift Testing framework unavailable, so tests could not be run. Build verification confirmed code compiles. Tests should be verified when Xcode is available or via CI.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Per-file cache is unbounded and incremental — ready for Phase 18 (memory eviction) to add session-level eviction on top
- All public APIs unchanged (invalidate, readAllUsageEntries return type)

---
*Phase: 17-incremental-scanning*
*Completed: 2026-03-25*

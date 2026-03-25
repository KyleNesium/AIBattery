# Phase 16: Idle and Lock Detection - Context

**Gathered:** 2026-03-24
**Status:** Ready for planning

<domain>
## Phase Boundary

Suspend all timers (polling, FileWatcher fallback, breath) when the screen is locked or system idle >5min. Resume on wake/activity. No new timers — piggyback idle check on existing polling cycle.

</domain>

<decisions>
## Implementation Decisions

### Idle Detection Strategy
- Detect system idle via `CGEventSourceSecondsSinceLastEventType(.hidSystemState, .mouseMoved)` polled every 60s during normal polling cycle — no new timer
- Suspend ALL timers on idle/lock: polling timer, FileWatcher fallback timer, breath timer
- Resume via existing `didWakeNotification` + `screensDidWakeNotification` — already wired in UsageViewModel and StatusBarManager
- Idle threshold: 5 minutes (300 seconds)
- Screen lock detection: `NSWorkspace.sessionDidResignActiveNotification` + `screensDidSleepNotification`

### Claude's Discretion
- Whether to add `sessionDidBecomeActiveNotification` alongside existing wake observers
- Implementation of idle state coordination between UsageViewModel and StatusBarManager

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `UsageViewModel` already has `willSleep`/`didWake` observers (lines 245-257)
- `StatusBarManager` already has `screensDidSleep`/`screensDidWake` observers (lines 406-418)
- FileWatcher has `startFallbackTimer()`/`stop()` methods

### Integration Points
- `UsageViewModel.refresh()` — where idle check can piggyback
- `FileWatcher.shared` — needs `suspendFallbackTimer()`/`resumeFallbackTimer()` methods
- `StatusBarManager` — already gates breath timer on sleep/wake

</code_context>

<specifics>
## Specific Ideas

No specific requirements — infrastructure phase

</specifics>

<deferred>
## Deferred Ideas

None

</deferred>

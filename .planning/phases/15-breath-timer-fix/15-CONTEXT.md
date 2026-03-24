# Phase 15: Breath Timer Fix - Context

**Gathered:** 2026-03-24
**Status:** Ready for planning

<domain>
## Phase Boundary

Gate the breath timer on popover visibility. When popover is closed, stop the timer entirely. When popover opens, restart it if conditions are met (≥95% or sparkle active).

</domain>

<decisions>
## Implementation Decisions

### Breath Timer Gating
- Add `!toggleState.isShowing` check to `updateBreathTimer()` — stop timer when popover is not visible
- The breath animation animates the menu bar ICON (visible even when popover closed), but 83% CPU for a subtle icon pulse is unacceptable — static icon when closed is the right tradeoff
- On panel show: call `updateBreathTimer()` to restart if conditions met
- On panel hide: stop breath timer immediately
- Screen sleep/wake observers already exist (lines 406-418) — keep them, they complement the visibility gate

### Claude's Discretion
- Whether to restart breath timer on every panel show or only when conditions change
- Whether to also gate on `isSparkleActive` state transitions

</decisions>

<code_context>
## Existing Code Insights

### Key Files
- `StatusBarManager.swift:344-351` — `updateBreathTimer()` — needs visibility guard
- `StatusBarManager.swift:395-435` — `startBreathTimerIfNeeded()` — timer creation
- `StatusBarManager.swift:437-439` — `stopBreathTimer()` — timer invalidation
- `StatusBarManager.swift:57` — `toggleState` — `PanelToggleState` with `.isShowing`

### Integration Points
- Panel show/hide already triggers through `toggleState` — hook breath timer restart there
- `currentPercent`, `currentColor`, `currentIsThrottled` are stored state — available for restart

</code_context>

<specifics>
## Specific Ideas

No specific requirements — infrastructure phase

</specifics>

<deferred>
## Deferred Ideas

None

</deferred>

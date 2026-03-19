# Phase 10: Popover Performance - Context

**Gathered:** 2026-03-20
**Status:** Ready for planning

<domain>
## Phase Boundary

Eliminate remaining popover open/close lag and gate all periodic updates on panel visibility. Pure performance work — no behavioral changes.

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion
All implementation choices are at Claude's discretion — pure infrastructure phase. Key considerations:
- We already fixed: frame resize debounce, MarqueeText GeometryReader, animation durations, TimelineView transitions, Timer.publish freeze
- Remaining work: audit for any other lag sources, ensure UsageBarsSection TimelineView is gated, reduce GeometryReader count where possible
- Note: the footer TimelineView was reverted to TimelineView (Timer.publish caused freeze) — it's fine since SwiftUI removes the view from hierarchy on orderOut

</decisions>

<code_context>
## Existing Code Insights

### Already Fixed (v1.9.4)
- Frame resize observer debounced (16ms) + gated on isPanelShowing
- MarqueeText nested GeometryReader → PreferenceKey
- MotionConstants: 0.15s/0.1s easeOut (from 0.2s/0.15s easeInOut)
- .transition(.opacity) removed from inside UsageBarsSection TimelineView
- contentTransition(.numericText()) removed from ProjectUsageSection + TokenHealthSection
- NSApp.activate moved after makeKeyAndOrderFront

### Remaining GeometryReaders (4)
- UsageBarsSection:81 — rate limit bar width
- TokenHealthSection:69 — context health bar width
- InsightsRowsAndHover:86 — chart hover overlay
- MarqueeText:48 — container width (already optimized)

### Integration Points
- StatusBarManager — panel open/close path
- All Views/ files with TimelineView, GeometryReader, or animations

</code_context>

<specifics>
## Specific Ideas

No specific requirements — infrastructure phase.

</specifics>

<deferred>
## Deferred Ideas

None.

</deferred>

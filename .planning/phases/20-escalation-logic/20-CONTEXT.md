# Phase 20: Escalation Logic - Context

**Gathered:** 2026-03-31
**Status:** Ready for planning

<domain>
## Phase Boundary

Replace urgency scoring in `autoResolvedMode` with a deterministic four-tier escalation ladder. Add session awareness so context health is excluded when no session has been active in the last 30 minutes. Remove time-to-limit boost scoring. Pure logic refactoring — no new UI, no new state storage.

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion
All implementation choices are at Claude's discretion — pure infrastructure phase. The requirements and success criteria fully specify the behavior. The escalation ladder order, threshold values, and session staleness window are all defined in REQUIREMENTS.md.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `UsageSnapshot.autoResolvedMode` (line 98) — current computed property to be replaced
- `UsageSnapshot.urgencyScore()` / `interpolate()` — to be removed (AUTO-06)
- `TokenHealthStatus.lastActivity` field — existing field for session recency (AUTO-05)
- `RateLimitUsage.representativeClaim` — identifies binding rate limit window (AUTO-02)
- `RateLimitUsage.isThrottled` — throttle detection (AUTO-03 tier 1)
- `UsageSnapshot.percent(for:)` — percentage accessor for each metric mode
- `UsageSnapshot.nearExhaustionThreshold` — 95% threshold (will be replaced by 80%)

### Established Patterns
- Three `MetricMode` cases: `.fiveHour`, `.sevenDay`, `.contextHealth`
- `topSessionHealths` array — sessions sorted by highest context usage
- Tests in `UsageSnapshotTests.swift` use Swift Testing framework

### Integration Points
- `StatusBarManager` reads `autoResolvedMode` for menu bar icon
- `UsagePopoverView` reads `autoResolvedMode` for default view selection
- `UsageViewModel` produces `UsageSnapshot` — no changes needed there

</code_context>

<specifics>
## Specific Ideas

No specific requirements — infrastructure phase. Requirements AUTO-01 through AUTO-06 (excluding AUTO-04) fully specify the behavior.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

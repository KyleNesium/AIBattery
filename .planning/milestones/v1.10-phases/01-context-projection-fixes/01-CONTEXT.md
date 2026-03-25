# Phase 1: Context & Projection Fixes - Context

**Gathered:** 2026-03-18
**Status:** Ready for planning

<domain>
## Phase Boundary

Fix two bugs in the monitoring subsystem: (1) context window tier detection only goes up, never down — add downward adjustment; (2) time-to-limit projections are gated or hidden at certain utilization levels — ensure they display across all ranges.

</domain>

<decisions>
## Implementation Decisions

### Context Window Tier (BUG-02)
- Add downward tier adjustment in `TokenHealthMonitor.assessSingleSession()` at the same location as the upward logic (lines 125-134)
- Use the same `tiers` array — find the smallest tier that fits the observed token count
- Downward adjustment should only trigger when observed tokens are significantly below the current tier (e.g., observed < tier_below_current) to avoid thrashing on sessions that just happen to be small
- Preserve the existing upward logic unchanged — extend, don't rewrite

### Time-to-Limit Projections (BUG-03)
- The code gate in `RateLimitUsage.estimatedTimeToLimit` is already at 20% utilization, not 50%
- CONSTANTS.md says 50% — verify whether there's a display-level filter in the view layer or UsageSnapshot that hides the estimate below 50%
- If the only issue is CONSTANTS.md being stale, update the doc; if there's a display filter, lower or remove it
- Keep the 20% minimum gate (below that, burn rate projections are too noisy to be useful)

### Claude's Discretion
- Exact threshold for downward tier adjustment (how far below current tier triggers a downgrade)
- Whether to use hysteresis (require N consecutive low readings before downgrading)
- Test approach for verifying tier transitions

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `TokenHealthMonitor.assessSingleSession()` — existing tier detection at lines 125-134
- `TokenHealthConfig.contextWindow(for:)` — static model→tier lookup (lines 79-86)
- `TokenHealthConfig` tiers array: `[200_000, 500_000, 1_000_000, 2_000_000, 5_000_000]`
- `RateLimitUsage.estimatedTimeToLimit(for:)` — burn rate calculation at lines 84-111

### Established Patterns
- Tier detection uses first-match in ordered array: `tiers.first(where: { $0 > observedTokens })`
- `usableContextRatio` is 1.0 in code (spec says 0.80 — another drift item for Phase 5)
- Band thresholds: green < 60%, orange 60-80%, red > 80%

### Integration Points
- `TokenHealthMonitor` feeds `UsageViewModel` which drives all UI
- `RateLimitUsage` is part of `UsageSnapshot` — consumed by popover views
- Changes here flow through existing `UsageAggregator` fingerprint-based skip

</code_context>

<specifics>
## Specific Ideas

No specific requirements — these are well-defined bug fixes with clear success criteria from the roadmap.

</specifics>

<deferred>
## Deferred Ideas

- `usableContextRatio` spec/code drift (1.0 vs 0.80) — belongs in Phase 5 (Spec Sync)

</deferred>

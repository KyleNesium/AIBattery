# Phase 21: Hysteresis - Context

**Gathered:** 2026-04-01
**Status:** Ready for planning

<domain>
## Phase Boundary

Add hysteresis to auto mode so that the displayed metric view does not flip-flop between polls when values hover near escalation thresholds. Requires cross-poll state storage (previous mode) and a 10pp de-escalation band. Pure logic addition on top of Phase 20's escalation ladder — no UI changes.

</domain>

<decisions>
## Implementation Decisions

### State Storage & Architecture
- `UsageViewModel` stores `lastResolvedMode: MetricMode?` as the cross-poll state — ViewModel already owns polling lifecycle, natural place for this
- Hysteresis is applied in `UsageViewModel` after calling `autoResolvedMode` — keeps `UsageSnapshot` as a pure value type with no mutation
- Hysteresis resets on manual mode override (user picks a view) and on account switch — fresh start makes sense
- Throttle tier bypasses hysteresis entirely — hard constraint, always shown immediately

### Hysteresis Thresholds & Behavior
- 10pp downward de-escalation band (e.g., RL must drop below 70% to release from Tier 2, context below 50% to release from Tier 3)
- Upward escalation is immediate — no hysteresis band when escalating to a higher tier
- No minimum consecutive polls required — the 10pp band provides sufficient debounce
- Session going stale (>30min) immediately drops context from competition — staleness is a hard gate, not subject to hysteresis

### Claude's Discretion
- Internal naming of the hysteresis method/property
- Whether to extract threshold constants to UsageSnapshot or keep in ViewModel
- Test structure and naming for hysteresis scenarios

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `UsageSnapshot.autoResolvedMode` — Phase 20's four-tier escalation ladder (the input to hysteresis)
- `UsageSnapshot.rateLimitEscalationThreshold` (80%) and `contextEscalationThreshold` (60%) — existing threshold constants
- `UsageSnapshot.hasActiveSession` — session staleness check (30min window)
- `UsageSnapshot.percent(for:)` — percentage accessor for each metric mode
- `UsageViewModel` — `@MainActor ObservableObject` that owns polling cycle and publishes `snapshot`

### Established Patterns
- `UsageSnapshot` is a pure struct (value type) — all computed properties, no mutation
- `UsageViewModel` publishes state changes via `@Published` properties
- Tests use Swift Testing framework (`@Test`, `#expect`)
- Phase 20 tests in `UsageSnapshotTests.swift` cover escalation ladder — hysteresis tests extend these

### Integration Points
- `UsageViewModel.updateSnapshot()` — where the new hysteresis logic hooks in (after snapshot creation, before publishing)
- `StatusBarManager` and `UsagePopoverView` consume the resolved mode — they should see the hysteresis-filtered result
- Manual mode override in popover — needs to reset hysteresis state

</code_context>

<specifics>
## Specific Ideas

No specific requirements — the 10pp band and immediate escalation behavior are well-defined in REQUIREMENTS.md and the accepted decisions above.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

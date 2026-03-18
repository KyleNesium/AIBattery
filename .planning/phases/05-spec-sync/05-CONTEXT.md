# Phase 5: Spec Sync - Context

**Gathered:** 2026-03-18
**Status:** Ready for planning

<domain>
## Phase Boundary

Sync spec files with current codebase. Document ThrottleTracker, correct AccountStore.canAddAccount, and audit for any other spec/code divergences introduced by phases 1-4.

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion
All implementation choices are at Claude's discretion — pure infrastructure/docs phase.

Key areas to check:
1. ThrottleTracker not in spec/ARCHITECTURE.md or spec/DATA_LAYER.md
2. AccountStore.canAddAccount — spec says `< 2` but code uses `maxAccounts = 3`
3. Any spec drift from Phase 1-4 changes (new properties, changed APIs, removed code)
4. CONSTANTS.md already fixed for 20% threshold in Phase 1 — verify no other stale values

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `spec/ARCHITECTURE.md` — app structure, data flow, project tree
- `spec/DATA_LAYER.md` — models, services, algorithms
- `spec/UI_SPEC.md` — views, layout, colors
- `spec/CONSTANTS.md` — hardcoded values

### Established Patterns
- Spec-driven workflow: spec is source of truth
- CLAUDE.md says "if you find spec/code drift, fix the spec first"

### Integration Points
- Changes from phases 1-4 need spec reflection: bidirectional tier detect, dynamic probe models, JSONL tool call counting, adaptive polling changes, discovery TTL

</code_context>

<specifics>
## Specific Ideas

No specific requirements — open to standard approaches.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

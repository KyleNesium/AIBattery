# Phase 13: Reliability - Context

**Gathered:** 2026-03-20
**Status:** Ready for planning

<domain>
## Phase Boundary

Fix intermittent panel no-open on menu bar icon click and eliminate any remaining UI freeze/hang during normal panel interaction. This is a debugging + fix phase — diagnose root cause first, then apply targeted fixes.

</domain>

<decisions>
## Implementation Decisions

### Diagnostic Approach
- Add structured os_log diagnostics to all dismiss paths — log which path fired and when to identify race conditions
- Temporary diagnostics only — remove after fix to keep codebase clean
- Investigation order: deactivation observer race first (most likely cause for LSUIElement apps), then click-outside monitor timing, then toggleState desync analysis

### Fix Strategy
- Add a brief guard window after show — ignore deactivation events for ~100ms after panel appears to prevent activation race
- Debounce statusItemClicked with 150ms cooldown — prevents double-click race conditions
- Verify fix with manual testing (rapid open/close cycles + stress test loop) — timing issues can't be reproduced in unit tests alone

### Hang Investigation
- Profile with os_signpost around all main-thread work in show path — NSApp.activate(ignoringOtherApps:) is the known slow call (~100-300ms)
- If hang is in NSApp.activate: move to DispatchQueue.main.async for non-blocking activation (partially done already per v1.12 decisions)
- No hang watchdog — too complex for a polish milestone; signpost profiling is sufficient

### Claude's Discretion
- Specific timing values for debounce/guard window can be tuned during implementation
- Additional dismiss path guards may be added if investigation reveals other race conditions

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `PanelToggleState` value-type state machine (line 10-35 in StatusBarManager.swift)
- `PopoverPanel` subclass with `onDismiss` callback (line 484-507)
- `os_signpost` already imported and used for PanelShow begin/end brackets (line 444-446)
- `panelShowLog` OSLog instance already exists (line 54)

### Established Patterns
- All dismiss paths consolidated through `PopoverPanel.orderOut` → `onDismiss` callback
- `toggleState.isShowing` is the single source of truth for panel visibility
- Frame resize observer already gated on `toggleState.isShowing` (line 154)
- Event monitors (escape, click-outside, deactivation) all check `toggleState.isShowing` before acting

### Integration Points
- `statusItemClicked()` (line 436) — the entry point for all panel toggle actions
- `NSApplication.didResignActiveNotification` observer (line 222) — most likely race condition source
- `clickOutsideMonitor` (line 210) — global event monitor that could fire during show sequence
- `NSApp.activate(ignoringOtherApps:)` (line 449) — known slow call that may cause deactivation/reactivation cycle

</code_context>

<specifics>
## Specific Ideas

- User reports: "I still click on the icon in the menubar and sometimes it doesn't open at all"
- STATE.md blocker: "User reports intermittent hang still occurs despite v1.12 fixes — root cause not yet identified"
- The deactivation observer firing during the show sequence is the prime suspect — LSUIElement apps have non-standard activation behavior

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

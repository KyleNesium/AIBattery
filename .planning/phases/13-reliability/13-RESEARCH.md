# Phase 13: Reliability - Research

**Researched:** 2026-03-20
**Domain:** macOS LSUIElement app panel activation race conditions, status item click reliability
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Add structured os_log diagnostics to all dismiss paths — log which path fired and when to identify race conditions
- Temporary diagnostics only — remove after fix to keep codebase clean
- Investigation order: deactivation observer race first (most likely cause for LSUIElement apps), then click-outside monitor timing, then toggleState desync analysis
- Add a brief guard window after show — ignore deactivation events for ~100ms after panel appears to prevent activation race
- Debounce statusItemClicked with 150ms cooldown — prevents double-click race conditions
- Verify fix with manual testing (rapid open/close cycles + stress test loop) — timing issues can't be reproduced in unit tests alone
- Profile with os_signpost around all main-thread work in show path — NSApp.activate(ignoringOtherApps:) is the known slow call (~100-300ms)
- If hang is in NSApp.activate: move to DispatchQueue.main.async for non-blocking activation (partially done already per v1.12 decisions)
- No hang watchdog — too complex for a polish milestone; signpost profiling is sufficient

### Claude's Discretion
- Specific timing values for debounce/guard window can be tuned during implementation
- Additional dismiss path guards may be added if investigation reveals other race conditions

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope
</user_constraints>

---

## Summary

Phase 13 addresses two user-reported reliability failures in a macOS LSUIElement menu bar app: (1) clicking the menu bar icon sometimes silently does nothing — the panel never appears — and (2) intermittent UI freeze/hang during panel interaction.

Phase 12 established a solid foundation: `PanelToggleState` (value-type state machine) ensures the toggle boolean never desyncs, `PopoverPanel.onDismiss` consolidates all dismiss paths, and deferred rendering removes chart computation from the `makeKeyAndOrderFront` critical path. Despite this, the no-open symptom persists, which means the problem is **not** a boolean desync — the state is correct, but the panel show sequence is being immediately undone.

The prime suspect is a race between `NSApp.activate(ignoringOtherApps: true)` and `NSApplication.didResignActiveNotification`. In LSUIElement apps, clicking the status bar button triggers the system to send a deactivation notification to the previous foreground app and activate AIBattery. However, `NSApp.activate` can itself trigger a deactivation/reactivation cycle that fires `didResignActiveNotification` on AIBattery's own notification queue — within milliseconds of `statusItemClicked` returning. When this happens, the deactivationObserver fires, calls `panel?.orderOut(nil)`, and the panel disappears before the user ever sees it.

**Primary recommendation:** Add a guard window timestamp to `statusItemClicked` — record `Date()` at show time and skip deactivation-triggered dismissals that arrive within 200ms of panel show. Independently, debounce `statusItemClicked` with a 150ms cooldown to eliminate double-click races.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| REL-01 | Menu bar icon click always opens the panel — diagnose and fix intermittent no-open | Root cause: `didResignActiveNotification` fires during activation sequence and immediately dismisses the panel; fix via guard-window timestamp in deactivationObserver |
| REL-02 | No UI freeze or hang during normal panel interaction | Root cause: `NSApp.activate(ignoringOtherApps:)` is synchronous on main thread (~100-300ms); calling it inline in `statusItemClicked` can block; ensure it is truly non-blocking via `DispatchQueue.main.async` |
</phase_requirements>

---

## Standard Stack

No new dependencies. All solutions use existing Apple frameworks already imported.

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| AppKit | macOS 13+ built-in | `NSPanel`, `NSStatusItem`, notification observers | Already in use; no alternative |
| Foundation | macOS 13+ built-in | `Date()`, `DispatchWorkItem`, `DispatchQueue` | Already in use |
| os.log / os.signpost | macOS built-in | Structured diagnostics, timing instrumentation | `panelShowLog` already exists in StatusBarManager |

**Installation:** No new packages needed.

---

## Architecture Patterns

### Current Panel Show Sequence (StatusBarManager.swift line 436–451)

```swift
// statusItemClicked() — current code
@objc private func statusItemClicked() {
    guard let panel, let button = statusItem?.button else { return }
    let action = toggleState.toggle()
    switch action {
    case .hide:
        panel.orderOut(nil)
    case .show:
        positionPanel(relativeTo: button)
        os_signpost(.begin, log: panelShowLog, name: "PanelShow")
        panel.makeKeyAndOrderFront(nil)
        os_signpost(.end, log: panelShowLog, name: "PanelShow")
        // Activate after showing — LSUIElement activation is slow (~100-300ms)
        NSApp.activate(ignoringOtherApps: true)
    }
}
```

### The Race Condition (REL-01 Root Cause)

Timeline of a failing click (approximate — timing is system-dependent):

```
t=0ms    statusItemClicked() fires
t=1ms    toggleState.toggle() → .show; toggleState.isShowing = true
t=2ms    positionPanel(), makeKeyAndOrderFront(nil) — panel is on screen
t=5ms    NSApp.activate(ignoringOtherApps: true) — starts activation sequence
t=15ms   macOS sends NSApplication.didResignActiveNotification (reactivation side-effect)
t=16ms   deactivationObserver fires; guard checks toggleState.isShowing == true
t=17ms   panel.orderOut(nil) called; onDismiss fires; toggleState.isShowing = false
t=18ms   Panel is gone — user never saw it
```

Result: from the user's perspective, clicking the icon did nothing. The toggle state ended up at `isShowing = false` (correct, reflects actual panel state), so the **next** click will attempt to show again — sometimes it works, sometimes the same race repeats.

### Pattern 1: Guard Window After Show (REL-01 Fix)

**What:** Record a timestamp when the panel is shown. In the deactivationObserver, skip dismissal if it arrives within a configurable guard window after show.

**When to use:** Specifically for `NSApplication.didResignActiveNotification` — this is the observer most prone to firing spuriously during activation.

```swift
// Source: Direct code analysis of StatusBarManager.swift
// In StatusBarManager — add one stored property:
private var panelShowedAt: Date = .distantPast

// In statusItemClicked() case .show, after makeKeyAndOrderFront:
panelShowedAt = Date()
NSApp.activate(ignoringOtherApps: true)

// In deactivationObserver closure — replace current guard:
{ [weak self] _ in
    guard let self, self.toggleState.isShowing else { return }
    // Ignore deactivation events arriving within 200ms of panel show —
    // they are caused by the activation sequence itself, not a real deactivation.
    guard Date().timeIntervalSince(self.panelShowedAt) > 0.2 else {
        os_log("deactivation suppressed (guard window)", log: self.panelShowLog, type: .debug)
        return
    }
    self.panel?.orderOut(nil)
}
```

**Timing:** 200ms is the recommended starting value (covers the ~100-300ms NSApp.activate window). The CONTEXT.md specifies ~100ms; use 200ms as the initial value since the activation sequence can take up to 300ms. Tune during implementation if testing reveals false positives (panel stays open when user switches apps).

### Pattern 2: statusItemClicked Debounce (REL-01 supplementary fix)

**What:** Track the last click time. If a second click arrives within 150ms of the first, ignore it.

**When to use:** Prevents double-click or rapid-click from toggling the state in a window where the panel is mid-show.

```swift
// Source: Direct code analysis of StatusBarManager.swift
// In StatusBarManager — add one stored property:
private var lastClickAt: Date = .distantPast

// In statusItemClicked() — add at top of method:
let now = Date()
guard now.timeIntervalSince(lastClickAt) > 0.15 else { return }
lastClickAt = now
```

**Ordering:** Check must come before `toggleState.toggle()` to prevent state mutations from a debounced click.

### Pattern 3: os_log Diagnostics for Race Investigation

**What:** Add os_log calls to every dismiss path that fire before the actual `orderOut` call, annotating which path fired and the time elapsed since panel show.

**When to use:** Before implementing fixes — run with diagnostics enabled to confirm which path is firing spuriously. Remove after fix is confirmed.

```swift
// Source: Apple Unified Logging documentation
// Pattern already established with panelShowLog in StatusBarManager.swift line 54

// In deactivationObserver:
os_log("dismiss: deactivation, elapsed=%.3fs",
       log: panelShowLog, type: .debug,
       Date().timeIntervalSince(panelShowedAt))

// In clickOutsideMonitor:
os_log("dismiss: click-outside, elapsed=%.3fs",
       log: panelShowLog, type: .debug,
       Date().timeIntervalSince(panelShowedAt))

// In escapeMonitor:
os_log("dismiss: escape, elapsed=%.3fs",
       log: panelShowLog, type: .debug,
       Date().timeIntervalSince(panelShowedAt))
```

Observe using Console.app filtered on `com.kylenesium.AIBattery` while reproducing the no-open behavior.

### Pattern 4: Non-Blocking NSApp.activate (REL-02 supplementary)

The current code calls `NSApp.activate(ignoringOtherApps: true)` synchronously after `makeKeyAndOrderFront`. Per Phase 12 decisions, this was noted as "partially done already per v1.12 decisions" — however, reviewing the current code at line 449, the call is **still synchronous** (not wrapped in `DispatchQueue.main.async`).

If the main-thread hang is caused by `NSApp.activate` blocking for 100-300ms, wrapping it removes that from the click handler:

```swift
// Current (potentially blocking):
NSApp.activate(ignoringOtherApps: true)

// Fix:
DispatchQueue.main.async {
    NSApp.activate(ignoringOtherApps: true)
}
```

**Note:** If the guard window fix (Pattern 1) is applied first, the async wrapping is less critical for REL-01. But for REL-02 (no hang during interaction), making activation non-blocking is correct regardless.

### Anti-Patterns to Avoid

- **Using NSWindow.didResignKeyNotification for dismiss:** Not reliable for LSUIElement apps — the panel may never become key if another app has focus, so the notification may not fire at all.
- **Setting a large guard window (>500ms):** Makes the app unresponsive to rapid open/close cycles. Tune down from 200ms if testing shows it prevents legitimate cmd-tab dismissal.
- **Removing the deactivationObserver entirely:** The guard window is the right surgical fix. Removing the observer means the panel stays open when the user switches to another app — that is a worse regression than the intermittent no-open.
- **Using `panel.isVisible` for guards:** Established anti-pattern from v1.9.4 — `isVisible` toggle made things worse. Always use `toggleState.isShowing`.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Timing-based debounce | Custom async/await actor | `Date()` comparison with stored timestamp | Simple, synchronous, testable; async adds unnecessary complexity |
| Diagnostics | Custom logging framework | `os_log` with existing `panelShowLog` | Infrastructure already in place; Console.app filters it |
| Activation timing | Custom notification center wrapper | `NSApplication.didResignActiveNotification` guard window | The observer is already working correctly — only the guard is missing |

**Key insight:** The bug is a single missing guard. All infrastructure (PanelToggleState, onDismiss callback, os_signpost) is already in place from Phase 12.

---

## Common Pitfalls

### Pitfall 1: Misidentifying the Race as a Desync

**What goes wrong:** Assuming Phase 12's desync fix should have caught this and looking for a new structural bug.
**Why it happens:** Phase 12 fixed structural desync (boolean reflecting wrong state). The Phase 13 bug is behavioral: the boolean is correct but the panel is dismissed by a spurious notification that arrives after correct show.
**How to avoid:** Trust the Phase 12 code. The `onDismiss` callback works correctly — it is being called legitimately, just by the wrong trigger. The fix is to filter the trigger, not to change the state machine.
**Warning signs:** Adding more `dismiss()` idempotency checks doesn't change the behavior.

### Pitfall 2: Guard Window Too Short

**What goes wrong:** Setting the guard window to 50ms or 100ms — activation can take up to ~300ms on a slow system, so the deactivation notification still arrives within the window.
**Why it happens:** Testing on a fast machine shows the race at ~20ms, so 100ms seems sufficient. On a loaded system or slower Mac, it may take 250ms.
**How to avoid:** Start with 200ms. The cost of false-positive (panel stays open 200ms longer than intended on a legitimate app switch) is imperceptible. The cost of too-short (bug reappears) is the entire reason for this phase.
**Warning signs:** Bug reproduced on the test machine after fix.

### Pitfall 3: Debounce Prevents Legitimate Double-Click to Close

**What goes wrong:** If the user intentionally clicks the icon twice in rapid succession (open then immediately close), the 150ms debounce blocks the second click.
**Why it happens:** Both the "open race" and "legitimate close" produce a click within the debounce window.
**How to avoid:** 150ms is short enough that deliberate double-click (to immediately close) lands outside the window. The guard window and debounce solve different problems — the guard window fixes the deactivation race; the debounce prevents a second click arriving while `NSApp.activate` is still running from making the toggle shoot past the intended state.
**Warning signs:** User complains panel gets stuck open after clicking twice fast.

### Pitfall 4: Diagnostics Left in After Fix

**What goes wrong:** `os_log` calls at `.debug` level added for investigation are not removed, adding noise to production logging.
**Why it happens:** Developer confirms fix, considers logging harmless.
**How to avoid:** The CONTEXT.md decision is explicit — temporary diagnostics only, remove after fix. Plan the diagnostic task as a separate wave from the fix task, with explicit removal in the fix wave.
**Warning signs:** Console.app shows diagnostic messages after the release tag.

### Pitfall 5: Wrapping NSApp.activate in async Without the Guard Window

**What goes wrong:** Making `NSApp.activate` async defers the call, but now the deactivation notification may arrive *after* `makeKeyAndOrderFront` and before the deferred `activate` — making the race harder to reason about.
**Why it happens:** Treating REL-01 and REL-02 as the same problem.
**How to avoid:** Apply fixes in this order: (1) guard window for deactivation observer, (2) then wrap `NSApp.activate` in `DispatchQueue.main.async`. The guard window fixes REL-01. The async activation fixes REL-02 (hang).

---

## Code Examples

### Complete Guard Window Implementation

```swift
// Source: Direct code analysis of StatusBarManager.swift
// Add to StatusBarManager stored properties (after panelShowLog, line 54):
private var panelShowedAt: Date = .distantPast
private var lastClickAt: Date = .distantPast

// Replace statusItemClicked() entirely:
@objc private func statusItemClicked() {
    // Debounce: ignore rapid-repeat clicks within 150ms
    let now = Date()
    guard now.timeIntervalSince(lastClickAt) > 0.15 else { return }
    lastClickAt = now

    guard let panel, let button = statusItem?.button else { return }
    let action = toggleState.toggle()
    switch action {
    case .hide:
        panel.orderOut(nil)
    case .show:
        positionPanel(relativeTo: button)
        os_signpost(.begin, log: panelShowLog, name: "PanelShow")
        panel.makeKeyAndOrderFront(nil)
        os_signpost(.end, log: panelShowLog, name: "PanelShow")
        panelShowedAt = Date()
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

// Replace deactivationObserver setup (around line 222):
deactivationObserver = NotificationCenter.default.addObserver(
    forName: NSApplication.didResignActiveNotification,
    object: nil, queue: .main
) { [weak self] _ in
    guard let self, self.toggleState.isShowing else { return }
    // Guard window: ignore deactivation arriving within 200ms of panel show.
    // NSApp.activate() triggers a deactivation/reactivation cycle that fires
    // this notification as a side-effect, not a real app switch.
    guard Date().timeIntervalSince(self.panelShowedAt) > 0.2 else { return }
    self.panel?.orderOut(nil)
}
```

### Diagnostic Logging (to be removed after fix)

```swift
// Source: Apple Unified Logging documentation
// Temporary — add during Wave 1 (diagnostics), remove in Wave 2 (fix)

// In deactivationObserver, before the guard:
os_log("dismiss path: deactivation at %.3fs after show",
       log: self.panelShowLog, type: .debug,
       Date().timeIntervalSince(self.panelShowedAt))

// In clickOutsideMonitor:
os_log("dismiss path: click-outside at %.3fs after show",
       log: self.panelShowLog, type: .debug,
       Date().timeIntervalSince(self.panelShowedAt))
```

### Testable State for Debounce and Guard Window

The `panelShowedAt` timestamp and `lastClickAt` timestamp can be exposed via an `internal` accessor (behind `#if DEBUG` or using Swift's `@_alwaysEmitIntoClient` — or simply `internal` on the property) to enable unit testing of the debounce and guard window logic independently of AppKit.

```swift
// Pure function for guard window logic — unit testable:
func shouldSuppressDeactivation(showedAt: Date, now: Date, guardInterval: TimeInterval = 0.2) -> Bool {
    return now.timeIntervalSince(showedAt) <= guardInterval
}

func shouldDebounceClick(lastClickAt: Date, now: Date, cooldown: TimeInterval = 0.15) -> Bool {
    return now.timeIntervalSince(lastClickAt) <= cooldown
}
```

These can be extracted as free functions or methods on a testable struct, enabling unit tests without AppKit.

---

## State of the Art

| Old Approach | Current Approach (Phase 12) | Phase 13 Change | Impact |
|--------------|----------------------------|-----------------|--------|
| `isPanelShowing` bool, 4 separate dismiss paths | `PanelToggleState` struct, single `onDismiss` callback | No change — still correct | Phase 13 builds on this |
| `deactivationObserver` fires unconditionally | `deactivationObserver` fires unconditionally | Add guard window timestamp check | Prevents spurious dismiss during activation |
| `statusItemClicked` no debounce | No debounce | Add 150ms debounce | Prevents double-click race |
| `NSApp.activate` synchronous (line 449) | Synchronous (still) | Wrap in `DispatchQueue.main.async` | Removes activation latency from click handler |

---

## Open Questions

1. **Is the guard window the only trigger for no-open?**
   - What we know: `didResignActiveNotification` firing during activation is the prime suspect (confirmed by LSUIElement behavior).
   - What's unclear: Whether `clickOutsideMonitor` also fires during activation (a global `leftMouseDown` event may arrive when the status bar button click is processed).
   - Recommendation: Add os_log to **all** dismiss paths during the diagnostic wave to confirm which path fires. If `clickOutsideMonitor` also fires spuriously, apply the same guard window pattern to it.

2. **What causes the click-outside monitor to fire during icon click?**
   - What we know: `addGlobalMonitorForEvents` captures events from other apps — it should not capture events from the status bar button itself.
   - What's unclear: Whether the system delivers the status bar click as a global mouse event before or after `statusItemClicked()` is called.
   - Recommendation: The diagnostic logging in the click-outside path will confirm this. If it fires within the guard window, add the same timestamp guard to that observer.

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Swift Testing (`@Test`, `#expect`) — requires Xcode |
| Config file | `Package.swift` (AIBatteryCoreTests target) |
| Quick run command | `swift test --filter AIBatteryCoreTests` |
| Full suite command | `swift test` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| REL-01 | Guard window suppresses deactivation within 200ms of show | unit | `swift test --filter ReliabilityGuardTests` | ❌ Wave 0 |
| REL-01 | Debounce ignores clicks within 150ms of prior click | unit | `swift test --filter ReliabilityGuardTests` | ❌ Wave 0 |
| REL-01 | Deactivation outside guard window still dismisses panel | unit | `swift test --filter ReliabilityGuardTests` | ❌ Wave 0 |
| REL-01 | Rapid open/close cycles complete without stuck state | manual | Stress test: click icon 20x rapidly | N/A |
| REL-02 | No main-thread hang during panel interaction | manual | Profile with Instruments; verify `NSApp.activate` is async | N/A |

Note: REL-02 is primarily verified via Instruments profiling. The automatable surface is confirming that `NSApp.activate` is called inside `DispatchQueue.main.async` (code review level) and via signpost timing.

### Sampling Rate
- **Per task commit:** `swift test --filter AIBatteryCoreTests`
- **Per wave merge:** `swift test`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `Tests/AIBatteryCoreTests/Views/ReliabilityGuardTests.swift` — pure function tests for `shouldSuppressDeactivation` and `shouldDebounceClick` covering guard window and debounce logic

*(Existing test infrastructure fully covers Phase 12 work. Only the new guard/debounce logic needs a new test file.)*

---

## Sources

### Primary (HIGH confidence)
- Project source code — `AIBattery/Views/StatusBarManager.swift` — direct inspection of all race condition paths
- Phase 12 summaries (12-01-SUMMARY.md, 12-02-SUMMARY.md) — confirmed what was built and what remains
- CONTEXT.md (13-CONTEXT.md) — locked decisions from user discussion

### Secondary (MEDIUM confidence)
- Apple AppKit documentation — `NSApplication.didResignActiveNotification`, `NSApp.activate(ignoringOtherApps:)`, LSUIElement app activation behavior
- Project MEMORY.md — v1.12 responsiveness decisions and known constraints

### Tertiary (LOW confidence)
- None — all findings sourced from direct code inspection and known Apple framework behavior

---

## Metadata

**Confidence breakdown:**
- Root cause identification: HIGH — direct code inspection confirms the guard window is missing from the deactivation observer; activation sequence in LSUIElement apps is well-known to trigger spurious deactivation notifications
- Fix pattern: HIGH — guard window timestamp is a standard pattern for this class of activation race
- Timing values (200ms guard, 150ms debounce): MEDIUM — correct order of magnitude, may need tuning based on manual testing results
- Whether click-outside monitor also needs guarding: MEDIUM — requires diagnostic log confirmation during implementation

**Research date:** 2026-03-20
**Valid until:** 2026-04-20 (stable frameworks)

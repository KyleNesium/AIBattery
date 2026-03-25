# Phase 12: Responsiveness - Research

**Researched:** 2026-03-20
**Domain:** SwiftUI/AppKit macOS menu bar panel performance, main-thread responsiveness, lazy rendering
**Confidence:** HIGH

## Summary

Phase 12 is a focused responsiveness pass on an existing, working macOS menu bar app. The app uses a custom `NSPanel` (not `NSPopover` or `MenuBarExtra`) with an `NSHostingView` rendering SwiftUI content. Prior work (v1.9.2, v1.9.4) already eliminated several major performance issues: removed `NSApp.activate` blocking, removed `Timer.publish` on SwiftUI structs, removed `.transition(.opacity)` inside `TimelineView`, and removed `contentTransition(.numericText())` from infrequently-updating values.

Despite these fixes, the user reports an intermittent hang still occurs. The requirements call for: sub-50ms open/close (RESP-01), zero UI freezes (RESP-02), no desync of the toggle boolean (RESP-03), and lazy rendering of off-screen content (RESP-04).

The core work is: (1) profiling and eliminating any remaining main-thread blocking work on panel show/hide, (2) ensuring `isPanelShowing` boolean stays consistent with actual panel state across all dismiss paths, (3) wrapping the `InsightsView` chart section in a deferred/lazy container so it does not render on open, and (4) identifying what work fires synchronously when `makeKeyAndOrderFront` is called.

**Primary recommendation:** Profile with Instruments (Time Profiler + SwiftUI view body trace) on open/close, fix the desync risk in the existing dismiss code, and gate `InsightsView` behind a `@State var panelHasAppeared` flag to defer chart rendering until after the panel is on-screen.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| RESP-01 | Popover opens/closes in under 50ms — no perceptible delay on any click | Panel show path is synchronous AppKit (`makeKeyAndOrderFront` + `setFrameOrigin`) — must ensure no SwiftUI work fires before the frame is on-screen; `NSApp.activate` is already async after show |
| RESP-02 | No UI freeze or hang during normal usage (open, scroll, toggle, close) | `InsightsView` computes chart data transforms on body evaluation; if data is stale it recomputes during the render triggered by show — this is the most likely source of intermittent hangs |
| RESP-03 | Panel toggle never desyncs (click always produces correct open/close) | `isPanelShowing` is set to `false` in 4 separate dismissal paths (click, Escape, click-outside, deactivation); a race or missed path causes desync |
| RESP-04 | Lazy-load heavy sections — only render visible content on open | `InsightsView`, `ProjectUsageSection` with sort/search state, and `TokenHealthSection` all initialize state on first body call; must defer until panel is visible |
</phase_requirements>

## Standard Stack

No new dependencies required. All solutions use existing Apple frameworks.

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| SwiftUI | macOS 13+ built-in | View rendering | Already in use |
| AppKit | macOS 13+ built-in | `NSPanel`, `NSStatusItem` | Already in use |
| Instruments | Xcode built-in | Time Profiler, SwiftUI profiling | Required for root cause analysis |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `os.signpost` | macOS built-in | Mark begin/end of show/hide path | When adding targeted measurements |
| `DispatchWorkItem` | Foundation | Debounce (already used in resize observer) | Existing pattern |

**Installation:** No new packages needed.

## Architecture Patterns

### Current Panel Show/Hide Path

```
statusItemClicked()
  └─ positionPanel(relativeTo: button)    // sync: frame calculation
       ├─ button.convert + window.convertToScreen
       └─ panel.setFrameOrigin             // sync: moves the window
  └─ panel.makeKeyAndOrderFront(nil)       // sync: orders panel on-screen
  └─ isPanelShowing = true
  └─ NSApp.activate(ignoringOtherApps: true)  // async-ish: already deferred
```

SwiftUI render of `PopoverContentView` fires during `makeKeyAndOrderFront`. The heavier the view hierarchy, the longer this blocks. Instruments will show this as time on the main thread inside `NSPanel.makeKeyAndOrderFront`.

### Pattern 1: Deferred Section Rendering (RESP-04)

**What:** Gate expensive sections behind a `@State var hasAppeared = false` flag that flips in `.onAppear`. Sections that are collapsed by default only render their header; the body renders only when explicitly expanded AND after the panel has appeared.

**When to use:** For any section whose body involves O(n) computation on render (`InsightsView` with chart transforms, `ProjectUsageSection` with sort computation).

**Example:**
```swift
// In UsagePopoverView or a wrapping Gate view
@State private var panelHasAppeared = false

// Replace InsightsGate body instantiation:
if panelHasAppeared {
    InsightsView(...)
} else {
    // Placeholder matching approximate height to avoid layout jump
    Color.clear.frame(height: 0)
}

// At some point after show:
.onAppear { panelHasAppeared = true }
```

Note: `onAppear` fires synchronously during the initial render pass, so this does NOT help with open latency unless the view is hidden via `if false` rather than `.hidden()`. An `if`-branch tells SwiftUI not to instantiate the view at all; `.hidden()` still renders.

**Better pattern for open latency:** Use `.task { panelHasAppeared = true }` (defers to the next run-loop iteration after the frame is visible) or a `DispatchQueue.main.async` call from `onAppear`.

```swift
.onAppear {
    DispatchQueue.main.async {
        panelHasAppeared = true
    }
}
```

This lets the panel show the lightweight header+bars first, then renders the chart section one frame later — invisible to the user but eliminates blocking the `makeKeyAndOrderFront` call.

### Pattern 2: isPanelShowing Desync Prevention (RESP-03)

The toggle boolean `isPanelShowing` is set to `false` in four paths:

1. `statusItemClicked()` — on second click
2. `escapeMonitor` — local key event
3. `clickOutsideMonitor` — global mouse event
4. `deactivationObserver` — `NSApplication.didResignActiveNotification`

The panel can also be ordered out by macOS itself (e.g., window server hides it). If this happens without one of the four observers firing, `isPanelShowing` stays `true` and the next click becomes a "close" call on an already-hidden panel — the toggle is stuck until the second click after that.

**Prevention:** Override `orderOut` in `PopoverPanel` to call a weak delegate/callback, or observe `NSWindow.didResignKeyNotification` + `NSWindow.willCloseNotification` on the panel itself. Any path that removes the panel from the screen should sync `isPanelShowing = false`.

```swift
// In PopoverPanel subclass (already exists):
// Add override or notification

// In StatusBarManager.setup:
NotificationCenter.default.addObserver(
    forName: NSWindow.willCloseNotification,
    object: panel,
    queue: .main
) { [weak self] _ in
    self?.isPanelShowing = false
}
```

Note: `orderOut` does not close the window (it is not removed from memory), so `willCloseNotification` is not the right event. The correct signal is `NSWindow.didResignKeyNotification` or a custom `PopoverPanel` override of `orderOut(_:)`.

```swift
// PopoverPanel override:
override func orderOut(_ sender: Any?) {
    super.orderOut(sender)
    onDismiss?()  // weak callback to StatusBarManager
}
```

### Pattern 3: Instruments Profiling for RESP-01/02

Before writing any code, run Instruments to identify where time is actually spent. The intermittent hang may be in a specific code path that is not obvious from inspection.

**Setup:**
1. Build in release mode: `swift build -c release`
2. Or attach to debug build with: Product > Profile in Xcode
3. Time Profiler template: measures CPU time per thread
4. SwiftUI instrument (Xcode 14+): shows view body recomputation counts and durations

**Key measurements to capture:**
- Time from `statusItemClicked()` entry to `makeKeyAndOrderFront` return
- Whether the hang correlates with `InsightsView.body` re-evaluation
- Whether `SessionLogReader` or `UsageAggregator` fires during panel show (should not — they are on a background timer)

### Anti-Patterns to Avoid

- **`GeometryReader` in scrollable content:** Already removed for `GaugeBar` (v1.9.4). Do not reintroduce. `GaugeBar` now uses a single `GeometryReader` at the leaf level — do not move it higher.
- **`.animation()` on the root VStack:** Fixed in v1.9.2. Scoping `.animation` to ForEach only is the correct pattern.
- **`Timer.publish` on SwiftUI structs:** Causes timer accumulation across re-renders. Already removed. Do not reintroduce. Use `TimelineView` or a class-based owner.
- **`withAnimation(.repeatForever)` in data path:** Leaks a global repeating animation transaction that affects all sibling views. Already removed in v1.9.2.
- **Calling `panel.isVisible` for toggle logic:** This was tried in v1.9.4 and reverted — it made toggle WORSE. `isPanelShowing` is the correct approach.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Toggle desync detection | Custom state machine | Observe `NSWindow` notifications + `PopoverPanel.orderOut` override | Window server already tracks state; mirroring it is error-prone |
| Lazy rendering | Custom visibility tracking | SwiftUI `if`-branch with deferred `@State` flag | SwiftUI only instantiates views inside true `if`-branches; `.hidden()` still renders |
| Performance profiling | Custom timers/logging | Instruments Time Profiler + os.signpost | Instruments shows actual CPU time and call stacks |

**Key insight:** The two hardest parts (lazy rendering and desync) are solved by well-understood AppKit/SwiftUI patterns — not custom infrastructure.

## Common Pitfalls

### Pitfall 1: Using `.onAppear` for Launch Deferral Without Async Hop

**What goes wrong:** Setting `panelHasAppeared = true` synchronously in `.onAppear` causes SwiftUI to re-render the view in the same pass — still blocking `makeKeyAndOrderFront`.
**Why it happens:** `.onAppear` is called during the view update cycle triggered by `makeKeyAndOrderFront`, before the window is actually composited.
**How to avoid:** Wrap the state mutation in `DispatchQueue.main.async { }` or `.task { panelHasAppeared = true }` to defer to the next run-loop iteration.
**Warning signs:** The panel still feels slow to appear even after adding the deferred flag.

### Pitfall 2: Fixing isPanelShowing Without Covering the orderOut Path

**What goes wrong:** Adding a `willCloseNotification` observer doesn't help because `orderOut` does not close the window.
**Why it happens:** `NSWindow.orderOut(_:)` hides the window without closing it. `willClose`/`didClose` notifications only fire on `performClose` or `close`.
**How to avoid:** Override `orderOut` in `PopoverPanel` and call a callback, or observe `NSWindow.didResignKeyNotification` combined with a visibility check (`!panel.isVisible`).
**Warning signs:** `isPanelShowing` stays `true` after clicking another app's window.

### Pitfall 3: Deferred Rendering Causes Layout Jump

**What goes wrong:** Swapping `Color.clear.frame(height: 0)` for `InsightsView` causes the panel to resize visibly — the resize debounce triggers a frame change from tall to short then tall again.
**Why it happens:** The resize observer watches `hostingView.fittingSize` and adjusts panel height. If the deferred section goes from height=0 to full height, the observer fires.
**How to avoid:** Either use a fixed placeholder with approximate height, or simply render the section immediately but defer the expensive chart data computation inside it using a separate `@State var chartDataReady = false` flag with an async hop in `onAppear`.
**Warning signs:** Panel visibly "jumps" in size after 1 frame.

### Pitfall 4: Ignoring the "Intermittent" Qualifier

**What goes wrong:** Optimizing the normal path doesn't fix the intermittent hang because the hang is caused by an edge-case trigger.
**Why it happens:** The STATE.md note says "User reports intermittent hang still occurs despite v1.12 fixes — root cause not yet identified." This implies a conditional code path. Likely candidates: (a) `InsightsView` only hangs when `dailyActivity` array is large, (b) hang only on first open after data refresh (cache miss in chart data fingerprinting).
**How to avoid:** Profile the hang specifically, not the fast path. Use `os_signpost` or Instruments to capture the slow case.
**Warning signs:** Fix works in testing but user still reports occasional hang.

## Code Examples

### Deferred Section with Async Hop

```swift
// Source: Apple SwiftUI documentation — view update lifecycle
// In UsagePopoverView (or InsightsGate):

@State private var panelHasAppeared = false

// In body:
if panelHasAppeared {
    InsightsGate(snapshot: snapshot)
} else {
    // No-height placeholder — does not trigger resize observer
    EmptyView()
}

// On parent VStack or root view:
.onAppear {
    DispatchQueue.main.async {
        panelHasAppeared = true
    }
}
.onDisappear {
    panelHasAppeared = false  // Reset for next open
}
```

### PopoverPanel orderOut Override for Desync Fix

```swift
// Source: AppKit NSPanel documentation
// In PopoverPanel (already a private class in StatusBarManager.swift):

var onDismiss: (() -> Void)?

override func orderOut(_ sender: Any?) {
    super.orderOut(sender)
    onDismiss?()
}
```

```swift
// In StatusBarManager.setup(), after creating panel:
panel.onDismiss = { [weak self] in
    self?.isPanelShowing = false
}
```

This ensures ALL dismiss paths (AppKit internal, Escape key override in PopoverPanel, manual `orderOut` calls) set `isPanelShowing = false`.

Note: The existing Escape key handler in `PopoverPanel.keyDown` calls `orderOut(nil)` — with this pattern, `isPanelShowing` will be set to `false` from both the `escapeMonitor` local event monitor AND the `onDismiss` callback. This is fine — setting a bool to `false` twice is idempotent.

### os_signpost for Profiling Panel Show

```swift
// Source: Apple Unified Logging documentation
import os.signpost

private let showLog = OSLog(subsystem: "com.kylenesium.AIBattery", category: .pointsOfInterest)

// In statusItemClicked():
os_signpost(.begin, log: showLog, name: "PanelShow")
panel.makeKeyAndOrderFront(nil)
os_signpost(.end, log: showLog, name: "PanelShow")
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `NSApp.activate` before `makeKeyAndOrderFront` | `NSApp.activate` after (non-blocking) | v1.9.4 | Removed ~200ms delay |
| `Timer.publish` on SwiftUI struct | `TimelineView` for periodic updates | v1.9.4 | Eliminated timer accumulation freeze |
| `.transition(.opacity)` inside `TimelineView` | Removed | v1.9.4 | Eliminated main-thread animation block on 10s ticks |
| `panel.isVisible` for toggle | `isPanelShowing` boolean | v1.9.4 | `isVisible` toggle made things WORSE — reverted |
| Frame resize observer fires always | Gated on `isPanelShowing` | v1.9.4 | Stops resize feedback loop when panel hidden |

**Still pending:**
- Lazy rendering of `InsightsView` (chart transforms fire on every panel open)
- Full coverage of `isPanelShowing = false` paths (no `onDismiss` override in `PopoverPanel`)

## Open Questions

1. **Root cause of intermittent hang**
   - What we know: Hang persists after v1.9.4 fixes. User reports it's intermittent, not every open.
   - What's unclear: Whether it correlates with data volume (many JSONL files), first open after data change, or specific section expansion.
   - Recommendation: Add `os_signpost` markers in `statusItemClicked` and `InsightsView.body` entry, then use Instruments to capture the slow case before writing any fixes.

2. **Whether onDisappear/panelHasAppeared causes layout jump**
   - What we know: Resize observer fires on `hostingView.fittingSize` changes; currently debounced 16ms and gated on `isPanelShowing`.
   - What's unclear: Whether removing InsightsView from hierarchy causes a height change large enough to trigger the observer.
   - Recommendation: Implement the deferred flag with `EmptyView()` placeholder first, then test for visible height jump. If jump occurs, defer chart data initialization inside InsightsView instead of removing the view from hierarchy.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Swift Testing (`@Test`, `#expect`) — requires Xcode |
| Config file | Package.swift (AIBatteryCoreTests target) |
| Quick run command | `swift test --filter AIBatteryCoreTests` |
| Full suite command | `swift test` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| RESP-01 | Panel show path has no blocking sync work added | manual | Profile with Instruments | N/A |
| RESP-02 | No main-thread hang during open/scroll/close | manual | Profile with Instruments + regression test for deferred flag | N/A |
| RESP-03 | `isPanelShowing` stays consistent after all dismiss paths | unit | `swift test --filter StatusBarManagerTests` | ❌ Wave 0 |
| RESP-04 | `InsightsView` not rendered on panel open (deferred) | unit | `swift test --filter UsagePopoverViewTests` | ❌ Wave 0 |

Note: RESP-01 and RESP-02 require runtime profiling (Instruments) and are not fully automatable. The automatable surface is: unit tests verifying the deferred-render flag logic and the `isPanelShowing` consistency. These are observable via testable state on the view model and logic, not full UI tests.

### Sampling Rate
- **Per task commit:** `swift test --filter AIBatteryCoreTests`
- **Per wave merge:** `swift test`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `Tests/AIBatteryCoreTests/Views/StatusBarToggleTests.swift` — covers RESP-03: test that all dismiss paths (orderOut override, escape, click-outside, deactivation) set `isPanelShowing = false`
- [ ] `Tests/AIBatteryCoreTests/Views/DeferredRenderingTests.swift` — covers RESP-04: test that deferred flag starts false, flips true after async hop, resets to false on disappear

*(Both gaps require testable extraction of the toggle logic from `StatusBarManager` — the pure boolean state machine can be extracted into a testable struct or made accessible via an internal accessor.)*

## Sources

### Primary (HIGH confidence)
- Apple AppKit `NSWindow` / `NSPanel` documentation — `orderOut`, `makeKeyAndOrderFront`, notification names
- Apple SwiftUI documentation — view update lifecycle, `onAppear`, task modifier
- Project source code (StatusBarManager.swift, UsagePopoverView.swift, ActivityChartView.swift) — direct inspection

### Secondary (MEDIUM confidence)
- CHANGELOG.md entries for v1.9.2, v1.9.4 — documents what was already tried and why
- STATE.md `Accumulated Context / Decisions` — locked decisions from prior debugging

### Tertiary (LOW confidence)
- None

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — no new dependencies; all patterns are native AppKit/SwiftUI
- Architecture: HIGH — direct code inspection of all relevant files
- Pitfalls: HIGH — most are confirmed by prior CHANGELOG fixes or the known revert (panel.isVisible)
- Root cause of intermittent hang: LOW — not yet identified; Instruments profiling required

**Research date:** 2026-03-20
**Valid until:** 2026-04-20 (stable frameworks, 30-day window)

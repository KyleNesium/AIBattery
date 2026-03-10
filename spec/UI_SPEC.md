# UI Specification

## Popover Layout

275pt wide, VStack layout with fixed header + metric toggle + ordered content sections + fixed footer. No ScrollView (MenuBarExtra `.window` style handles overflow).

## ASCII Mockup

```
┌──────────────────────────────────────┐
│ ✦ AI Battery  Account ▾   v⚙   │  ← ❶ Header
├──────────────────────────────────────┤
│ [Settings panel — collapsible]       │  ← ❶b Settings
│  Active: [________]                 │     (gear toggle)
│  Account: [________] (×)            │
│  + Add Account                      │
│  Refresh: [slider 10-60s]           │
│  Idle: [slider 30m-8h-∞]           │
│  Alerts: ☐ Claude.ai ☐ Claude Code │
├──────────────────────────────────────┤
│ (A) [5 Hour|7 Day|Context]             │  ← Metric toggle + auto
│                                        │
├──────────────────────────────────────┤
│ 5-Hour                         12%  │
│ [████████████░░░░░░░░░░░] binding   │  ← ❷ Rate Limits
│ 88% remaining      Resets in 4h 32m │     (5h + 7d)
│                                      │
│ 7-Day                           3%  │
│ [██░░░░░░░░░░░░░░░░░░░░░]          │
│ 97% remaining      Resets in 6d 2h  │
├──────────────────────────────────────┤
│ Context Health    < 1/5 > ⟳ ● 60%  │  ← ❸ Context
│ Code · main · 4h 45m · Today 14:32   │     health
│ [██████████████░░░░░░░░]             │   (multi-session)
│ ~64K of 160K usable                  │
│ 358 turns · Opus 4.6                 │
├──────────────────────────────────────┤
│ Tokens                       18.9M   │  ← ❹ Tokens
│   ⚡ Opus 4.6  ▶ Active  12.3M      │   (per-model)
│      ↑ 5K  ↓ 29K  📄 17.6M  ✎ 1.4M │
│   ⚡ Sonnet 4.5           6.6M      │
│      ↑ 2K  ↓ 15K  📄 4.3M   ✎ 300K │
├──────────────────────────────────────┤
│ Activity      [12H] [7D] [12M]      │  ← ❺ Chart
│ ~~~ area chart ~~~                   │
│ HH  HH  HH  HH  HH (trailing 12h)  │
├──────────────────────────────────────┤
│ Today   42 msgs · 3 sessions · 128  │  ← ❻ Insights
│ All Time  1,247 msgs · 89 sessions  │
├──────────────────────────────────────┤
│ 📊Usage↗  ●Status↗   Logout  Quit │  ← ❼ Footer
└──────────────────────────────────────┘
```

## View Hierarchy

```
UsagePopoverView (275px, VStack)
  @ObservedObject viewModel: UsageViewModel
  @ObservedObject accountStore: AccountStore (drives account picker reactivity)
  @AppStorage: metricModeRaw, autoMetricMode (only 2 — other toggles pushed to child views)
├── headerSection
├── Divider
├── SettingsRow (if showSettings — toggled by gear icon)
│   ├── Account name rows (depend on accountStore — stay in parent)
│   ├── RefreshSettingsSection — owns refreshInterval
│   ├── DisplaySettingsSection — owns idleSessionMinutes, colorblindMode, showCostEstimate
│   ├── AlertSettingsSection — owns alertStatus, alertRateLimit, rateLimitThreshold
│   └── LaunchAtLoginSection — owns launchAtLogin
├── Divider
├── metricToggle (auto "A" circle button left + segmented picker: 5h | 7d | Ctx)
│   (auto mode highlights selected segment via read-only binding)
├── Divider
├── ForEach(orderedModes) ← selected metric first, then others
│   ├── FiveHourBarSection / SevenDayBarSection (if rateLimits)
│   └── TokenHealthSection — collapsible (if topSessionHealths or tokenHealth)
│   └── .animation(.easeInOut(duration: 0.15), value: metricModeRaw) ← scoped to ForEach only
├── TokenUsageGate (data check, TokenUsageSection owns collapsed @AppStorage)
├── ActivityChartGate (data check, ActivityChartView owns collapsed @AppStorage)
├── InsightsSection (Today + All Time stats)
├── Divider
├── footerSection
└── .overlay { TutorialOverlay(hasData:) } — self-managing visibility via own @AppStorage
```

Conditional states (mutually exclusive with content): Loading | Error | Empty

## Section Specs

### ❶ Header (`UsagePopoverView.headerSection`)

- Title: `"✦ AI Battery"` (.headline)
- **Account picker**: always-visible dropdown Menu next to title
  - Label: display name if set, otherwise `"Account N"` for multi-account / `"Account"` for single (.caption, .secondary)
  - Menu items: display name or `"Account N"` with checkmark on active, clicking switches via `viewModel.switchAccount(to:)`
  - "Add Account" item (plus.circle icon) below divider when `canAddAccount` (< max) — triggers AuthView overlay
  - `.menuStyle(.borderlessButton)`, `.fixedSize()`
- Gear button: `gearshape`, 11pt, toggles Settings panel
- Loading spinner: ProgressView at 0.6 scale
- **Update button** (`arrow.up.circle`, 11pt): three color states, no banner
  - **Update available** (`viewModel.availableUpdate` exists): button turns `.yellow`, stays yellow. Clicking re-shows the update banner (if dismissed). `.help("vX.Y.Z available")`.
  - **Up to date** (`updateCheckMessage` set, no update): button turns `.green` for 2.5s, fades back to `.secondary`.
  - **Default**: `.secondary` color. Clicking triggers `forceCheckForUpdate()`.
- **Update banner** (below header, when `availableUpdate` exists and not dismissed): bordered card, single-row HStack
  - Background: `RoundedRectangle(cornerRadius: 6)` with `Color.yellow.opacity(0.08)` fill and `Color.yellow.opacity(0.25)` 1pt stroke, 8pt padding
  - Yellow circle icon + **"vX.Y.Z ↗"** (.caption2, .secondary) — clickable, opens GitHub release page
  - **"↓ Install Update"** (.caption2, .blue) — tries Sparkle in-app update; falls back to opening GitHub release if Sparkle not ready
  - **"✕"** dismiss button (xmark.circle.fill, 14pt, .secondary) — hides banner, yellow icon stays yellow; clicking icon re-shows banner
  - State: `@State updateBannerDismissed` (resets when yellow icon clicked)
- Padding: H 16, V 8

### ❶b Settings (`SettingsRow` — private struct, decomposed into sub-views)

Collapsible panel toggled by gear icon. Decomposed into sub-views so each `@AppStorage` toggle only redraws its own section.

**Parent `SettingsRow`**: holds `viewModel`, `accountStore`, `onAddAccount` closure. Contains account name rows (depend on `accountStore`) and delegates sections to child views. Uses `ForEach(accounts)` with index derived inside loop body.

**`RefreshSettingsSection`** (owns `refreshInterval`):
- **Refresh**: Slider (10–60s, step 5) → `aibattery_refreshInterval`
  - Calls `viewModel.updatePollingInterval()` on change
  - Hint: `"~3 tokens per poll"` (.caption2, .tertiary)

**`DisplaySettingsSection`** (owns `idleSessionMinutes`, `colorblindMode`, `showCostEstimate`):
- **Idle**: Slider (1–6, step 1) → `aibattery_idleSessionMinutes` (30/60/120/240/480 minutes, 0 = Never)
  - Display: `"30m"`, `"1h"`, `"2h"`, `"4h"`, `"8h"`, or `"∞"` (Never)
  - Slider positions: 30m, 1h, 2h, 4h, 8h, ∞ (left to right)
  - Hint: `"Hide idle sessions from context health"` (.caption2, .tertiary)
- **Display**: Checkboxes
  - "Colorblind" → `aibattery_colorblindMode`; "Cost" → `aibattery_showCostEstimate`

**`AlertSettingsSection`** (owns `alertStatus`, `alertRateLimit`, `rateLimitThreshold`):
- **Alerts row**: "Status" checkbox + "Rate Limit" checkbox + "Test" button (when Status enabled)
  - Status: notifies on any of the 5 tracked status page components
  - Rate Limit: threshold slider (50–95%, step 5, default 80%) appears below when enabled

**`LaunchAtLoginSection`** (owns `launchAtLogin`):
- **Startup**: "Launch at Login" checkbox → `aibattery_launchAtLogin`
  - Syncs with `SMAppService.mainApp.status` on appear

**`sliderMarks()`**: `fileprivate` file-level helper for generating slider tick marks (shared by sections).

**Animations**:
- Settings toggle: `withAnimation(.easeInOut(duration: 0.2))` + `.transition(.opacity.combined(with: .move(edge: .top)))`
- Metric mode changes: `.animation(.easeInOut(duration: 0.15), value: metricModeRaw)` — scoped to ForEach block only, not entire VStack
- Account switch: `withAnimation(.easeInOut(duration: 0.2))`

Values propagate to header + menu bar immediately via `@AppStorage` (settings) and `@Published` (account names).

Padding: H 16, V 8

### Collapsible Sections

Context Health, Tokens, and Activity sections have collapsible headers. Each section header is a button with a rotating chevron (`chevron.right`, 8pt bold). Collapsed state persists via `@AppStorage` per section (`contextCollapsed`, `tokensCollapsed`, `activityCollapsed`). When collapsed, only the header row shows (with summary value on the right). Collapse/expand animates with `.easeInOut(duration: 0.2)`.

### Gate Views (`TokenUsageGate`, `ActivityChartGate`)

Gate views check data availability and render the section + divider. Sections own their own collapsed `@AppStorage`.

- **`TokenUsageGate`**: renders `TokenUsageSection` + `Divider` when `snapshot.totalTokens > 0`.
- **`ActivityChartGate`**: renders `ActivityChartView` + `Divider` when activity data is available.

### Metric Toggle (`UsagePopoverView.metricToggle`)

HStack layout: auto mode button (left) + Spacer + segmented picker (190pt, centered) + Spacer.

**Segmented picker**: 3 segments using `MetricMode.shortLabel` — `"5 Hour"`, `"7 Day"`, `"Context"`. Auto mode syncs picker selection to the auto-resolved mode via a read-only binding.

**Auto mode button** ("A"): 20pt circle, `.system(size: 9, weight: .heavy, design: .rounded)`.
- **Active**: blue text, `Color.blue.opacity(0.15)` fill, 1.5pt blue stroke with pulsing opacity (0.3–0.8), pulsing blue shadow (radius 1–5pt, opacity 0.1–0.5). Pulse via scoped `.animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: autoGlowing)` on stroke/shadow views only (never `withAnimation` — leaks global repeating transaction).
- **Inactive**: `.secondary.opacity(0.5)` text, no fill, `.secondary.opacity(0.2)` stroke, no shadow.
- Picker dims to 0.4 opacity and is disabled when auto mode is active.
- **Auto highlight**: when auto mode is active, the picker selection syncs to the auto-resolved mode via a read-only binding, visually highlighting which segment was chosen. The picker is dimmed (0.55 opacity) and disabled.
- **Behavior**: auto mode uses three-tier priority via `snapshot.autoResolvedMode`: throttled → always rate limit window; near-exhaustion (≥95%) → rate limit unconditionally beats context health; **Tier 3** — urgency-normalized comparison via `urgencyScore(percent:mode:)` with piecewise-linear interpolation (see CONSTANTS.md for anchor points); highest urgency wins, context breaks ties. Applied in both popover and menu bar label.

Padding: H 16, V 8

### Gate Views (`TokenUsageGate`, `ActivityChartGate`)

Gate views check data availability and render the section + divider. Sections own their own collapsed `@AppStorage`.

- **`TokenUsageGate`**: renders `TokenUsageSection` + `Divider` when `snapshot.totalTokens > 0`.
- **`ActivityChartGate`**: renders `ActivityChartView` + `Divider` when activity data is available.

### MarqueeText (`Views/MarqueeText.swift`)

News-ticker style scrolling text view. Supports single or multiple texts.

- **Single text**: if text fits container, displays statically. If wider, scrolls left then right (bouncing) at 30pt/s with 2s pause at each end.
- **Multiple texts**: scrolls current text left (if needed), then cross-fades (0.3s out → swap → 0.3s in) to the next text. Non-scrolling texts hold for 3s before advancing. Cycles endlessly.
- Container: `GeometryReader` + `.clipped()`, 14pt height.
- Text measured via background `GeometryReader`, re-measured on index change via `.id(currentIndex)` and on geometry width change via `.onChange(of:)`.

### ❷ Rate Limit Bars (`Views/UsageBarsSection.swift`)

`FiveHourBarSection` + `SevenDayBarSection`, each wrapping a shared `UsageBar` view.

Each bar:
- **Label row**: label (.subheadline.bold()) + `"binding"` badge if active constraint (.system 9pt, monospaced, .tertiary, rounded background) + throttle warning icon + percentage (.title3, monospaced, semibold)
- **Progress bar**: 8pt height, 3pt corner radius. Background: primary 0.1 opacity. Fill: color by percent.
- **Detail row**: left status + reset countdown on right
  - Normal: `"X% remaining"` (.caption2, secondaryLabel) + `"Resets in Xh Ym"` (.caption2, .tertiary)
  - Predictive: `"~Xh Ym to limit"` (.caption2, .caution) when `estimatedTimeToLimit` available (utilization > 50%, estimate before reset)
  - Throttled: `"Rate limited"` (.caption2, .danger) — shown when per-window status is `"throttled"` OR overall `isThrottled` and window is at 100%
  - **Reset expired, API still shows usage** (percent ≥ 1): `"Resets soon"` (.caption2, .caution) — waiting for API confirmation
  - **Reset confirmed** (expired + percent < 1): sparkles icon + `"Reset"` (.caption2, .green) — celebration state

Reset time format: `>24h` → "in Xd Yh", `1-24h` → "in Xh Ym", `1-59m` → "in Xm", `<60s` → "in Xs" (seconds countdown), expired → "soon" or green "Reset"

Padding: H 16, V 8

### ❸ Context Health (`Views/TokenHealthSection.swift`)

Takes `sessions: [TokenHealthStatus]` array (top 5 by highest context usage). Backward-compat `init(health:onRefresh:)` for single session.

- **Header row**: `"Context Health"` (.subheadline.bold) + session toggle + refresh + health badge
- **Session info** (two lines below header, .caption2, .tertiary):
  - Line 1: `projectName · gitBranch · sessionId[:8]` — project, branch, and 8-char session ID prefix (`.copyable()`) for cross-referencing
  - Line 2: `duration · lastActivity · velocity` — e.g. "2h 15m · Today 14:32 · 1.2K/min"
  - Falls back to `"Latest session"` if no metadata on line 1
- **Session toggle** (if multiple sessions): `< 1/3 >` `ChevronButton` components
  - `@State selectedIndex` tracks current session (position 1 = highest context usage)
  - `ChevronButton`: 22pt square hit target, `chevron.left`/`chevron.right` icons at 9pt bold, 4pt corner radius background with press highlight (`Color.primary.opacity(0.1)`), `.plain` button style. Disabled state uses 0.15 opacity; enabled uses 0.6 opacity.
  - Left/right chevrons with `.easeInOut(0.15)` animation
  - Counter: monospaced caption2, e.g. `"1/3"`
- **Swipe gesture**: `DragGesture(minimumDistance: 20)` on main VStack — horizontal drag >50pt or fast flick (velocity >300pt/s) navigates prev/next session (same animation as chevron buttons)
- **VoiceOver**: `.accessibilityAdjustableAction` on section — increment/decrement maps to next/previous session
- **Stale session badge** (if lastActivity > 30 min and band != .green): amber dot (6pt) + `"Idle Xm"` (.caption2, .orange)
- **Expanded tooltip**: `.help()` on session info label with full details — session ID, model, context window, all timestamps, all token counts, warnings
- **Refresh button**: `arrow.clockwise` 10pt, .secondary
- **Health badge**: 8pt colored circle + percentage in monospaced subheadline semibold
- **Gauge bar**: same style as usage bars (8pt, 3pt radius), width proportional to usagePercentage
- **Detail row**: `"~{remaining} of {usableWindow} usable"` (.caption, ThemeColors.secondaryLabel) + `"{turnCount} turns · {modelName}"` (.caption2, ThemeColors.tertiaryLabel)
  - Percentage and remaining are relative to usable window (80% of raw context window)
  - 100% = Claude Code is about to auto-compact
- **Safe minimum hint** (orange/red only): `"(keep above ~{20% of usable} for best quality)"` (.caption2, .tertiary)
- **Warnings**: triangle icon + message. Strong = filled triangle, red. Mild = outline triangle, orange.
- **Suggested action**: (.caption2, red or orange based on band)

Padding: H 16, V 12

### ❹ Tokens (`Views/TokenUsageSection.swift`)

- Header: `"Tokens"` (.subheadline.bold) + total (.subheadline, monospaced, semibold)
- Per-model breakdown via `ForEach` over sorted models (active first via prefix matching, then by totalTokens descending)
- Model icons: SF Symbols cycle (`cpu`, `bolt`, `sparkles`, `cube`, `wand.and.stars`) at 10pt, ThemeColors.secondaryLabel, 14pt frame
- Per model row: icon + display name (.caption) + `"▶"` badge if active (.caption2, green) + total tokens (.caption monospaced, ThemeColors.secondaryLabel)
- Token type breakdown per model (row below model name): `TokenTag` components with directional icons
  - Input: `arrow.up`, Output: `arrow.down`, Cache Read: `doc.on.doc`, Cache Write: `square.and.pencil`
  - Each tag: icon (8pt, ThemeColors.tertiaryLabel) + value (.caption2 monospaced, ThemeColors.tertiaryLabel)
  - Aligned with 14pt leading spacer to match model icon width
  - Each `TokenTag` has `accessibilityName` for VoiceOver
- **Cost estimation** (when `aibattery_showCostEstimate` is true):
  - Header: total cost next to "Tokens" label (.caption monospaced, ThemeColors.secondaryLabel)
  - Per-model: cost inline before token total (.caption2 monospaced, ThemeColors.secondaryLabel)
  - All cost values have `.copyable()` modifier

Padding: H 16, V 12

### Click-to-Copy Behavior (`Views/CopyableText.swift`)

`CopyableModifier` ViewModifier applied via `.copyable(_ value:)` extension:
- Copies formatted display value to `NSPasteboard.general` on tap
- Hover feedback: pointer cursor (`NSCursor.pointingHand`) + subtle background highlight (`.primary.opacity(0.10)`)
- Brief clipboard icon overlay (`doc.on.clipboard.fill`, 9pt, `.secondary`, 1.2s duration, `.scale.combined(with: .opacity)` transition, offset right of content)
- `.help` tooltip shows the value
- Applied to: usage percentages, token counts, health stats, insight summaries, cost values, session ID prefix

### ❺ Activity Chart (`Views/ActivityChartView.swift`)

Compact chart with mode toggle. Positioned below Tokens section.

- Header row: `"Activity"` (.subheadline.bold()) + segmented picker (.segmented, width 120, scaleEffect 0.8)
- Toggle modes: `"12H"` (Hourly), `"7D"` (Daily), `"12M"` (Monthly)
- **Mode persistence**: `@AppStorage("aibattery_chartMode")` — persists across popover close/reopen
- Empty state: centered VStack with `chart.line.flattrend.xyaxis` icon (14pt, .quaternary) + `"No activity data"` (.caption2, .tertiary), 50pt height

Chart styling (all modes):
  - LineMark: `.orange`, 1.5pt stroke, catmullRom interpolation
  - AreaMark: orange gradient (0.3 → 0.1 opacity, top → bottom)
  - PointMark: `.orange`, symbolSize 12 (daily + monthly only; hourly skips for cleaner look)
  - `.chartPlotStyle { $0.background(.clear) }` (fixes white background)
  - Y-axis: `AxisMarks(position: .trailing, values: .automatic(desiredCount: 3))` with compact labels (`compactCount`: "2K", "3.2M") and `AxisTick` (0.5pt, tertiaryLabel)
  - Height: 50pt

X-axis per mode:
  - **12H**: Trailing 12-hour window ending at current hour. X-axis uses offset 0–11; labels at offsets [0, 3, 6, 9, 11] show actual clock hours (zero-padded). Domain 0...11. Font: `.system(size: 8)`. At midnight wrap (e.g. 2 AM), hours 15–23 show 0 (only today's data exists).
  - **7D**: Rolling 7-day window. Day abbreviation (`.system(size: 9)`) for all days including today
  - **12M**: Rolling 12-month window. 3-letter month (`"MMM"` → Jan, Feb, etc.), `.system(size: 9)`

Data per mode:
  - **12H**: `todayHourCounts` trailing 12 hours (`(currentHour - 11)` through `currentHour`, wrapping via `% 24`)
  - **7D**: `dailyActivity` last 7 days (rolling window) → daily message counts
  - **12M**: `dailyActivity` grouped by year-month, summed, rolling 12-month window. Current month projected to full-month pace (`total * daysInMonth / dayOfMonth`) for fair comparison.

**Trend summary** (below chart, mode-aware, two rows of two stats each):

- **12H** — Row 1: vs-yesterday change (↑/↓/→ + delta, colored) + msgs today. Row 2: throttle count today + peak hour.
- **7D** — Row 1: weekly trend arrow + vs-yesterday change + avg/day. Row 2: throttle count this week + busiest day.
- **12M** — Row 1: vs-last-month change (projected, ±10% threshold) + this month total (compactCount). Row 2: throttle count this month + busiest month.

Throttle label: `"Throttled: 0"` (ThemeColors.secondaryLabel) or `"Throttled: N×"` (ThemeColors.caution). Reads `UsageViewModel.throttleCount(days:)`.

All trend stats use `.caption` monospaced font with `ThemeColors.secondaryLabel`. Change indicators use accent colors. Entire trend block is `.copyable()` — builds a plain-text summary via `trendCopyText()` with bullet separators.

`.padding(.top, 4)`

Padding: H 16, V 12

### ❻ Insights (`Views/InsightsSection.swift`)

- Today: `"Today"` label (.caption, ThemeColors.secondaryLabel) + `"{msgs} msgs · {sessions} sess · {tools} calls"` (.caption, monospaced)
- All Time: `"All Time"` label (.caption, ThemeColors.secondaryLabel) + `"{messages} msgs · {sessions} sessions"` (.caption, monospaced)
- Each row: label left, stats right (HStack with Spacer)

Padding: H 16, V 12

### ❼ Footer (`UsagePopoverView.footerSection`)

Links row in HStack (spacing 10):
1. **Usage**: chart.bar icon (9pt) + "Usage" + arrow.up.right (6pt) → opens `platform.claude.com/usage`
2. **Status**: colored circle (6pt) + "Status" + arrow.up.right (6pt) → opens `status.claude.com`
3. _(Spacer)_
4. **Logout**: rectangle.portrait.and.arrow.right icon (9pt) + "Logout" → clears OAuth tokens
5. **Quit**: xmark.circle icon (9pt) + "Quit" → terminates app

Each button's inner HStack uses `.fixedSize()` to prevent text wrapping. Links row spacing: 10pt.

Active incident banner (if `incidentNames` non-empty): triangle icon + `MarqueeText(texts:, color: statusColor)` cycling through all active incidents with cross-fade transitions (color matches incident severity)

All text: .caption2, .secondary. Padding: H 16, V 8.

Status colors: operational=green, degraded=yellow, partial=orange, major=red, maintenance=blue, unknown=gray

### Loading / Error / Empty States

- **Loading**: centered spinner (0.8 scale) + "Loading...", 80pt height
- **Error**: orange triangle + message + blue "Retry" button, 100pt height
- **Empty**: "No Claude Code data found" + "Start a Claude Code session to populate usage data.\nData appears automatically once Claude Code is running.", 80pt height

## Menu Bar

### StatusBarManager (`Views/StatusBarManager.swift`)

Native AppKit `NSStatusItem` with `button.image` (star icon) + `button.title` (percentage/countdown). Replaces SwiftUI's `MenuBarExtra` to gain full control over popover lifecycle.

**Button rendering** (native AppKit, no NSHostingView):
- `button.image` = `MenuBarIcon.statusBarImage(for: percent)` — star icon colored by usage band
- `button.title` = percentage or countdown text
- `button.imagePosition = .imageLeading` for icon-then-text layout
- `button.font` = `.monospacedDigitSystemFont(ofSize: 0, weight: .regular)` — matches macOS battery indicator style

**Countdown display**: title shows countdown to reset instead of percentage when any of these conditions are met:
- `rateLimits.isThrottled == true` → shows binding reset countdown
- `fiveHourPercent >= 100` → shows 5-hour window reset countdown
- `sevenDayPercent >= 100` → shows 7-day window reset countdown
- Both windows exhausted → shows earliest reset

This ensures the user sees actionable "2h 15m" instead of a stuck "100%" when capacity is exhausted. Overrides the selected metric mode entirely. Updates on each polling cycle.

**Normal mode**: shows `"{percent}%"` driven by selected metric mode (reads `UserDefaults` directly since `@AppStorage` requires SwiftUI View context).

**Staleness**: `button.appearsDisabled = true` when last fresh fetch > 5 minutes ago (native dimming).

**Panel behavior** (floating `NSPanel`, not `NSPopover`):
- Standalone `PopoverPanel` subclass (borderless, `canBecomeKey = true`) with `NSVisualEffectView` (`.popover` material, 10pt corner radius) + `NSHostingView` content
- `hidesOnDeactivate = false`, `level = .floating`
- Closes on: (1) clicking the status item again, (2) pressing Escape, or (3) clicking outside the panel / switching apps
- Positioned below the status item, centered horizontally, clamped to the status item's screen edges (multi-monitor safe)
- `NSApp.activate(ignoringOtherApps: true)` after showing ensures keyboard events reach it (LSUIElement app)
- `NSEvent.addLocalMonitorForEvents(matching: .keyDown)` for Escape key dismissal
- `NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown])` for click-outside dismissal

**Reactivity**: Combine subscriptions to `viewModel.$snapshot` and `viewModel.$lastFreshFetch` drive button updates. Auth changes via `oauthManager.$isAuthenticated` trigger refresh.

### MenuBarIcon (`Views/MenuBarIcon.swift`)

- 22×22 NSImage canvas (extra room for glow/sparkles), CGContext-based drawing
- 4-pointed star: 8 vertices alternating outer (6.5pt) / inner (2.0pt) radius
- Centered at (11, 11), rotation offset -π/2 (starts from top)
- Fill: solid color from caller (matches active metric mode — rate limit or context health thresholds)
- Stroke: high-contrast → black 0.8 / 1.0pt; light mode → black 0.3 / 0.75pt; dark mode → color 0.6 / 0.5pt
- `isTemplate = false`

**Three render modes** based on state:

1. **Breathing mode (normal)**: star itself scales up and down with a soft circular halo behind it
   - Star scale range grows with usage: 1.0–1.08x at <60%, up to 1.0–1.14x at 95%+
   - Halo alpha range grows with usage: 0–0.12 at low, 0.12–0.32 at high
   - Halo radius: star outer radius × scale × 1.15
   - Sine-wave breathing factor from discrete pulse step

2. **Broken mode (throttled)**: star fractures into 4 triangular fragments with dramatic pulse
   - Each point of the 4-pointed star is a triangle (outer tip + two adjacent inner vertices)
   - Each triangle offset outward from center by ~1.5pt along its radial direction
   - Fragment scale breathes 1.0–1.14x, halo alpha 0.15–0.45
   - Visible gaps between fragments — the star appears "shattered"

3. **Recovery sparkle (throttle → green transition)**: 30s celebration effect after throttle clears
   - Star drawn at normal size, surrounded by subtle twinkling cross sparkles
   - 8 pre-defined sparkle positions evenly spaced around the star (8–9pt from center)
   - Each frame shows 2-3 sparkles (rotating subset), frames change every 500ms (half pulse rate)
   - Each sparkle is a + cross shape (1.6pt arm, 0.7pt stroke width, 0.7 alpha)
   - Triggered by `StatusBarManager` detecting `isThrottled` going from true → false
   - Automatically stops after 30 seconds, returning to normal breathing mode

**Animation**: `StatusBarManager` runs a repeating timer (4s full cycle, 8 discrete steps, 500ms per tick).
- Always active — breathing at all usage levels, dramatic pulse when throttled
- Recovery sparkle overlaid for 30s after throttle clears
- Pauses on screen sleep, resumes on wake
- Timer callback uses `MainActor.assumeIsolated` (no async dispatch overhead)
- Timer stopped only when app terminates

**Star color selection** (by `StatusBarManager`):
- Rate limit modes: `ThemeColors.barNSColor` (green < 50%, yellow 50–80%, orange 80–95%, red ≥ 95%)
- Context health mode: `ThemeColors.contextHealthNSColor` (green < 60%, orange 60–80%, red ≥ 80%)
- Throttled: always red/critical band

**Quantized caching**: cache key = `quantizedPercent` (every 5%, 21 buckets) × 100 + `pulseStep` (0–7) for normal, `10_100 + pulseStep` for broken, `10_200 + pulseStep` for sparkle. Max entries: 21×8 + 8 + 8 = 184. Cache invalidates on colorblind/appearance/contrast change.

- **`statusBarImage(for:color:isBroken:isSparkle:pulseStep:)`**: public static method for StatusBarManager's native AppKit button.

## Accessibility

- **InsightsSection**: `.accessibilityElement(children: .combine)` on both rows with full labels ("Today: N messages, N sessions, N tool calls")
- **TokenUsageSection**: `TokenTag` has `accessibilityName` param (input/output/cache read/cache write), model VStack has combined label
- **UsageBarsSection**: `"Binding constraint"` label on binding badge
- **TokenHealthSection**: combined label on detail row with remaining tokens, turn count, model name

## Help Tooltips

`.help()` modifiers provide hover descriptions across all sections:
- **UsageBarsSection**: binding badge ("This window is the active rate limit constraint"), throttle icon ("You are currently rate limited")
- **TokenUsageSection**: header ("Total tokens used across all models"), active indicator ("Active model in current session"), token type tags (input/output/cache read/cache write)
- **TokenHealthSection**: context gauge ("Percentage of usable context window consumed"), turns label, safe minimum hint, expanded session details tooltip
- **ActivityChartView**: mode picker ("Switch activity chart time range")
- **InsightsSection**: today/all-time labels
- **UsagePopoverView**: metric mode picker, auto mode button

### Tutorial Overlay (`Views/TutorialOverlay.swift`)

Self-managing 3-step walkthrough. Owns its own `@AppStorage(hasSeenTutorial)` — parent passes only `hasData: Bool`. Renders when `!hasSeenTutorial && hasData`.

1. **Rate Limits** — explains 5h/7d bars and binding constraint
2. **Context Health** — explains session monitoring and bands
3. **Settings** — points to gear icon for customization

- Semi-transparent backdrop (`Color.black.opacity(0.4)`)
- Centered card with `.regularMaterial` background, 12pt corner radius, max 280pt width
- Step indicators: 3 dots (active = blue, inactive = secondary 0.3)
- Action button: "Next" / "Get Started" (`.borderedProminent`), "Skip" (.plain, .secondary) on non-final steps
- Sets `hasSeenTutorial = true` on dismiss

## Color Rules

See `spec/CONSTANTS.md` for all color threshold tables.

**Popover background**: solid opaque `windowBackgroundColor` in light mode (no desktop bleed-through); translucent `.popover` vibrancy material with `.behindWindow` blending in dark mode. Panel tracks system appearance changes via KVO on `NSApp.effectiveAppearance`.

**Light/dark mode**: Bar and accent colors use system palette in both modes — the opaque light-mode background provides sufficient contrast for `.systemYellow`, `.systemOrange`, etc. Only text labels and fills use `ThemeColors.adaptive(light:dark:)` for distinct per-appearance values:
- **Orange** (caution, 80–94% bars, orange band): `.systemOrange` both modes
- **Gold** (50–80% bars): `.systemYellow` both modes
- **Chart accent**: `.systemOrange` both modes
- **Trend colors**: SwiftUI `.orange` (up) / `.green` (down) both modes
- **Secondary label**: `black 70%` in light mode; `white 55%` in dark mode
- **Tertiary label**: `black 55%` in light mode; `white 35%` in dark mode (replaces system `.tertiary`/`.quaternary`)
- **Track fill** (bar gauge backgrounds): `black 14%` in light mode; `white 10%` in dark mode
- **Badge fill** (binding label, etc.): `black 9%` in light mode; `white 6%` in dark mode
- **Chart area gradient**: top `chartAccent 30%` → bottom `chartAccent 10%` (both modes)
- **Update banner**: `yellow 12%` fill, `yellow 35%` border (both modes)

**Colorblind mode** (`aibattery_colorblindMode`): switches all status colors from green/yellow/orange/red to blue/cyan/amber/purple for deuteranopia/protanopia users. All color decisions centralized in `ThemeColors`.

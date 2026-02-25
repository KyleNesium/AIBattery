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
│  Models: [slider 1d-7d-All]         │
│  Alerts: ☐ Claude.ai ☐ Claude Code │
├──────────────────────────────────────┤
│ (A) [5-Hour|7-Day|Context]           │  ← Metric toggle + auto
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
│ Activity      [24H] [7D] [12M]      │  ← ❺ Chart
│ ~~~ area chart ~~~                   │
│ 0   3   6   9   12  15  18  21      │
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
├── headerSection
├── Divider
├── SettingsRow (if showSettings — toggled by gear icon)
├── Divider
├── metricToggle (auto "A" circle button left + segmented picker: 5-Hour | 7-Day | Context)
├── Divider
├── ForEach(orderedModes) ← selected metric first, then others
│   ├── FiveHourBarSection / SevenDayBarSection (if rateLimits)
│   └── TokenHealthSection (if topSessionHealths or tokenHealth)
│   └── .animation(.easeInOut(duration: 0.15), value: metricModeRaw) ← scoped to ForEach only
├── TokenUsageGate (owns showTokens @AppStorage, conditionally renders TokenUsageSection)
├── ActivityChartGate (owns showActivity @AppStorage, conditionally renders ActivityChartView)
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
  - **Update available** (`viewModel.availableUpdate` exists): button turns `.yellow`, stays yellow. Clicking opens release URL in browser. `.help("vX.Y.Z available")`.
  - **Up to date** (`updateCheckMessage` set, no update): button turns `.green` for 2.5s, fades back to `.secondary`.
  - **Default**: `.secondary` color. Clicking triggers `forceCheckForUpdate()`.
- Padding: H 16, V 10

### ❶b Settings (`SettingsRow` — private struct)

Collapsible panel toggled by gear icon. Uses `@AppStorage` for persistence.

- **Account name editing**: per-account name row with editable `TextField` (placeholder "Account N", capped at 30 chars). Label: "Active"/"Account" when multi-account, "Name" for single. Changes saved via `OAuthManager.shared.updateAccountMetadata(accountId:displayName:)`.
- **Account management**: shown when >1 account or `canAddAccount`. Remove button (`xmark.circle`) per account when >1. "Add Account" button (.caption, .blue) when `canAddAccount`.
- **Refresh**: Slider (10–60s, step 5) → `aibattery_refreshInterval`
  - Calls `viewModel.updatePollingInterval()` on change
  - Hint: `"~3 tokens per poll"` (.caption2, .tertiary)
- **Models**: Slider (1–8, step 1) → `aibattery_tokenWindowDays` (1–7 = days, 8 maps to 0 = All time)
  - Display: `"All"` when stored value is 0, `"{value}d"` when 1–7
  - Slider positions: 1d, 2d, 3d, 4d, 5d, 6d, 7d, All (left to right)
  - Hint: `"Only show models used within period"` (.caption2, .tertiary)
  - Controls which time window is used for token counts (JSONL-based when >0)
- **Alerts**: Two checkboxes (`.checkbox` toggle style)
  - `Claude.ai` → `aibattery_alertClaudeAI` (Bool, default false)
  - `Claude Code` → `aibattery_alertClaudeCode` (Bool, default false)
  - **Test button**: "Test" (.caption2, .blue, `.plain` style) — visible when at least one toggle is on, calls `NotificationManager.shared.testAlerts()`
  - Hint: `"Notify when service is down"` (.caption2, .tertiary)
  - On enable: calls `NotificationManager.shared.requestPermission()`

- **Display**: Two rows of checkboxes
  - Row 1: "Tokens" → `aibattery_showTokens` (Bool, default true) — toggles the Tokens section; "Activity" → `aibattery_showActivity` (Bool, default true) — toggles the Activity chart
  - Row 2: "Colorblind" → `aibattery_colorblindMode` (Bool, default false) — switches to blue/cyan/amber/purple palette; "Cost*" → `aibattery_showCostEstimate` (Bool, default false) — toggles cost display in Tokens section
  - Hint: `"Cost* = equivalent API token rates"` (.caption2, .tertiary)
- **Rate Limit**: Toggle + threshold slider (50–95%, step 5, default 80%)
  - Hint: `"Notify when rate limit usage exceeds threshold"` (.caption2, .tertiary)
  - Slider + tick marks shown only when toggle is on
- **Startup**: "Launch at Login" checkbox → `aibattery_launchAtLogin`
  - Syncs with `SMAppService.mainApp.status` on appear
**Animations**:
- Settings toggle: `withAnimation(.easeInOut(duration: 0.2))` + `.transition(.opacity.combined(with: .move(edge: .top)))`
- Metric mode changes: `.animation(.easeInOut(duration: 0.15), value: metricModeRaw)` — scoped to ForEach block only, not entire VStack
- Account switch: `withAnimation(.easeInOut(duration: 0.2))`

Values propagate to header + menu bar immediately via `@AppStorage` (settings) and `@Published` (account names).

Padding: H 16, V 10

### Metric Toggle (`UsagePopoverView.metricToggle`)

HStack layout: auto mode button (left) + Spacer + segmented picker (190pt, centered) + Spacer.

**Auto mode button** ("A"): 20pt circle, `.system(size: 9, weight: .heavy, design: .rounded)`.
- **Active**: blue text, `Color.blue.opacity(0.15)` fill, 1.5pt blue stroke with pulsing opacity (0.3–0.8), pulsing blue shadow (radius 1–5pt, opacity 0.1–0.5). Pulse via scoped `.animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: autoGlowing)` on stroke/shadow views only (never `withAnimation` — leaks global repeating transaction).
- **Inactive**: `.secondary.opacity(0.5)` text, no fill, `.secondary.opacity(0.2)` stroke, no shadow.
- Picker dims to 0.4 opacity and is disabled when auto mode is active.
- **Behavior**: auto mode picks whichever metric (5h/7d/context) has the highest percentage via `snapshot.autoResolvedMode` (computed property on `UsageSnapshot`). Applied in both popover and menu bar label.

Padding: H 16, V 10

### Gate Views (`TokenUsageGate`, `ActivityChartGate`)

Each gate view owns a single `@AppStorage` toggle and conditionally renders its content section. This isolates toggle-flip redraws from the parent view.

- **`TokenUsageGate`**: owns `showTokens`. Renders `TokenUsageSection` + `Divider` when `showTokens && snapshot.totalTokens > 0`.
- **`ActivityChartGate`**: owns `showActivity`. Renders `ActivityChartView` + `Divider` when `showActivity` and activity data is available.

### MarqueeText (`Views/MarqueeText.swift`)

News-ticker style scrolling text view. Supports single or multiple texts.

- **Single text**: if text fits container, displays statically. If wider, scrolls left then right (bouncing) at 30pt/s with 2s pause at each end.
- **Multiple texts**: scrolls current text left (if needed), then cross-fades (0.3s out → swap → 0.3s in) to the next text. Non-scrolling texts hold for 3s before advancing. Cycles endlessly.
- Container: `GeometryReader` + `.clipped()`, 14pt height.
- Text measured via background `GeometryReader`, re-measured on index change via `.id(currentIndex)`.

### ❷ Rate Limit Bars (`Views/UsageBarsSection.swift`)

`FiveHourBarSection` + `SevenDayBarSection`, each wrapping a shared `UsageBar` view.

Each bar:
- **Label row**: label (.subheadline.bold()) + `"binding"` badge if active constraint (.system 9pt, monospaced, .tertiary, rounded background) + throttle warning icon + percentage (.title3, monospaced, semibold)
- **Progress bar**: 8pt height, 3pt corner radius. Background: primary 0.1 opacity. Fill: color by percent.
- **Detail row**: left status + `"Resets in Xh Ym"` (.caption2, .tertiary) always visible on right
  - Normal: `"X% remaining"` (.caption2, .secondary)
  - Predictive: `"~Xh Ym to limit"` (.caption2, .caution) when `estimatedTimeToLimit` available (utilization > 50%, estimate before reset)
  - Throttled: `"Rate limited"` (.caption2, .danger)

Reset time format: `>24h` → "in Xd Yh", `1-24h` → "in Xh Ym", `<1h` → "in Xm", expired → "soon"

Padding: H 16, V 12

### ❸ Context Health (`Views/TokenHealthSection.swift`)

Takes `sessions: [TokenHealthStatus]` array (top 5 most recent). Backward-compat `init(health:onRefresh:)` for single session.

- **Header row**: `"Context Health"` (.subheadline.bold) + session toggle + refresh + health badge
- **Session info** (two lines below header, .caption2, .tertiary):
  - Line 1: `projectName · gitBranch · sessionId[:8]` — project, branch, and 8-char session ID prefix (`.copyable()`) for cross-referencing
  - Line 2: `duration · lastActivity · velocity` — e.g. "2h 15m · Today 14:32 · 1.2K/min"
  - Falls back to `"Latest session"` if no metadata on line 1
- **Session toggle** (if multiple sessions): `< 1/3 >` chevron buttons
  - `@State selectedIndex` tracks current session
  - Left/right chevrons with `.easeInOut(0.15)` animation
  - Counter: monospaced caption2, e.g. `"1/3"`
  - Disabled states at bounds, `.quaternary` color when disabled
- **Swipe gesture**: `DragGesture(minimumDistance: 20)` on main VStack — horizontal drag >50pt or fast flick (velocity >300pt/s) navigates prev/next session (same animation as chevron buttons)
- **VoiceOver**: `.accessibilityAdjustableAction` on section — increment/decrement maps to next/previous session
- **Stale session badge** (if lastActivity > 30 min and band != .green): amber dot (6pt) + `"Idle Xm"` (.caption2, .orange)
- **Expanded tooltip**: `.help()` on session info label with full details — session ID, model, context window, all timestamps, all token counts, warnings
- **Refresh button**: `arrow.clockwise` 10pt, .secondary
- **Health badge**: 8pt colored circle + percentage in monospaced subheadline semibold
- **Gauge bar**: same style as usage bars (8pt, 3pt radius), width proportional to usagePercentage
- **Detail row**: `"~{remaining} of {usableWindow} usable"` (.caption, .secondary) + `"{turnCount} turns · {modelName}"` (.caption2, .tertiary)
  - Percentage and remaining are relative to usable window (80% of raw context window)
  - 100% = Claude Code is about to auto-compact
- **Safe minimum hint** (orange/red only): `"(keep above ~{20% of usable} for best quality)"` (.caption2, .tertiary)
- **Warnings**: triangle icon + message. Strong = filled triangle, red. Mild = outline triangle, orange.
- **Suggested action**: (.caption2, red or orange based on band)

Padding: H 16, V 12

### ❹ Tokens (`Views/TokenUsageSection.swift`)

- Header: `"Tokens"` (.subheadline.bold) + total (.subheadline, monospaced, semibold)
- Per-model breakdown via `ForEach` over sorted models (active first via prefix matching, then by totalTokens descending)
- Model icons: SF Symbols cycle (`cpu`, `bolt`, `sparkles`, `cube`, `wand.and.stars`) at 10pt, .secondary, 14pt frame
- Per model row: icon + display name (.caption) + `"▶"` badge if active (.caption2, green) + total tokens (.caption monospaced, .secondary)
- Token type breakdown per model (row below model name): `TokenTag` components with directional icons
  - Input: `arrow.up`, Output: `arrow.down`, Cache Read: `doc.on.doc`, Cache Write: `square.and.pencil`
  - Each tag: icon (8pt, .tertiary) + value (.caption2 monospaced, .tertiary)
  - Aligned with 14pt leading spacer to match model icon width
  - Each `TokenTag` has `accessibilityName` for VoiceOver
- **Cost estimation** (when `aibattery_showCostEstimate` is true):
  - Header: total cost next to "Tokens" label (.caption monospaced, .secondary)
  - Per-model: cost inline before token total (.caption2 monospaced, .tertiary)
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
- Toggle modes: `"24H"` (Hourly), `"7D"` (Daily), `"12M"` (Monthly)
- **Mode persistence**: `@AppStorage("aibattery_chartMode")` — persists across popover close/reopen
- Empty state: centered VStack with `chart.line.flattrend.xyaxis` icon (14pt, .quaternary) + `"No activity data"` (.caption2, .tertiary), 50pt height

Chart styling (all modes):
  - LineMark: `.orange`, 1.5pt stroke, catmullRom interpolation
  - AreaMark: orange gradient (0.3 → 0.05 opacity, top → bottom)
  - PointMark: `.orange`, symbolSize 12 (daily + monthly only; hourly skips — 24 dots too dense)
  - `.chartPlotStyle { $0.background(.clear) }` (fixes white background)
  - `.chartYAxis(.hidden)` — keeps chart compact
  - Height: 50pt

X-axis per mode:
  - **24H**: Every 3 hours (0, 3, 6, ..., 21) → zero-padded labels "00", "03", "06", ..., "21". Domain 0...23. Font: `.system(size: 8)`
  - **7D**: Rolling 7-day window. Day abbreviation (`.system(size: 9)`), last day labeled "Today"
  - **12M**: Rolling 12-month window. 3-letter month (`"MMM"` → Jan, Feb, etc.), `.system(size: 9)`

Data per mode:
  - **24H**: `hourCounts` (hour "0"-"23" → aggregate count from stats-cache)
  - **7D**: `dailyActivity` last 7 days (rolling window) → daily message counts
  - **12M**: `dailyActivity` grouped by year-month, summed, rolling 12-month window

**Trend summary** (below chart, always visible when snapshot available):
- Single HStack row: trend arrow (colored per `ThemeColors.trendColor`) + vs-yesterday change (monospaced, colored) + `·` separator + daily average (monospaced, .tertiary) + Spacer + busiest day label (.tertiary)
- Example: `↑ +5 msgs  ·  42 avg/day          Peak on Tuesdays`
- `.padding(.top, 4)`, `.help("Weekly trend: this week vs last week")`

Padding: H 16, V 12

### ❻ Insights (`Views/InsightsSection.swift`)

- Today: `"Today"` label (.caption, .secondary) + `"{msgs} msgs · {sessions} sess · {tools} calls"` (.caption, monospaced)
- All Time: `"All Time"` label (.caption, .secondary) + `"{messages} msgs · {sessions} sessions"` (.caption, monospaced)
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

All text: .caption2, .secondary. Padding: H 16, V 10.

Status colors: operational=green, degraded=yellow, partial=orange, major=red, maintenance=blue, unknown=gray

### Loading / Error / Empty States

- **Loading**: centered spinner (0.8 scale) + "Loading...", 80pt height
- **Error**: orange triangle + message + blue "Retry" button, 100pt height
- **Empty**: "No Claude Code data found" + "Start a Claude Code session to populate usage data.\nData appears automatically once Claude Code is running.", 80pt height

## Menu Bar

### MenuBarLabel (`Views/MenuBarLabel.swift`)

HStack(spacing: 4): `MenuBarIcon` + percentage text (11pt, medium weight, monospaced)

- **Staleness**: percentage text dims to 50% opacity when last fresh fetch > 5 minutes ago

### MenuBarIcon (`Views/MenuBarIcon.swift`)

- 16×16 NSImage, custom drawing
- 4-pointed star: 8 vertices alternating outer (6.5pt) / inner (2.0pt) radius
- Centered at (8, 8), rotation offset -π/2 (starts from top)
- Fill: solid color based on requestsPercent
- Stroke: same color at 0.6 alpha, 0.5pt width
- `isTemplate = false`
- **Band-based caching**: `colorBand` maps percentage to 4 discrete bands (0: <50%, 1: <80%, 2: <95%, 3: >=95%). Static `iconCache: [Int: NSImage]` stores up to 8 entries (4 bands × 2 colorblind modes). Icon only re-rendered when band changes — not on every percentage tick.

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

**Colorblind mode** (`aibattery_colorblindMode`): switches all status colors from green/yellow/orange/red to blue/cyan/amber/purple for deuteranopia/protanopia users. All color decisions centralized in `ThemeColors`.

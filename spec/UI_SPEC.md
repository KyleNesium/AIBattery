# UI Specification

## Popover Layout

275pt wide, VStack layout with fixed header + metric toggle + ordered content sections + fixed footer. No ScrollView (MenuBarExtra `.window` style handles overflow).

## ASCII Mockup

```
┌──────────────────────────────────────┐
│ ✦ AI Battery  Kyle · Org ▾  ⚙   │  ← ❶ Header
├──────────────────────────────────────┤
│ [Settings panel — collapsible]       │  ← ❶b Settings
│  Active: [________]  Org sub-label  │     (gear toggle)
│  Account: [________] (×)            │
│  + Add Account                      │
│  Refresh: [slider 10-60s]           │
│  Models: [slider 1d-7d-All]         │
│  Alerts: ☐ Claude.ai ☐ Claude Code │
├──────────────────────────────────────┤
│    [5-Hour|7-Day|Context]           │  ← Metric toggle
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
├── metricToggle (segmented picker: 5-Hour | 7-Day | Context)
├── Divider
├── ForEach(orderedModes) ← selected metric first, then others
│   ├── FiveHourBarSection / SevenDayBarSection (if rateLimits)
│   └── TokenHealthSection (if topSessionHealths or tokenHealth)
├── TokenUsageSection (includes per-model breakdown)
├── Divider
├── ActivityChartView (if dailyActivity or hourCounts)
├── Divider
├── InsightsSection (Today + All Time stats)
├── Divider
└── footerSection
```

Conditional states (mutually exclusive with content): Loading | Error | Empty

## Section Specs

### ❶ Header (`UsagePopoverView.headerSection`)

- Title: `"✦ AI Battery"` (.headline)
- **Account picker**: always-visible dropdown Menu next to title
  - Label: `accountPickerLabel` + chevron.up.chevron.down (7pt), (.caption, .secondary)
    - Single account: `"displayName · organizationName"` (omits default individual org pattern)
    - Multi-account: active account's org name or display name
    - Fallback: `"Account"` when no metadata available
  - Menu items: all accounts with checkmark on active, clicking switches via `viewModel.switchAccount(to:)`
  - "Add Account" item (plus.circle icon) below divider when `canAddAccount` (< max) — triggers AuthView overlay
  - `.menuStyle(.borderlessButton)`, `.fixedSize()`
- Gear button: `gearshape`, 11pt, toggles Settings panel
- Loading spinner: ProgressView at 0.6 scale
- Padding: H 16, V 10

### ❶b Settings (`SettingsRow` — private struct)

Collapsible panel toggled by gear icon. Uses `@AppStorage` for persistence (except per-account names stored in `AccountRecord`).

- **Per-account names**: `ForEach(accountStore.accounts)` renders `accountNameRow` per account
  - Label: "Active" / "Account" (multi-account) or "Name" (single account)
  - TextField → writes `displayName` on `AccountRecord` via `OAuthManager.updateAccountMetadata()`, clamped to 30 chars
  - Org name sub-label (.caption2, .tertiary) shown below when non-empty
  - Remove button (`xmark.circle`, 10pt, .secondary) — shown only when >1 account, calls `OAuthManager.signOut(accountId:)`
- **Add Account**: `"+ Add Account"` button (.caption, .blue) — shown when `canAddAccount` (< max). Triggers AuthView overlay for second-account flow.
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
  - Hint: `"Notify when service is down"` (.caption2, .tertiary)
  - On enable: calls `NotificationManager.shared.requestPermission()`

Values propagate to header + menu bar immediately via `@AppStorage` (settings) and `@Published` (account names).

Padding: H 16, V 10

### ❷ Rate Limit Bars (`Views/UsageBarsSection.swift`)

`FiveHourBarSection` + `SevenDayBarSection`, each wrapping a shared `UsageBar` view.

Each bar:
- **Label row**: label (.subheadline, .secondary) + `"binding"` badge if active constraint (.system 9pt, monospaced, .tertiary, rounded background) + throttle warning icon + percentage (.title3, monospaced, semibold)
- **Progress bar**: 8pt height, 3pt corner radius. Background: primary 0.1 opacity. Fill: color by percent.
- **Detail row**: `"X% remaining"` (.caption2) + `"Resets in Xh Ym"` (.caption2, .tertiary)

Reset time format: `>24h` → "in Xd Yh", `1-24h` → "in Xh Ym", `<1h` → "in Xm", expired → "soon"

Padding: H 16, V 12

### ❸ Context Health (`Views/TokenHealthSection.swift`)

Takes `sessions: [TokenHealthStatus]` array (top 5 most recent). Backward-compat `init(health:onRefresh:)` for single session.

- **Header row**: `"Context Health"` (.subheadline.bold) + session toggle + refresh + health badge
- **Session info** (two lines below header, .caption2, .tertiary):
  - Line 1: `projectName · gitBranch · sessionId[:8]` — project, branch, and 8-char session ID prefix for cross-referencing
  - Line 2: `duration · lastActivity · velocity` — e.g. "2h 15m · Today 14:32 · 1.2K/min"
  - Falls back to `"Latest session"` if no metadata on line 1
- **Session toggle** (if multiple sessions): `< 1/3 >` chevron buttons
  - `@State selectedIndex` tracks current session
  - Left/right chevrons with `.easeInOut(0.15)` animation
  - Counter: monospaced caption2, e.g. `"1/3"`
  - Disabled states at bounds, `.quaternary` color when disabled
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

Padding: H 16, V 12

### ❻ Insights (`Views/InsightsSection.swift`)

- Today: `"Today"` label (.caption, .secondary) + `"{msgs} msgs · {sessions} sessions · {tools} tools"` (.caption, monospaced)
- All Time: `"All Time"` label (.caption, .secondary) + `"{messages} msgs · {sessions} sessions"` (.caption, monospaced)
- Each row: label left, stats right (HStack with Spacer)

Padding: H 16, V 12

### ❺ Activity Chart (`Views/ActivityChartView.swift`)

Positioned below Insights. Compact chart with mode toggle.

- Header row: `"Activity"` (.caption2, .secondary) + segmented picker (.segmented, width 120, scaleEffect 0.8)
- Toggle modes: `"24H"` (Hourly), `"7D"` (Daily), `"12M"` (Monthly)
- **Mode persistence**: `@AppStorage("aibattery_chartMode")` — persists across popover close/reopen
- Empty state: `"No activity data"` (.caption2, .tertiary, 40pt height)

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

Padding: H 16, V 8

### ❼ Footer (`UsagePopoverView.footerSection`)

Links row in HStack (spacing 6):
1. **Usage**: chart.bar icon (9pt) + "Usage" + arrow.up.right (6pt) → opens `platform.claude.com/usage`
2. **Status**: colored circle (6pt) + "Status" + arrow.up.right (6pt) → opens `status.claude.com`
3. _(Spacer)_
4. **Logout**: rectangle.portrait.and.arrow.right icon (9pt) + "Logout" → clears OAuth tokens
5. **Quit**: xmark.circle icon (9pt) + "Quit" → terminates app

Each button's inner HStack uses `.fixedSize()` to prevent text wrapping.

Active incident banner below (if `incidentName` exists): triangle icon + incident name

**Staleness indicator** (below incident banner, if `lastFreshFetch` exists):
- HStack(spacing: 3): optional clock icon + label
- When `isShowingCachedData`: `clock.arrow.circlepath` icon (8pt, orange) + "Updated Xm ago" (9pt, orange)
- When fresh: "Updated just now" (9pt, gray 0.4 opacity)
- Format: `< 60s` → "Updated just now", `< 1h` → "Updated Xm ago", `≥ 1h` → "Updated Xh ago"

All text: .caption2, .secondary. Padding: H 16, V 8.

Status colors: operational=green, degraded=yellow, partial=orange, major=red, maintenance=blue, unknown=gray

### Loading / Error / Empty States

- **Loading**: centered spinner (0.8 scale) + "Loading...", 80pt height
- **Error**: orange triangle + message + blue "Retry" button, 100pt height
- **Empty**: "No Claude Code data found" + "Start a Claude Code session to populate usage data.\nData appears automatically once Claude Code is running.", 80pt height

## Menu Bar

### MenuBarLabel (`Views/MenuBarLabel.swift`)

HStack(spacing: 4): `MenuBarIcon` + percentage text (11pt, medium weight, monospaced) + optional org name (10pt, with · separator)

- **Staleness**: percentage text dims to 50% opacity when last fresh fetch > 5 minutes ago
- Org name reads from snapshot first, falls back to `@AppStorage("aibattery_orgName")`. Hides default individual org pattern.

### MenuBarIcon (`Views/MenuBarIcon.swift`)

- 16×16 NSImage, custom drawing
- 4-pointed star: 8 vertices alternating outer (6.5pt) / inner (2.0pt) radius
- Centered at (8, 8), rotation offset -π/2 (starts from top)
- Fill: solid color based on requestsPercent
- Stroke: same color at 0.6 alpha, 0.5pt width
- `isTemplate = false`

## Color Rules

See `spec/CONSTANTS.md` for all color threshold tables.

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
│  Refresh: [slider 30-300s]          │
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
│ Tokens    92% cached  ~$12  18.9M   │  ← ❹ Tokens
│   Opus 4.6  ▶     ~$8.50  12.3M     │   (per-model)
│     93% cached · 29K out             │
│   Sonnet 4.5       ~$3.81  6.6M     │
│     89% cached · 15K out             │
├──────────────────────────────────────┤
│ Projects          ↕ by tokens 18.9M │  ← ❹b Projects
│   📁 AIBattery    ~$12  8.1M      │   (per-project,
│   🔨 my-webapp     ~$4  2.3M      │    6 shown, expand)
│   ⌨ scripts        ~$1  1.2M      │
│        ▾ Show all (8)              │
├──────────────────────────────────────┤
│ Insights  515M  [5H] [7D] [12M]     │  ← ❺ Chart
│ ~~~ area chart ~~~                   │
│ HH:MM  HH:MM  HH:MM  (trailing 5h)  │
│   All Time  1,247 msgs · 89 sess   │     (insight rows
│   Longest  2h 15m · 42 msgs        │      below trend)
│   Period   Nov 6 – Mar 10, 2026    │
├──────────────────────────────────────┤
│ 📊Usage↗  ●Status↗   Logout  Quit │  ← ❻ Footer
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
│   ├── DisplaySettingsSection — owns idleSessionMinutes, colorblindMode
│   ├── AlertSettingsSection — owns alertStatus, alertRateLimit, rateLimitThreshold
│   └── LaunchAtLoginSection — owns launchAtLogin
├── Divider
├── metricToggle (auto "A" circle button left + custom tab bar: 5h | 7d | Ctx)
│   (auto mode highlights selected tab via read-only binding)
├── Divider
├── ForEach(orderedModes) ← selected metric first, then others
│   ├── FiveHourBarSection / SevenDayBarSection (if rateLimits)
│   ├── LocalEstimateSection (if !rateLimits && isUsingLocalEstimate)
│   ├── StandardLimitsSection (if !rateLimits && !isUsingLocalEstimate && standardLimits)
│   └── TokenHealthSection — collapsible (if topSessionHealths or tokenHealth)
│   └── .animation(MotionConstants.snappy, value: metricModeRaw) ← scoped to ForEach only
├── ProjectUsageGate (data check, ProjectUsageSection owns collapsed @AppStorage)
├── InsightsGate (data check, InsightsView owns collapsed @AppStorage)
├── Divider
├── footerSection
└── .overlay { TutorialOverlay(hasData:) } — self-managing visibility via own @AppStorage
```

Conditional states (mutually exclusive with content): Loading | Error | Empty

## Design Tokens

All font sizes, spacing values, layout dimensions, and animation durations are defined as named constants in `Utilities/`:
- **Typography** — 24 named font styles (e.g., `Typography.sectionHeader`, `Typography.monoValue`, `Typography.tinyLabel`, `Typography.trendSymbol`, `Typography.autoModeLabel`)
- **Spacing** — 11 spacing constants (`micro` 1pt, `tight` 2pt, `xsmall` 3pt, `inner` 4pt, `small` 4pt, `gap` 6pt, `section` 8pt, `medium` 10pt, `authGap` 12pt, `sectionHorizontal` 16pt, `overlay` 24pt)
- **Layout** — 35 dimension constants (`popoverWidth` 275pt, `chartHeight` 50pt, `barHeight` 8pt, `barCornerRadius` 3pt, `chevronFrame` 22pt, `dotSize` 8pt, `dotSizeSmall` 6pt, `tabCornerRadius` 4pt, `smallCornerRadius` 4pt, `bannerCornerRadius` 6pt, `iconClipRadius` 10pt, `cardCornerRadius` 12pt, `autoModeSize` 20pt, `chartSymbolSize` 12pt, `shadowSmall` 1pt, `glowRadius` 4pt, `borderWidth` 1.5pt, `subtleBorderWidth` 1pt, `costColumn` 46pt, `tokenColumn` 42pt, `insightLabel` 55pt, `marqueeHeight` 14pt, `spinnerSize` 10pt, `stateHeightLoading` 40pt, `stateHeightEmpty` 80pt, `stateHeightError` 100pt, `iconSize` 22pt, `settingsLabel` 50pt, `sliderValueLabel` 28pt, `appIconSize` 48pt, `activityModePickerWidth` 120pt, `indexColumn` 14pt, `tutorialCardMaxWidth` 280pt, `accountPickerMaxWidth` 100pt, `clipboardIconOffset` 13pt)
- **ThemeColors** — surface elevation (`surfaceLevel1`, `surfaceLevel2`), interactive states (`hoverFill`, `copyableHoverFill`), opacity tokens (`dividerOpacity` 0.3, `overlayBackdropOpacity` 0.4, `inactiveIndicatorOpacity` 0.45, `subtleBorderOpacity` 0.2, `hoverBorderOpacity` 0.4, `activeLabelOpacity` 0.5, `focusRingOpacity` 0.6, `shadowOpacity` 0.25, `disabledOpacity` 0.55, `disabledDeepOpacity` 0.25, `subtleElementOpacity` 0.12, `subtleStrokeOpacity` 0.35, `chartGradientStartOpacity` 0.3, `chartGradientEndOpacity` 0.1, `activeAccentOpacity` 0.6, `activeElementFillOpacity` 0.15, `enabledControlOpacity` 0.6)
- **MotionConstants** — 7 animation/transition tokens (`standard` 0.15s easeOut, `snappy` 0.1s easeOut, `smooth` 0.4s easeInOut, `fadeOut` 0.3s, `dialog` 0.2s, `spin` 0.5s, `expandTransition` opacity+move)

Full token values are listed in `CONSTANTS.md > Design Tokens`.

All visual section dividers use `StyledDivider` — a shared component rendering `Divider()` at `ThemeColors.dividerOpacity` (0.3) with `Spacing.tight` (2pt) vertical padding.

## Section Specs

### ❶ Header (`PopoverHeaderView`)

- Title: `"✦ AI Battery"` (.headline)
- **Account picker**: always-visible dropdown Menu next to title
  - Label: display name if set, otherwise `"Account N"` for multi-account / `"Account"` for single (.caption, ThemeColors.secondaryLabel)
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
  - Yellow circle icon + **"vX.Y.Z ↗"** (.caption2, ThemeColors.secondaryLabel) — clickable, opens GitHub release page
  - **"↓ Install Update"** (.caption2, .blue) — tries Sparkle in-app update; falls back to opening GitHub release if Sparkle not ready
  - **"✕"** dismiss button (xmark.circle.fill, 14pt, ThemeColors.secondaryLabel) — hides banner, yellow icon stays yellow; clicking icon re-shows banner
  - State: `@State updateBannerDismissed` (resets when yellow icon clicked)
- Padding: H 16, V 6

### ❶b Settings (`SettingsRow` — private struct, decomposed into sub-views)

Collapsible panel toggled by gear icon. Decomposed into sub-views so each `@AppStorage` toggle only redraws its own section.

**Parent `SettingsRow`**: holds `viewModel`, `accountStore`, `onAddAccount` closure. Contains account name rows (depend on `accountStore`) and delegates sections to child views. Uses `ForEach(accounts)` with index derived inside loop body. Subtle dividers (`Divider().opacity(0.5)`) separate account names, refresh, display, alerts, and startup sub-sections.

**`RefreshSettingsSection`** (owns `refreshInterval`):
- **Refresh**: Slider (30–300s, step 30) → `aibattery_refreshInterval`
  - Calls `viewModel.updatePollingInterval()` on change
  - Marks: 30s, 1m, 2m, 3m, 4m, 5m
  - Hint: `"~3 tokens/poll · API data kept until next update"` (.tinyLabel, .tertiaryLabel)

**`DisplaySettingsSection`** (owns `idleSessionMinutes`, `colorblindMode`):
- **Idle**: Slider (1–6, step 1) → `aibattery_idleSessionMinutes` (30/60/120/240/480 minutes, 0 = Never)
  - Display: `"30m"`, `"1h"`, `"2h"`, `"4h"`, `"8h"`, or `"∞"` (Never)
  - Slider positions: 30m, 1h, 2h, 4h, 8h, ∞ (left to right)
  - Hint: `"Hide idle sessions from context health"` (.caption2, .tertiary)
- **Display**: Checkboxes
  - "Colorblind" → `aibattery_colorblindMode`

**`AlertSettingsSection`** (owns `alertStatus`, `alertRateLimit`, `rateLimitThreshold`):
- **Alerts row**: "Status" checkbox + "Rate Limit" checkbox + "Test" button (when Status enabled)
  - Status: notifies on any of the 5 tracked status page components
  - Rate Limit: threshold slider (50–95%, step 5, default 80%) appears below when enabled

**`LaunchAtLoginSection`** (owns `launchAtLogin`):
- **Startup**: "Launch at Login" checkbox → `aibattery_launchAtLogin`
  - Syncs with `SMAppService.mainApp.status` on appear

**`sliderMarks()`**: `fileprivate` file-level helper for generating slider tick marks (shared by sections).

**Animations**:
- Settings toggle: `withAnimation(MotionConstants.standard)` — `.easeOut(duration: 0.15)`
- Metric mode changes: `.animation(MotionConstants.snappy, value: metricModeRaw)` — `.easeOut(duration: 0.1)`, scoped to ForEach block only, not entire VStack
- Account switch: `withAnimation(MotionConstants.standard)` — `.easeOut(duration: 0.15)`

### Panel Visibility Safety (PG-01)

All popover animations are naturally gated by SwiftUI's view lifecycle. When the panel is hidden (`orderOut`), `NSHostingView` removes all views from the rendering tree — no layout passes occur, no `.animation()` modifiers evaluate, and no `withAnimation` blocks can be triggered (no user interaction possible). `MarqueeText` explicitly calls `cancelAndStop()` in `.onDisappear`. The `StatusBarManager` breath timer operates at the AppKit layer outside the `NSHostingView` and is not a popover animation. Verified by code audit — no runtime gating logic is needed.

Values propagate to header + menu bar immediately via `@AppStorage` (settings) and `@Published` (account names).

Padding: H 16, V 8

### Collapsible Sections

Context Health, Tokens, Projects, and Activity sections use `CollapsibleSectionHeader(title:collapsed:tooltip:)` — a shared view with rotating chevron (`chevron.right`, 8pt bold), bold title, and VoiceOver labels. Collapsed state persists via `@AppStorage` per section (`contextCollapsed`, `tokensCollapsed`, `projectsCollapsed`, `activityCollapsed`). When collapsed, the header row shows with summary value on the right: Tokens shows total tokens + cost, Projects shows total tokens + cost, Activity shows vs-yesterday trend. No contextual hints (model names, project counts) in collapsed state. Collapse/expand animates with `MotionConstants.standard` (`.easeOut(duration: 0.15)`).

### Gate Views (`ProjectUsageGate`, `InsightsGate`)

Gate views check data availability and render the section + divider. Sections own their own collapsed `@AppStorage`.

- **`ProjectUsageGate`**: renders `ProjectUsageSection` + `Divider` when `snapshot.projectTokens` is non-empty.
- **`InsightsGate`**: renders `InsightsView` + `Divider` when activity data or token data is available.

### Metric Toggle (`MetricToggleView`)

Single HStack in a rounded container (`ThemeColors.trackFill` at 0.5 opacity, cornerRadius 6): auto mode button (left) + 1px vertical divider + custom tab buttons (equal-width, ForEach over `MetricMode.allCases`).

**Custom tab bar**: 3 tab buttons using `MetricMode.shortLabel` — `"5 Hour"`, `"7 Day"`, `"Context"`. Single stable `pickerBinding` routes auto/manual mode internally (avoids SwiftUI AttributeGraph crash from swapping Binding instances). Auto mode syncs picker selection to the auto-resolved mode via this binding.
- **Selected tab**: `ThemeColors.action` text, `Typography.bodyLabel` font, `ThemeColors.action.opacity(0.2)` background pill (cornerRadius 4), subtle `ThemeColors.action.opacity(0.4)` border (0.5pt).
- **Unselected tab**: `ThemeColors.secondaryLabel` text, `Typography.base` font, no background.
- **Hover** (unselected): `ThemeColors.hoverFill` background (cornerRadius 4).
- **Vertical divider**: `Color.secondary.opacity(0.2)`, 1pt wide, 14pt tall — separates auto button from tab row.

**Auto mode button** ("A"): 20pt circle, `.system(size: 10, weight: .heavy, design: .rounded)`.
- **Active**: `ThemeColors.action` text, `ThemeColors.action.opacity(0.15)` fill, 1.5pt `ThemeColors.action` stroke at 0.6 opacity, action shadow (radius 4pt, 0.5 opacity). Static styling — no pulse animation. Controlled by the `autoMetricMode` boolean.
- **Hover** (inactive): `.secondary` text, `ThemeColors.hoverFill` background, `.secondary.opacity(0.4)` stroke.
- **Inactive**: `.secondary.opacity(0.5)` text, no fill, `.secondary.opacity(0.2)` stroke, no shadow.
- Tab buttons dim to `ThemeColors.disabledOpacity` (0.55) and are disabled when auto mode is active.
- **Auto highlight**: when auto mode is active, the tab selection syncs to the auto-resolved mode via the single pickerBinding, visually highlighting which tab was chosen.
- **Behavior**: auto mode uses three-tier priority via `snapshot.autoResolvedMode`: throttled → always rate limit window; near-exhaustion (>=95%) → rate limit unconditionally beats context health; **Tier 3** — urgency-normalized comparison via `urgencyScore(percent:mode:)` with piecewise-linear interpolation (see CONSTANTS.md for anchor points); highest urgency wins, context breaks ties. Applied in both popover and menu bar label.

Padding: outer H 16, V 8; container inner V 4
Spacing: auto mode button has 8pt trailing padding (`Spacing.section`); tab buttons spaced 4pt (`Spacing.small`)

### MarqueeText (`Views/MarqueeText.swift`)

News-ticker style scrolling text view. Supports single or multiple texts.

- **Single text**: if text fits container, displays statically. If wider, scrolls left then right (bouncing) at 30pt/s with 2s pause at each end.
- **Multiple texts**: scrolls current text left (if needed), then cross-fades (0.3s out → swap → 0.3s in) to the next text. Non-scrolling texts hold for 3s before advancing. Cycles endlessly.
- Container: `GeometryReader` + `.clipped()`, 14pt height.
- Text measured via background `GeometryReader`, re-measured on index change via `.id(currentIndex)` and on geometry width change via `.onChange(of:)`.

### ❷ Rate Limit Bars (`Views/UsageBarsSection.swift`)

`FiveHourBarSection` + `SevenDayBarSection`, each wrapping a shared `UsageBar` view.

Each bar:
- **Label row**: label (.subheadline.bold()) + `"binding"` badge if active constraint (.system 9pt, monospaced, .tertiary, rounded background) + throttle warning icon + token total (monoCaption, white 70% opacity, tokenColumn-width trailing) + percentage (.headline, monospaced, semibold)
  - Token total shows tokens consumed in the active rate limit window, aligned to the window boundary via `resetsAt`. Uses `fiveHourWindowTokens(resetsAt:)` / `sevenDayWindowTokens(resetsAt:)` — sums only buckets/days within the actual window so the count resets when the window resets.
- **Progress bar**: 8pt height, 3pt corner radius. Background: primary 0.1 opacity. Fill: color by percent.
- **Detail row**: left status + reset countdown on right
  - Normal: `"X% remaining"` (.caption2, secondaryLabel) + `"Resets in Xh Ym"` (.caption2, .tertiary)
  - Predictive: `"~Xh Ym to limit"` (.caption2, .caution) when `estimatedTimeToLimit` available (utilization > 20%, estimate before reset)
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
  - Left/right chevrons with `MotionConstants.snappy` animation (`.easeOut(duration: 0.1)`)
  - Counter: monospaced caption2, e.g. `"1/3"`
- **Swipe gesture**: `DragGesture(minimumDistance: 20)` on main VStack — horizontal drag >50pt or fast flick (velocity >300pt/s) navigates prev/next session (same animation as chevron buttons)
- **VoiceOver**: `.accessibilityAdjustableAction` on section — increment/decrement maps to next/previous session
- **Stale session badge** (if lastActivity > 30 min and band != .green): amber dot (6pt) + `"Idle Xm"` (.caption2, .orange)
- **Expanded tooltip**: `.help()` on session info label with full details — session ID, model, context window, all timestamps, all token counts, warnings
- **Copy details button**: `doc.on.clipboard` 10pt, .secondary → green `doc.on.clipboard.fill` for 1.5s after click. Copies full session details (exact token counts, model, project, branch, warnings) to clipboard via `SessionInfoFormatter.copyableDetails(for:)`.
- **Refresh button**: `arrow.clockwise` 10pt, .secondary
- **Health badge**: 8pt colored circle + percentage in monospaced subheadline semibold
- **Gauge bar**: same style as usage bars (8pt, 3pt radius), width proportional to usagePercentage
- **Detail row**: `"~{remaining} of {usableWindow} usable"` (.caption, ThemeColors.secondaryLabel) + `"{turnCount} turns · {modelName}"` (.caption2, ThemeColors.tertiaryLabel)
  - Percentage and remaining are relative to usable window (80% of raw context window)
  - 100% = Claude Code is about to auto-compact
- **Safe minimum hint** (orange/red only): `"(keep above ~{20% of usable} for best quality)"` (.caption2, .tertiary)
- **Warnings**: triangle icon + message. Strong = filled triangle, red. Mild = outline triangle, orange.
- **Suggested action**: (.caption2, red or orange based on band)

Padding: H 16, V 8

### ❷b Local Estimate Fallback (`Views/LocalEstimateSection.swift`)

Shown when Anthropic's unified 5h/7d rate limit headers are unavailable (e.g., API header removal — see issue #141). Renders one window (5h or 7d) based on the active metric mode, so the mode selector and auto-mode work identically to the API data path.

- **Label row**: `"{Window} Usage"` (.buttonLabel) + percentage (.monoValue, copyable) + token count with limit (`"X / Y"`, .monoValue, ThemeColors.secondaryLabel, copyable)
- **Gauge bar**: same style as rate limit bars (GaugeBar, 8pt height, 3pt radius), colored by percent via `ThemeColors.barColor`
- **Remaining row**: `"~X remaining"` (.tinyLabel, ThemeColors.secondaryLabel) — `~` prefix when limit is estimated from plan tier
- **Limit sources**: calibrated from prior API headers (exact) or inferred from `PlanTier` (estimated). `limitSource` property distinguishes the two.
- Renders via `ForEach(orderedModes)` — same slot as `FiveHourBarSection`/`SevenDayBarSection`
- Condition: `snapshot.rateLimits == nil && snapshot.isUsingLocalEstimate`

Padding: H 16, V 8

### ❷c Standard Limits Fallback (`Views/StandardLimitsSection.swift`)

Last-resort fallback when both unified 5h/7d headers and local estimate are unavailable. Shows per-minute request and token limits from standard Anthropic API headers (`anthropic-ratelimit-*`).

- **Info banner**: info.circle icon (.tinyLabel, ThemeColors.tertiaryLabel) + `"Showing API rate limits (5h/7d usage unavailable)"` (.tinyLabel, ThemeColors.secondaryLabel)
- **Per-limit bar** (requests and/or tokens, via `StandardLimitBar`):
  - Label row: label (.buttonLabel) + warning triangle if exhausted + `"remaining/limit"` (.monoValue, copyable)
  - Gauge bar: same shared GaugeBar component
  - Detail row (TimelineView, 10s tick): remaining count (.tinyLabel, ThemeColors.secondaryLabel) or `"Limit reached"` (.tinyLabel, ThemeColors.danger) + reset countdown (.tinyLabel, ThemeColors.tertiaryLabel)
- Condition: `snapshot.rateLimits == nil && !snapshot.isUsingLocalEstimate && snapshot.standardLimits != nil`

Padding: H 16, V 8

### ❹ Projects (`Views/ProjectUsageSection.swift`)

Per-project token breakdown from JSONL `cwd` field. Same visual pattern as Token Usage section but without per-token-type breakdown rows.

- Header: `"Projects"` (.subheadline.bold) + total (.subheadline, monospaced, semibold)
- **Sort toggle**: right-aligned button (directional arrow icon + label), cycles through 4 modes: tokens descending, cost descending, cost ascending, name alphabetical. Only shown when 2+ projects.
- Per-project row: icon + project name (.caption) + cost (optional) + total tokens (.caption monospaced, ThemeColors.secondaryLabel)
- Project index: numbered rank (`1`, `2`, `3`, ...) in .caption2 monospaced, ThemeColors.tertiaryLabel, 14pt frame
- **Cost**: always visible. Uses `formatCompactCost` (drops cents for >= $1, e.g. "$18"), prefixed with `"~"`. Cost column: 38pt width. Cost text uses ThemeColors.tertiaryLabel for visual separation from token values.
- **5-project limit**: shows top 5 by default. "Show more" expands to 10. "Show less" collapses. Controls row: "Show more"/"Show less" left (accent color) + sort button right — same line. State resets when section is collapsed.
- **Search filter**: appears when expanded. Filters projects by name. Magnifying glass icon + plain text field in subtle rounded background.
- Collapsed state: `@AppStorage("aibattery_projectsCollapsed")`
- Accessibility: combined label per row with project name and token total
- Column widths: cost 38pt, tokens 42pt
- Data source: JSONL entries only (stats-cache lacks per-entry cwd). Entries with nil/empty cwd grouped as "Other".

Padding: H 16, V 8

### Click-to-Copy Behavior (`Views/CopyableText.swift`)

`CopyableModifier` ViewModifier applied via `.copyable(_ value:)` extension:
- Copies formatted display value to `NSPasteboard.general` on tap
- Hover feedback: pointer cursor (`NSCursor.pointingHand`) + subtle background highlight (`.primary.opacity(0.10)`)
- Brief clipboard icon overlay (`doc.on.clipboard.fill`, 9pt, ThemeColors.secondaryLabel, 1.2s duration, `.scale.combined(with: .opacity)` transition, offset right of content)
- `.help` tooltip shows the value
- Applied to: usage percentages, token counts, health stats, insight summaries, cost values, session ID prefix

### ❺ Insights (`Views/ActivityChartView.swift` → `InsightsView`)

Unified section combining activity chart, API-equivalent cost breakdown, and cumulative stats. Positioned below Projects section.

- Header row: `"Activity"` (.subheadline.bold()) + segmented picker (.segmented, width 120, scaleEffect 0.8)
- Toggle modes: `"5H"` (5-hour), `"7D"` (7-day), `"12M"` (12-month)
- **Mode persistence**: `@AppStorage("aibattery_chartMode")` — persists across popover close/reopen
- **Collapsed summary**: vs-yesterday change indicator (arrow + delta, colored) — inline right of header
- Empty state: centered VStack with `chart.line.flattrend.xyaxis` icon (14pt, .tertiary) + `"No activity in {mode} window"` (.caption2, .tertiary), 50pt height

Chart styling (all modes):
  - LineMark: `.orange`, 1.5pt stroke, catmullRom interpolation
  - AreaMark: orange gradient (0.3 → 0.1 opacity, top → bottom)
  - PointMark: `.orange`, symbolSize 12 (daily + monthly only; hourly skips for cleaner look)
  - `.chartPlotStyle { $0.background(.clear) }` (fixes white background)
  - Y-axis: `AxisMarks(position: .trailing, values: .automatic(desiredCount: 3))` with compact labels (`compactCount`: "2K", "3.2M") and `AxisTick` (0.5pt, tertiaryLabel)
  - Height: 50pt

X-axis per mode:
  - **5H**: 20 × 15-minute token buckets. X-axis shows clock times at offsets [0, 5, 10, 15, 19]. Domain 0...19. Font: `.system(size: 8)`.
  - **7D**: Rolling 7-day window. Day abbreviation (`.system(size: 9)`) for all days including today
  - **12M**: Rolling 12-month window. 3-letter month (`"MMM"` → Jan, Feb, etc.), `.system(size: 9)`

Data per mode (cached per-mode with fingerprint — toggling back to a mode skips recomputation if underlying data unchanged):
  - **5H**: `fiveHourTokenBuckets` — 20 × 15-minute token buckets (all 4 token types)
  - **7D**: `dailyTokenTotals` last 7 days (rolling window) → daily token totals (all 4 types)
  - **12M**: `dailyActivity` grouped by year-month, summed, rolling 12-month window. Current month projected to full-month pace (`total * daysInMonth / dayOfMonth`) for fair comparison.

**Trend summary** (below chart, mode-aware, two rows of two stats each):

- **5H** — Row 1: vs-yesterday token change (↑/↓/→ + %, colored) + tokens in 5h (compactCount). Row 2: throttle count today + peak hour.
- **7D** — Row 1: vs-last-week token change (%) + tokens in 7d (compactCount). Row 2: throttle count this week + busiest day.
- **12M** — Row 1: vs-last-month token change (projected, ±10% threshold) + 12-month total (compactCount). Row 2: throttle count this month + busiest month.

Throttle label: `"Throttled: 0×"` (ThemeColors.secondaryLabel) or `"Throttled: N×"` (ThemeColors.caution). Reads `UsageViewModel.throttleCount(days:)`.

All trend stats use `.caption` monospaced font with `ThemeColors.secondaryLabel`. Change indicators use accent colors. Entire trend block is `.copyable()` — builds a plain-text summary via `trendCopyText()` with bullet separators.

`.padding(.top, 4)`

**API Equivalent cost** (below trend, separated by subtle divider):

Mode-aware cost breakdown showing what the usage would cost on the pay-per-token API.
- Header: `"API Equivalent"` (.caption, ThemeColors.secondaryLabel) + total cost (.caption monospaced semibold, `.copyable()`)
- Per-model rows: display name (.caption2) + `"▶"` if active (.green) + cost (.caption2 monospaced, 54pt width) + tokens (.caption2 monospaced, 42pt width)
- Data source: `todayModelTokens` (5H), `weekModelTokens` (7D), `monthModelTokens` (12M) — JSONL entries filtered by time window
- Cost uses `formatCompactCost` (no cents) everywhere

**Insight rows** (below cost, separated by subtle divider):

Insight rows display cumulative stats using `insightRow(label:value:tooltip:)` helper:
- Label left (55pt fixed width, .caption, ThemeColors.secondaryLabel) + value right (.caption monospaced, .primary)
- Values have `.contentTransition(.numericText())` and `.copyable()` modifiers

| Row | Label | Value | Condition |
|-----|-------|-------|-----------|
| Period | `"Period"` | `"Nov 6 – Mar 16, 2026"` (date range) | `firstSessionDate` exists |
| Longest | `"Longest"` | `"{duration} · {messages} msgs"` | `longestSessionDuration` exists & messages > 0 |
| All Time | `"All Time"` | `"{totalMessages} msgs · {totalSessions} sessions"` | Always (at bottom) |

Date range uses `DateFormatters.formatDateRange(from:to:)` — same year omits start year, cross-year includes both.

Padding: H 16, V 8

### ❻ Footer (`PopoverFooterView`)

Links row in HStack (spacing 10):
1. **Usage**: chart.bar icon (9pt) + "Usage" + arrow.up.right (6pt) → opens `claude.ai/settings/usage`
2. **Status**: colored circle (6pt) + "Status" + arrow.up.right (6pt) → opens `status.claude.com`
3. _(Spacer)_
4. **Logout**: rectangle.portrait.and.arrow.right icon (9pt) + "Logout" → two-tap confirmation (first tap shows "Confirm?" in red, auto-reverts after 3s, second tap clears OAuth tokens)
5. **Quit**: xmark.circle icon (9pt) + "Quit" → terminates app (also via Cmd+Q keyboard shortcut)

Each button's inner HStack uses `.fixedSize()` to prevent text wrapping. Links row spacing: 10pt.

**Incident banner / timestamp** (mutually exclusive):
- **Active incidents** (if `incidentNames` non-empty): triangle icon + `MarqueeText(texts:, color: statusColor)` cycling through all active incidents with cross-fade transitions (color matches incident severity). Replaces timestamp.
- **No incidents**: `"Updated {relative time}"` right-aligned (.system 9pt monospaced, ThemeColors.tertiaryLabel). Wrapped in `TimelineView(.periodic(from: .now, by: 10))` for live updates. Tooltip shows absolute time.

All text: .caption2, ThemeColors.secondaryLabel. Padding: H 16, V 8 (section).

Status colors: operational=green, degraded=yellow, partial=orange, major=red, maintenance=blue, unknown=gray

### Loading / Error / Empty States

- **Loading**: centered spinner (0.8 scale) + "Loading...", 80pt height
- **Error**: orange triangle + message + blue "Retry" button, 100pt height
- **Empty**: "No Claude Code data found" + "Start a Claude Code session to populate usage data.\nData appears automatically once Claude Code is running.", 80pt height

## Menu Bar

### StatusBarManager (`Views/StatusBarManager.swift`)

Native AppKit `NSStatusItem` with a single combined `button.image` — percentage/countdown text and the star icon are baked into one `NSImage` via `MenuBarIcon.combinedStatusBarImage(...)`. This bypasses the per-side bezel padding AppKit applies around a separate `title + image` layout, so the menu bar pill hugs the content like Battery / WiFi / Control Center.

**Button rendering** (native AppKit, no NSHostingView):
- `button.image` = `MenuBarIcon.combinedStatusBarImage(text:percent:color:...:menuBarAppearance:)` — text + star rendered into one tightly-packed image (text in `.white`/`.black` based on `menuBarAppearance` — the status bar button's `effectiveAppearance`, which reflects the actual menu bar backdrop including wallpaper tint and translucency, rather than `NSApp.effectiveAppearance` which only tracks the system-wide Light/Dark setting; then 2pt gap, then the colored star with its 4pt canvas padding trimmed from both sides)
- `button.title = ""` — leaving it set would add AppKit's bezel padding back around the text
- `statusItem.length = image.size.width` — sizing the button exactly to the image makes `NSButtonCell.imageRect(forBounds:)` return `origin.x = 0`, so the image is flush against both button edges with no centering gap
- `button.font` = `.monospacedDigitSystemFont(ofSize: 11, weight: .medium)` — used for text measurement inside `combinedStatusBarImage`, matches macOS menu bar status items

**macOS window chrome constraint (unavoidable):** `NSStatusBarWindow` wraps every third-party status item in a window that is exactly **`length + 16`pt wide** (8pt on each side), independent of content. This was verified empirically by probing `button.window?.frame` against `statusItem.length` at multiple sizes — the 16pt delta is invariant. System items (Battery, WiFi, Clock) live inside `ControlCenter`'s private content view and bypass this chrome, which is why they can appear tighter. For third-party `NSStatusItem` users, this 16pt is a floor we can't reduce via public API; the minimum pill width is therefore `content_width + 16`.

**Countdown display**: the baked text in the combined image shows countdown to reset instead of percentage when any of these conditions are met:
- `rateLimits.isThrottled == true` → shows binding reset countdown
- `fiveHourPercent >= 100` → shows 5-hour window reset countdown
- `sevenDayPercent >= 100` → shows 7-day window reset countdown
- Both windows exhausted → shows earliest **future** reset (past dates are filtered out per-window, so once the earlier window has reset the still-valid later window's countdown takes over instead of the display dropping back to `"100%"`)

This ensures the user sees actionable "2h 15m" instead of a stuck "100%" when capacity is exhausted. Overrides the selected metric mode entirely. Refreshes every **1 s when <60 s remain, every 10 s otherwise** via an adaptive `Timer.scheduledTimer` in `StatusBarManager.startCountdownTimer` — the menu bar is kept in sync with the popover's `TimelineView` rather than the longer rate-limit polling cycle.

**Normal mode**: shows `"{percent}%"` driven by selected metric mode (reads `UserDefaults` directly since `@AppStorage` requires SwiftUI View context).

**Staleness**: the icon always renders the last known state — no grey-out. Other menu bar apps (Battery, WiFi) also don't dim on stale data.

**Panel behavior** (floating `NSPanel`, not `NSPopover`):
- Standalone `PopoverPanel` subclass (borderless, `canBecomeKey = true`, handles Cmd+Q) with `NSHostingView` content (10pt corner radius via layer)
- **Dynamic height**: panel resizes to fit SwiftUI content (via `NSView.frameDidChangeNotification` on hosting view), max height is screen-relative (`screen.visibleFrame.height - 40pt`) so all sections fit on most displays, grows downward from fixed top anchor (`panelTopY` set by `positionPanel`)
- `hidesOnDeactivate = false`, `level = .statusBar`
- Closes on: (1) clicking the status item again, (2) pressing Escape, or (3) clicking outside the panel / switching apps
- Positioned below the status item, left-aligned to the status item's left edge, clamped to screen edges (multi-monitor safe)
- Panel uses `.statusBar` level + `orderFrontRegardless` — no `NSApp.activate()` needed (LSUIElement app, avoids stealing focus from the active app)
- `NSEvent.addLocalMonitorForEvents(matching: .keyDown)` for Escape key dismissal
- `NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown])` for click-outside dismissal

**Reactivity**: Combine subscriptions to `viewModel.$snapshot`, `viewModel.$lastFreshFetch`, and `viewModel.$perAccountRateLimits` drive button updates. Auth changes via `oauthManager.$isAuthenticated` trigger refresh. A `UserDefaults.didChangeNotification` observer redraws within ~100 ms when the user flips the "Show all accounts in menu bar" toggle.

**Multi-account display** (when `aibattery_showAllAccountsInMenuBar == true` and ≥2 authenticated accounts exist):
- Text format: `"<a>%\u{00A0}|\u{00A0}<b>%[\u{00A0}|\u{00A0}<c>%]"` — non-breaking spaces around `|` so a single slot doesn't break across the separator. Pure formatting via `MenuBarMultiAccountText.build(order:limits:metricMode:)`.
- Order: `AccountStore.accounts` order (user-controlled, mirrors the popover account picker).
- Star color & breath: driven by the **worst** account's percent (max across `perAccountRateLimits.values`).
- Broken star: triggered if any account has `isThrottled == true` OR any account has 100%+ utilization.
- Countdown mode: triggered by the worst account's reset; renders a single countdown (no per-slot countdown). Source resolved by `MenuBarMultiAccountText.worstResetDate(...)` over per-account reset dates.
- Empty/missing slot: `"—"` (e.g. account fetched but data not yet present).
- `MetricMode.contextHealth`: falls back to `.fiveHour` for per-account percents (context health is per-session, not per-account).
- Single-account fallback: when only 1 account is authenticated even with toggle ON, falls back to the single-account renderer (no separator).

### MenuBarIcon (`Views/MenuBarIcon.swift`)

- 22×22 NSImage canvas (extra room for glow/sparkles), CGContext-based drawing
- 4-pointed star: 8 vertices alternating outer (6.5pt) / inner (2.0pt) radius
- Centered at (11, 11), rotation offset -π/2 (starts from top)
- Fill: solid color from caller (matches active metric mode — rate limit or context health thresholds), no stroke
- `isTemplate = false`
- `alignmentRect` inset `(left: 1, right: 5)` — still set on the per-icon `NSImage` for anywhere the star is used outside the menu bar button (SwiftUI previews, tests). The menu bar pill no longer relies on it — `combinedStatusBarImage` positions the star directly by trimming the 3pt canvas padding on each side

**Three render modes** based on state:

1. **Normal mode**: star appearance depends on usage band
   - **Below 80%**: plain star, no glow, no animation (timer stopped)
   - **Orange band (80–95%)**: static star-shaped glow (1.25× star size, 18% alpha) directly around the star. No breathing, no timer.
   - **Red band (≥95%, not throttled)**: breathing star with 12-pointed star glow (spiky, aggressive). Star scale 1.0–1.14x, glow alpha 0.12–0.32. Timer active.
   - Sine-wave breathing factor from discrete pulse step

2. **Broken mode (throttled)**: star fractures into 4 triangular fragments with starburst rays — **static, no animation**
   - Each point of the 4-pointed star is a triangle (outer tip + two adjacent inner vertices)
   - Each triangle offset outward from center by ~1.5pt along its radial direction
   - Fragment scale fixed at 1.14x (peak intensity)
   - **Starburst glow**: 12 thin triangular rays radiating outward, alpha 0.45, ray tips extend ~1.3× past star tips
   - Visible gaps between fragments — the star appears "shattered" with an explosive burst behind it
   - No timer needed — single cached image, zero CPU wake-ups

3. **Recovery sparkle (throttle → green transition)**: 30s celebration effect after throttle clears
   - Star drawn at normal size, surrounded by subtle twinkling cross sparkles
   - 8 pre-defined sparkle positions evenly spaced around the star (8–9pt from center)
   - Each frame shows 2-3 sparkles (rotating subset), frames change every 500ms (half pulse rate)
   - Each sparkle is a + cross shape (1.6pt arm, 0.7pt stroke width, 0.7 alpha)
   - Triggered by `StatusBarManager` detecting `isThrottled` going from true → false
   - Automatically stops after 30 seconds, returning to normal breathing mode

**Animation**: `StatusBarManager` runs a repeating timer (4s full cycle, 8 discrete steps). Sparkle mode ticks every 500ms (all 8 steps). Red band (≥95%) ticks every 1s (steps by 2) — halves CPU wakeups with imperceptible visual change. Timer restarts automatically when transitioning between sparkle and red band modes.
- Active only when visually impactful: sparkle active or critical usage (≥95%). Throttled uses static broken star — no timer. Orange band (80–95%) uses static glow — no timer. Below 80%, breathing is imperceptible — timer stopped to save wake-ups.
- Recovery sparkle overlaid for 30s after throttle clears
- Pauses on screen sleep, resumes on wake
- Timer callback uses `MainActor.assumeIsolated` (no async dispatch overhead)

**Star color selection** (by `StatusBarManager`):
- Rate limit modes: `ThemeColors.barNSColor(percent:isDarkMenuBar:)` (green < 50%, yellow/gold 50–80%, orange 80–95%, red ≥ 95%). On light menu bars (`isDarkMenuBar == false`) the 50–80% band uses `menuBarGold` (#B88F00) instead of `systemYellow`, which washes out against a light backdrop
- Context health mode: `ThemeColors.contextHealthNSColor` (green < 60%, orange 60–80%, red ≥ 80%)
- Throttled: always red/critical band

**Quantized caching**: cache key = `quantizedPercent` (every 5%, 21 buckets) × 100 + `pulseStep` (0–7) for normal, `10_100 + pulseStep` for broken (static, always step 0 → 1 entry), `10_200 + pulseStep` for sparkle. Max entries: 21×8 + 1 + 8 = 177. Cache invalidates on colorblind or appearance change.

- **`statusBarImage(for:color:isBroken:isSparkle:pulseStep:menuBarAppearance:)`**: public static method for StatusBarManager's native AppKit button. `menuBarAppearance` defaults to `nil` (falls back to `NSApp.effectiveAppearance`); StatusBarManager passes `button.effectiveAppearance` for accurate wallpaper-tinted rendering.

## Accessibility

- **InsightsView insight rows**: `.accessibilityElement(children: .combine)` on each row with full labels ("All time: N messages, N sessions").
- **InsightsView cost section**: model rows have combined accessibility labels with display name, tokens, and cost
- **UsageBarsSection**: `"Binding constraint"` label on binding badge
- **TokenHealthSection**: combined label on detail row with remaining tokens, turn count, model name

## Help Tooltips

`.help()` modifiers provide hover descriptions across all sections:
- **UsageBarsSection**: binding badge ("This window is the active rate limit constraint"), throttle icon ("You are currently rate limited")
- **TokenUsageSection**: header ("Total tokens used across all models"), active indicator ("Active model in current session"), token type tags (input/output/cache read/cache write)
- **TokenHealthSection**: context gauge ("Percentage of usable context window consumed"), turns label, safe minimum hint, expanded session details tooltip
- **ActivityChartView**: mode picker ("Switch activity chart time range")
- **ActivityChartView**: insight rows (All Time/Longest/Period)
- **MetricToggleView**: metric mode custom tab bar, auto mode button

### Tutorial Overlay (`Views/TutorialOverlay.swift`)

Self-managing 3-step walkthrough. Owns its own `@AppStorage(hasSeenTutorial)` — parent passes only `hasData: Bool`. Renders when `!hasSeenTutorial && hasData`.

1. **Rate Limits** — explains 5h/7d bars and binding constraint
2. **Context Health** — explains session monitoring and bands
3. **Settings** — points to gear icon for customization

- Semi-transparent backdrop (`Color.black.opacity(0.4)`)
- Centered card with `.regularMaterial` background, 12pt corner radius, max 280pt width
- Step indicators: 3 dots (active = blue, inactive = secondary 0.3)
- Action button: "Next" / "Get Started" (`.borderedProminent`), "Skip" (.plain, ThemeColors.secondaryLabel) on non-final steps
- Sets `hasSeenTutorial = true` on dismiss

## Color Rules

See `spec/CONSTANTS.md` for all color threshold tables.

**Popover background**: `controlBackgroundColor` — opaque background that adapts to light/dark mode automatically. Very dark in dark mode (matches native macOS menus like Battery and Clipy), white in light mode. Panel tracks system appearance changes via KVO on `NSApp.effectiveAppearance`.

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

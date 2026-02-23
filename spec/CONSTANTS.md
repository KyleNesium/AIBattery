# Constants & Configuration

Every hardcoded value in the app. When changing a threshold, URL, or price, update here first.

## Timing

| Constant | Value | File |
|----------|-------|------|
| Polling interval | 60 sec default (configurable 10–60s via Settings) | UsageViewModel |
| File watcher debounce | 2 sec | FileWatcher |
| FSEvent latency | 2.0 sec | FileWatcher |
| Fallback timer | 60 sec | FileWatcher |
| Stats-cache retry (base) | 60 sec, exponential (doubles per retry), cap 300 sec, max 10 retries | FileWatcher |
| API request timeout | 15 sec | RateLimitFetcher |
| Status request timeout | 5 sec | StatusChecker |
| Status backoff (base) | 60 sec, exponential (doubles per failure), cap 300 sec, ±20% jitter | StatusChecker |
| Rate limit cache max age | 3600 sec (1 hour) | RateLimitFetcher |
| Token expiry buffer | 300 sec (5 min) — refresh early to avoid clock-skew 401s | OAuthManager |
| Token endpoint retry | 2 retries, exponential backoff (1s, 2s) on 5xx | OAuthManager |
| Token endpoint timeout | 15 sec | OAuthManager |
| Adaptive polling threshold | 3 unchanged cycles | UsageViewModel |
| Adaptive polling max | 300 sec (5 min) | UsageViewModel |
| Notification batch delay | 500 ms | NotificationManager |
| Identity timeout | 3600 sec (1 hour) — pending account identity | UsageViewModel |
| Menu bar staleness threshold | 300 sec (5 min) | MenuBarLabel |

## URLs

| Constant | Value |
|----------|-------|
| Messages API | `https://api.anthropic.com/v1/messages?beta=true` |
| Status API | `https://status.claude.com/api/v2/summary.json` |
| Usage Dashboard | `https://platform.claude.com/usage` |
| Status Page | `https://status.claude.com` |
| GitHub Releases | `https://api.github.com/repos/KyleNesium/AIBattery/releases/latest` |

## API Configuration

| Constant | Value |
|----------|-------|
| Anthropic version header | `2023-06-01` |
| Probe models (fallback order) | `claude-sonnet-4-6-20250929`, `claude-sonnet-4-5-20250929`, `claude-haiku-3-5-20241022` (remembers last working model per account) |
| Probe content | `"."` |
| Probe max_tokens | `1` |
| User-Agent | `AIBattery/{version} (macOS)` (dynamic from bundle) |
| Keychain service (OAuth) | `"AIBattery"` |

## Statuspage Component IDs

Exposed as `StatusChecker.claudeAPIComponentID` and `StatusChecker.claudeCodeComponentID`.

| Component | ID |
|-----------|-----|
| Claude API | `k8w3r06qmzrp` |
| Claude Code | `yyzkbfz2thpt` |

## Context Windows

| Model | Window |
|-------|--------|
| claude-opus-4-6 | 200,000 |
| claude-sonnet-4-6-20250929 | 200,000 |
| claude-sonnet-4-5-20250929 | 200,000 |
| claude-haiku-4-5-20251001 | 200,000 |
| claude-3-5-sonnet-20241022 | 200,000 |
| claude-3-5-haiku-20241022 | 200,000 |
| claude-3-opus-20240229 | 200,000 |
| claude-3-sonnet-20240229 | 200,000 |
| claude-3-haiku-20240307 | 200,000 |
| Default fallback | 200,000 |

## Health Thresholds

| Threshold | Default | Notes |
|-----------|---------|-------|
| Usable context ratio | 0.80 | Claude Code auto-compacts at 80% of window |
| Green ceiling | 60% | Below = optimal (of usable window) |
| Red floor | 80% | Above = critical (of usable window) |
| Turn count mild | 15 | Triggers mild warning |
| Turn count strong | 25 | Triggers strong warning |
| Input/output ratio | 20:1 | Triggers ratio warning (includes cache tokens) |
| Safe minimum divisor | 5 | usableWindow / 5 for hint |
| Stale session idle | 30 min | Triggers stale warning if band != green |
| Zero output turns | 3 | Triggers warning if outputTokens == 0 |
| Rapid consumption | < 60s duration, > 50K tokens | Anomaly warning |

## Rate Limit Alerts

| Constant | Value |
|----------|-------|
| Rate limit alert | `aibattery_alertRateLimit` (Bool, default false) |
| Threshold | `aibattery_rateLimitThreshold` (Double, default 80, range 50–95, step 5) |
| Dedup keys | `rateLimit5h`, `rateLimit7d` |
| Delivery | Same `osascript` mechanism as status alerts |
| Deduplication | Fires once when crossing threshold, resets when dropping below |

## Status Alerts

| Constant | Value |
|----------|-------|
| Claude.ai alert | `aibattery_alertClaudeAI` (Bool, default false) |
| Claude Code alert | `aibattery_alertClaudeCode` (Bool, default false) |
| Identifier prefix | `aibattery-status-` |
| Delivery | `osascript` `display notification` |
| Sound | `default` |
| Deduplication | Fires once per outage, resets when service recovers |

## Cost Estimation

| Constant | Value |
|----------|-------|
| Show tokens | `aibattery_showTokens` (Bool, default true) |
| Show activity | `aibattery_showActivity` (Bool, default true) |
| Show cost | `aibattery_showCostEstimate` (Bool, default false) |
| Format | `"$X.XX"` or `"<$0.01"` for sub-penny amounts |
| Note | Shows what the same token usage would cost at API rates — Pro/Max/Teams subscribers aren't billed per-token |

Pricing per million tokens:

| Model | Input | Output | Cache Write | Cache Read |
|-------|-------|--------|-------------|------------|
| Opus 4 | $15 | $75 | $1.875 | $1.50 |
| Sonnet 4 | $3 | $15 | $0.375 | $0.30 |
| Haiku 4 | $0.80 | $4 | $0.10 | $0.08 |
| Sonnet 3.5 | $3 | $15 | $0.375 | $0.30 |
| Haiku 3.5 | $0.80 | $4 | $0.10 | $0.08 |
| Opus 3 | $15 | $75 | $1.875 | $1.50 |

## Display Settings

| Constant | Value |
|----------|-------|
| Colorblind mode | `aibattery_colorblindMode` (Bool, default false) |
| Auto metric mode | `aibattery_autoMetricMode` (Bool, default false) |
| Tutorial seen | `aibattery_hasSeenTutorial` (Bool, default false) |

## Launch at Login

| Constant | Value |
|----------|-------|
| UserDefaults key | `aibattery_launchAtLogin` (Bool, default false) |
| Framework | SMAppService.mainApp (macOS 13+) |
| Failure mode | Silently fails during dev builds (no .app bundle) |

## Update Checker

| Constant | Value |
|----------|-------|
| GitHub API URL | `https://api.github.com/repos/KyleNesium/AIBattery/releases/latest` |
| Check interval | 86400 sec (24 hours) |
| Request timeout | 10 sec |
| Last check key | `aibattery_lastUpdateCheck` (Double, Unix timestamp) |
| Cached version key | `aibattery_lastUpdateVersion` (String, semver) |
| Cached URL key | `aibattery_lastUpdateURL` (String, release page URL) |
| Persistence | Last check + cached update restored on launch, persisted after each check |

## Token Window

| Constant | Value |
|----------|-------|
| Window | User-configurable 0–7 days (slider, 0 = all time) |
| Default | `0` (all time) |
| AppStorage key | `aibattery_tokenWindowDays` |
| Mode when >0 | Computes tokens from JSONL entries within window |
| Mode when 0 | Uses stats-cache modelUsage (all-time) + uncached JSONL |

## UI Layout

| Constant | Value |
|----------|-------|
| Popover width | 275pt |
| Progress bar height | 8pt |
| Bar corner radius | 3pt |
| Section padding H | 16pt |
| Section padding V | 12pt |
| Header padding V | 10pt |
| Footer padding V | 10pt |
| Menu bar icon size | 16×16 |
| Star outer radius | 6.5pt |
| Star inner radius | 2.0pt |
| Health dot size | 8pt |
| Status dot size | 6pt |
| Model dot size | 8pt |
| Token type dot size | 6pt |
| Chart height | 50pt |
| Chart modes | 24H (hourly), 7D (daily rolling), 12M (monthly rolling) |

## Animations

| Constant | Value |
|----------|-------|
| Settings toggle | `.easeInOut(duration: 0.2)` |
| Settings transition | `.opacity.combined(with: .move(edge: .top))` |
| Metric mode change | `.easeInOut(duration: 0.15)` |
| Account switch | `.easeInOut(duration: 0.2)` |
| Copy clipboard icon display | 1.2 seconds, `.easeOut(duration: 0.12)` show / `.easeIn(duration: 0.2)` hide |
| Progress bar fill | `.easeInOut(duration: 0.4)` on width (UsageBar + TokenHealthSection) |
| Numeric text transition | `.contentTransition(.numericText())`, `.easeInOut(duration: 0.4)` on percentages |
| Copy hover highlight | `Color.primary.opacity(0.10)` background, `NSCursor.pointingHand` |
| Auto mode pulse | `.easeInOut(duration: 1.2).repeatForever(autoreverses: true)` — cyan glow |
| MarqueeText scroll | 30pt/s linear, 2s pause at each end |
| MarqueeText hold | 3s before cycling to next text (non-scrolling) |
| MarqueeText cross-fade | 0.3s ease-out fade out, 0.3s ease-in fade in |

## JSONL Processing

| Constant | Value |
|----------|-------|
| Read buffer size | 64 KB |
| Max line size | 1 MB — oversized lines discarded (malformed data protection) |
| Pre-filter marker 1 | `"type":"assistant"` |
| Pre-filter marker 2 | `"usage"` |
| Cache max entries | 200 files |

## Activity Chart

| Constant | Value |
|----------|-------|
| AppStorage key | `aibattery_chartMode` |
| Default mode | `"24H"` (hourly) |
| Persists across sessions | Yes (via `@AppStorage`) |

## File Paths

| Path | Purpose |
|------|---------|
| macOS Keychain, service `"AIBattery"` | OAuth tokens (access, refresh, expiry) |
| `~/.claude/stats-cache.json` | Historical usage aggregates |
| `~/.claude/projects/*/[session-id].jsonl` | Session token data |
| `~/.claude/projects/*/subagents/*.jsonl` | Subagent session data |

All paths are centralized in `ClaudePaths` (`Utilities/ClaudePaths.swift`).

## Color Thresholds

### Menu bar icon + Usage bars

| Range | Color |
|-------|-------|
| 0–49% | Green |
| 50–79% | Yellow |
| 80–94% | Orange |
| 95–100% | Red |

### Colorblind mode palette

| Standard | Colorblind |
|----------|------------|
| Green | Blue |
| Yellow | Cyan |
| Orange | Amber (RGB 1.0, 0.75, 0.0) |
| Red | Purple |

Applied via `ThemeColors` to: usage bars, context health bands, system status dots, menu bar icon.

### Context health bands

| Range | Color | Status |
|-------|-------|--------|
| 0–59% | Green | Optimal |
| 60–79% | Orange | Warning |
| 80–100% | Red | Critical |

### System status

| Status | API strings | Color |
|--------|-------------|-------|
| Operational | `none`, `operational` | Green |
| Degraded Performance | `minor`, `degraded_performance`, `elevated` | Yellow |
| Partial Outage | `major`, `partial_outage` | Orange |
| Major Outage | `critical`, `major_outage` | Red |
| Maintenance | `maintenance`, `under_maintenance` | Blue |
| Unknown | (any unrecognized value) | Gray |

**Incident escalation**: When components report `operational` but active incidents exist, the incident `impact` field (`none`, `minor`, `major`, `critical`) is factored in. If impact is `none` but incidents are active, the status escalates to at least Degraded Performance (yellow).

## Predictive Rate Limit

| Constant | Value |
|----------|-------|
| Minimum utilization | 50% (below this, estimate not shown) |
| Minimum elapsed time | 60 sec (need meaningful burn rate) |
| Shown when | Estimate < remaining time before reset |

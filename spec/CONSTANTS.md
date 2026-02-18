# Constants & Configuration

Every hardcoded value in the app. When changing a threshold, URL, or price, update here first.

## Timing

| Constant | Value | File |
|----------|-------|------|
| Polling interval | 60 sec default (configurable 10–60s via Settings) | UsageViewModel |
| File watcher debounce | 2 sec | FileWatcher |
| FSEvent latency | 2.0 sec | FileWatcher |
| Fallback timer | 60 sec | FileWatcher |
| API request timeout | 15 sec | RateLimitFetcher |
| Status request timeout | 5 sec | StatusChecker |
| Status backoff interval | 300 sec (5 min) | StatusChecker |
| Rate limit cache max age | 3600 sec (1 hour) | RateLimitFetcher |
| Menu bar staleness threshold | 300 sec (5 min) | MenuBarLabel |

## URLs

| Constant | Value |
|----------|-------|
| Messages API | `https://api.anthropic.com/v1/messages?beta=true` |
| Status API | `https://status.claude.com/api/v2/summary.json` |
| Usage Dashboard | `https://platform.claude.com/usage` |
| Status Page | `https://status.claude.com` |

## API Configuration

| Constant | Value |
|----------|-------|
| Anthropic version header | `2023-06-01` |
| Probe models (fallback order) | `claude-sonnet-4-5-20250929`, `claude-haiku-3-5-20241022` |
| Probe content | `"."` |
| Probe max_tokens | `1` |
| User-Agent | `AIBattery/1.0.0 (macOS)` |
| Keychain service | `"Claude Code"` |

## Statuspage Component IDs

Exposed as `StatusChecker.claudeAPIComponentID` and `StatusChecker.claudeCodeComponentID`.

| Component | ID |
|-----------|-----|
| Claude API | `k8w3r06qmzrp` |
| Claude Code | `yyzkbfz2thpt` |

## Plan Tier Inference (from billingType)

Source: `~/.claude.json` → `oauthAccount.organizationBillingType`

| billingType | Plan Name | Price Display |
|-------------|-----------|---------------|
| `"pro"` | Pro | $20/mo |
| `"max"`, `"max_5x"` | Max | $100/mo per seat |
| `"teams"`, `"team"` | Teams | $30/mo per seat |
| `"free"` | Free | (none) |
| `"api_evaluation"`, `"api"` | API | Usage-based |
| `""` (empty) | nil (not shown) | — |
| Other | Capitalized type name | (none) |

Fallback chain: billingType → UserDefaults `aibattery_plan` → nil

## Context Windows

| Model | Window |
|-------|--------|
| claude-opus-4-6 | 200,000 |
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
## Status Alerts

| Constant | Value |
|----------|-------|
| Claude.ai alert | `aibattery_alertClaudeAI` (Bool, default false) |
| Claude Code alert | `aibattery_alertClaudeCode` (Bool, default false) |
| Identifier prefix | `aibattery-status-` |
| Delivery | `osascript` `display notification` |
| Sound | `default` |
| Deduplication | Fires once per outage, resets when service recovers |

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
| Footer padding V | 8pt |
| Menu bar icon size | 16×16 |
| Star outer radius | 6.5pt |
| Star inner radius | 2.0pt |
| Health dot size | 8pt |
| Status dot size | 6pt |
| Model dot size | 8pt |
| Token type dot size | 6pt |
| Chart height | 50pt |
| Chart modes | 24H (hourly), 7D (daily rolling), 12M (monthly rolling) |

## JSONL Processing

| Constant | Value |
|----------|-------|
| Read buffer size | 64 KB |
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
| macOS Keychain, service `"Claude Code"` | API key |
| `~/.claude.json` → `oauthAccount` | Account info (displayName, organizationName) |
| `~/.claude/stats-cache.json` | Historical usage aggregates |
| `~/.claude/projects/*/[session-id].jsonl` | Session token data |
| `~/.claude/projects/*/subagents/*.jsonl` | Subagent session data |

## Color Thresholds

### Menu bar icon + Usage bars

| Range | Color |
|-------|-------|
| 0–49% | Green |
| 50–79% | Yellow |
| 80–94% | Orange |
| 95–100% | Red |

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

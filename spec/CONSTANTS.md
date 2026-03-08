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
| Adaptive polling threshold | 3 unchanged cycles | AdaptivePollingState |
| Adaptive polling escalation | Progressive doubling: base × 2^(cycles past threshold) | AdaptivePollingState |
| Adaptive polling max | 300 sec (5 min) | AdaptivePollingState |
| Notification batch delay | 500 ms | NotificationManager |
| Identity timeout | 3600 sec (1 hour) — pending account identity | UsageViewModel |
| Retry-After max delay | 30 sec (caps parsed Retry-After header) | RateLimitFetcher |
| Sleep pause / wake resume | Immediate (NSWorkspace notifications) | UsageViewModel |
| Menu bar staleness threshold | 300 sec (5 min) | StatusBarManager |
| Menu bar countdown update | Per polling cycle (10–60 sec) | StatusBarManager |

## URLs

| Constant | Value |
|----------|-------|
| Messages API | `https://api.anthropic.com/v1/messages?beta=true` |
| Status API | `https://status.claude.com/api/v2/summary.json` |
| Usage Dashboard | `https://platform.claude.com/usage` |
| Status Page | `https://status.claude.com` |
| GitHub Releases | `https://api.github.com/repos/KyleNesium/AIBattery/releases/latest` |
| Sparkle Appcast | `https://kylenesium.github.io/AIBattery/appcast.xml` |

## API Configuration

| Constant | Value |
|----------|-------|
| Anthropic version header | `2023-06-01` |
| Probe models (fallback order) | Date-stamped IDs; see `RateLimitFetcher.probeModels` for current values (remembers last working model per account) |
| Probe content | `"."` |
| Probe max_tokens | `1` |
| User-Agent | `AIBattery/{version} (macOS)` (dynamic from bundle) |
| Keychain service (OAuth) | `"AIBattery"` |
| Max accounts | 3 |

## Rate Limit Headers

Headers parsed from `/v1/messages` responses (only endpoint that returns them):

| Header | Type | Notes |
|--------|------|-------|
| `anthropic-ratelimit-unified-status` | String | `"allowed"` or `"throttled"` — overall status |
| `anthropic-ratelimit-unified-representative-claim` | String | `"five_hour"` or `"seven_day"` — binding constraint |
| `anthropic-ratelimit-unified-5h-utilization` | Double | 0.0–1.0 (clamped on parse) |
| `anthropic-ratelimit-unified-5h-reset` | Unix timestamp | Seconds since epoch |
| `anthropic-ratelimit-unified-5h-status` | String | `"allowed"` or `"throttled"` |
| `anthropic-ratelimit-unified-7d-utilization` | Double | 0.0–1.0 (clamped on parse) |
| `anthropic-ratelimit-unified-7d-reset` | Unix timestamp | Seconds since epoch |
| `anthropic-ratelimit-unified-7d-status` | String | `"allowed"` or `"throttled"` |

## Statuspage Component IDs

Exposed as `StatusChecker.knownComponents` — array of `StatusComponent` structs with `id`, `name`, `alertKey`.

| Component | ID | Alert Key |
|-----------|-----|-----------|
| claude.ai | `rwppv331jlwc` | `claudeAI` |
| Console | `0qbwn08sd68x` | `console` |
| Claude API | `k8w3r06qmzrp` | `claudeAPI` |
| Claude Code | `yyzkbfz2thpt` | `claudeCode` |
| Claude for Gov | `0scnb50nvy53` | `claudeForGov` |

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
| Rapid consumption seconds | 60 sec | `config.rapidConsumptionSeconds` |
| Rapid consumption tokens | 50,000 | `config.rapidConsumptionTokens` |
| Velocity min duration | 60 sec | `config.velocityMinDuration` |
| Auto mode near-exhaustion | 95% | Rate limit ≥ threshold unconditionally supersedes context health in `autoResolvedMode` |

## Rate Limit Alerts

| Constant | Value |
|----------|-------|
| Rate limit alert | `aibattery_alertRateLimit` (Bool, default false) |
| Threshold | `aibattery_rateLimitThreshold` (Double, default 80, range 50–95, step 5) |
| Dedup keys | `rateLimit5h`, `rateLimit7d` |
| Delivery | Same `UNUserNotificationCenter` mechanism as status alerts |
| Deduplication | Fires once when crossing threshold, resets when dropping below |

## Status Alerts

Single toggle: `aibattery_alertStatus` (Bool, default false). When enabled, alerts fire for any of the 5 tracked components.

| Constant | Value |
|----------|-------|
| Key | `aibattery_alertStatus` |
| Identifier prefix | `aibattery-status-` |
| Delivery | `UNUserNotificationCenter` (native macOS) |
| Sound | `default` |
| Deduplication | Fires once per component per outage, resets when service recovers |
| Migration | One-time (v2): any legacy per-component key enabled → enables `alertStatus` |

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

## Sparkle Auto-Update

| Constant | Value |
|----------|-------|
| Appcast feed URL | `https://kylenesium.github.io/AIBattery/appcast.xml` (Info.plist `SUFeedURL`) |
| EdDSA public key | Info.plist `SUPublicEDKey` — injected at build time via `SPARKLE_EDDSA_PUBLIC_KEY` env var (not committed to source) |
| Automatic checks | Disabled (`automaticallyChecksForUpdates = false`) |
| Automatic downloads | Disabled (`automaticallyDownloadsUpdates = false`) |
| Check interval | 0 (no scheduled checks — user-initiated only) |
| Trigger | User clicks "Install Update" in banner (falls back to GitHub release if Sparkle not ready) |
| Pre-activation | `NSApp.setActivationPolicy(.regular)` + `activate(ignoringOtherApps:)`, reverts to `.accessory` after 5s (LSUIElement workaround) |
| Entitlement | `com.apple.security.cs.disable-library-validation` — required for ad-hoc signed builds to load Sparkle.framework |
| CI secrets | `SPARKLE_EDDSA_KEY` (private signing key), `SPARKLE_EDDSA_PUBLIC_KEY` (public verification key injected into Info.plist) |

## Idle Session Cutoff

| Constant | Value |
|----------|-------|
| Cutoff | User-configurable: 30m, 1h, 2h, 4h, 8h, or Never (slider) |
| Default | `0` (Never — uses 24h performance bound) |
| AppStorage key | `aibattery_idleSessionMinutes` |
| Stored values | `30`, `60`, `120`, `240`, `480` (minutes), `0` (never) |
| Effect | Hides sessions idle longer than cutoff from context health view |
| When 0 (Never) | Uses 24h cutoff (performance bound, existing behavior) |

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
| Menu bar icon canvas | 22×22pt |
| Star outer radius | 6.5pt |
| Star inner radius | 2.0pt |
| Broken star fragment offset | 1.5pt |
| Recovery sparkle arm length | 1.6pt |
| Recovery sparkle stroke width | 0.7pt |
| Recovery sparkle alpha | 0.7 |
| Recovery sparkle frame rate | 500ms (every 2nd pulse step) |
| Recovery sparkle duration | 30 sec |
| Pulse steps per cycle | 16 |
| Pulse cycle duration | 4.0 sec |
| Pulse tick interval | 250ms (4s ÷ 16) |
| Health dot size | 8pt |
| Status dot size | 6pt |
| Model dot size | 8pt |
| Token type dot size | 6pt |
| Chevron button frame | 22×22pt |
| Chevron icon size | 9pt (bold weight) |
| Chevron corner radius | 4pt |
| Chart height | 50pt |
| Chart modes | 12H (hourly trailing), 7D (daily rolling), 12M (monthly rolling) |

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
| Auto mode pulse | `.easeInOut(duration: 1.2).repeatForever(autoreverses: true)` — blue glow |
| MarqueeText scroll | 30pt/s linear, 2s pause at each end |
| MarqueeText hold | 3s before cycling to next text (non-scrolling) |
| MarqueeText cross-fade | 0.3s ease-out fade out, 0.3s ease-in fade in |

## Security Guards

| Constant | Value | File |
|----------|-------|------|
| Max API response size | 2,000,000 bytes (2 MB) — drops oversized responses | SecureNetworking |
| Resource timeout | 30 sec — caps total transfer time (slow-drip defense) | SecureNetworking |
| Max stats-cache file size | 10,000,000 bytes (10 MB) — rejects before read | StatsCacheReader |
| Org ID max length | 128 chars — caps organization ID from API headers | APIProfile |
| Org ID allowed chars | ASCII alphanumeric, hyphens, underscores only | APIProfile |

## JSONL Processing

| Constant | Value |
|----------|-------|
| Read buffer size | 64 KB |
| Max line size | 1 MB — oversized lines discarded (malformed data protection) |
| Pre-filter marker 1a | `"type":"assistant"` (no space) |
| Pre-filter marker 1b | `"type": "assistant"` (with space) |
| Pre-filter marker 2 | `"usage"` |
| Cache max entries | 200 files |

## Activity Chart

| Constant | Value |
|----------|-------|
| AppStorage key | `aibattery_chartMode` |
| Default mode | `"12H"` (hourly) |
| Persists across sessions | Yes (via `@AppStorage`) |

## File Paths

| Path | Purpose |
|------|---------|
| macOS Keychain, service `"AIBattery"` | OAuth refresh token only (`refreshToken_{accountId}`); access token in memory, expiry in UserDefaults (`aibattery_expiresAt_{accountId}`) |
| `~/Library/Application Support/AIBattery/aibattery.lock` | Single-instance POSIX file lock |
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

### Context health icon (different thresholds)

| Range | Color |
|-------|-------|
| 0–59% | Green |
| 60–79% | Orange |
| 80–100% | Red |

### Colorblind mode palette

| Standard | Colorblind |
|----------|------------|
| Green | Blue |
| Yellow | Cyan |
| Orange | Amber (RGB 1.0, 0.75, 0.0) |
| Red | Purple |

Applied via `ThemeColors` to: usage bars, context health bands, system status dots, menu bar icon.

### Colors (light/dark mode)

Most bar and accent colors use system palette in both modes (the opaque light-mode background provides sufficient contrast). Only text labels and fills use adaptive variants.

| Constant | Light | Dark |
|----------|-------|------|
| Orange (caution, 80–94%, orange band) | `.systemOrange` | `.systemOrange` |
| Gold (50–80% bars) | `.systemYellow` | `.systemYellow` |
| Chart accent | `.systemOrange` | `.systemOrange` |
| Trend ↑ | `.orange` | `.orange` |
| Trend ↓ | `.green` | `.green` |
| Menu bar gold | `.systemYellow` | `.systemYellow` |
| Menu bar orange | `.systemOrange` | `.systemOrange` |
| Secondary label | black 70% | white 55% |
| Tertiary label | black 55% | white 35% |
| Track fill | black 14% opacity | white 10% opacity |
| Badge fill | black 9% opacity | white 6% opacity |
| Popover background | solid `windowBackgroundColor` | translucent `.popover` vibrancy |

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

## Compiler Flags

| Flag | Default | Effect |
|------|---------|--------|
| `ENABLE_SPARKLE` | Defined (all 3 SPM targets) | Guards Sparkle imports, `SparkleUpdateService`, and Sparkle-dependent UI. Remove to build App Store variant without Sparkle. |
| `ENABLE_VERSION_CHECKER` | Defined (all 3 SPM targets) | Guards `VersionChecker`, update banner UI, and version check button. Remove for App Store (guideline 3.1.1). |
| `APP_SANDBOX` | NOT defined | Reserved for future App Store sandbox support (security-scoped bookmark for `~/.claude/` access). Only set for App Store builds. |

## Build Environment Variables

| Variable | Default | Effect |
|----------|---------|--------|
| `SPARKLE_EDDSA_KEY` | (unset) | Sparkle EdDSA private key for signing zip artifacts |
| `SPARKLE_EDDSA_PUBLIC_KEY` | (unset) | Sparkle EdDSA public key injected into Info.plist |
| `APP_STORE_BUILD` | (unset) | Strips SUFeedURL from Info.plist; selects `AIBattery-AppStore.entitlements` |
| `CODE_SIGN_IDENTITY` | `-` (ad-hoc) | Signing identity for `codesign --sign`. Set to `"Developer ID Application: ..."` for notarization |
| `APPLE_ID` | (unset) | Apple ID email for `notarytool` submission (notarization skipped when unset) |
| `APPLE_TEAM_ID` | (unset) | Apple Developer team ID for `notarytool` |
| `APPLE_APP_PASSWORD` | (unset) | App-specific password for `notarytool` authentication |

## Sandbox Access (App Store only)

| Constant | Value |
|----------|-------|
| Bookmark key | `aibattery_claudeDirBookmark` (Data, security-scoped bookmark for `~/.claude/`) |
| Active when | `APP_SANDBOX` compiler flag is defined |
| User flow | NSOpenPanel prompts for `~/.claude/` directory; bookmark persisted to UserDefaults |

## Predictive Rate Limit

| Constant | Value |
|----------|-------|
| Minimum utilization | 50% (below this, estimate not shown) |
| Minimum elapsed time | 60 sec (need meaningful burn rate) |
| Shown when | Estimate < remaining time before reset |

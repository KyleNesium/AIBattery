# Data Layer

Every model struct, service class, and algorithm.

## Models

### UsageSnapshot (`Models/UsageSnapshot.swift`)

Main aggregated data struct consumed by all views.

| Field | Type | Source |
|-------|------|--------|
| `lastUpdated` | `Date` | Generated at aggregation time |
| `rateLimits` | `RateLimitUsage?` | API response headers |
| `firstSessionDate` | `Date?` | stats-cache.json (ISO 8601) |
| `totalSessions` | `Int` | stats-cache + additional JSONL (deduped across all dates) |
| `totalMessages` | `Int` | stats-cache + additional JSONL (deduped across all dates) |
| `longestSessionDuration` | `String?` | stats-cache (formatted) |
| `longestSessionMessages` | `Int` | stats-cache |
| `peakHour` | `Int?` | Merged hourCounts (stats-cache + today's JSONL) |
| `peakHourCount` | `Int` | Merged hourCounts |
| `todayMessages` | `Int` | Today's JSONL entries count |
| `todaySessions` | `Int` | Unique session IDs in today's entries |
| `todayToolCalls` | `Int` | max(JSONL tool_use count, stats-cache dailyActivity) for today |
| `hourCounts` | `[String: Int]` | All-time hourly distribution (stats-cache merged with today's JSONL, max per hour) |
| `todayHourCounts` | `[String: Int]` | Today-only hourly breakdown from JSONL (hour "0"-"23" → message count) |
| `modelTokens` | `[ModelTokenSummary]` | Merged stats-cache + JSONL |
| `projectTokens` | `[ProjectTokenSummary]` | JSONL entries grouped by full cwd path |
| `totalTokens` | `Int` | Sum of all `modelTokens.totalTokens` |
| `totalUsageTokens` | `Int` | Input + output only — excludes cache tokens |
| `totalProjectTokens` | `Int` | Sum of all `projectTokens.totalTokens` |
| `totalProjectUsageTokens` | `Int` | Input + output only — excludes cache tokens |
| `totalProjectCost` | `Double` | Sum of all `projectTokens.estimatedCost` |
| `fiveHourTokens` | `Int` | Local token total for 5h window estimation |
| `sevenDayTokens` | `Int` | Local token total for 7d window estimation |
| `fiveHourTokenBuckets` | `[Int: Int]` | 20 × 15-min token buckets for 5H chart (0=oldest, 19=now) |
| `dailyTokenTotals` | `[String: Int]` | Per-date token totals for 7D/12M chart modes |
| `todayModelTokens` | `[ModelTokenSummary]` | JSONL entries from today (cost breakdown) |
| `weekModelTokens` | `[ModelTokenSummary]` | Last 7 days (cost breakdown) |
| `monthModelTokens` | `[ModelTokenSummary]` | Current calendar month (cost breakdown) |
| `dailyActivity` | `[DailyActivity]` | stats-cache + all JSONL dates merged (fills gaps between stale cache rebuild and today) |
| `tokenHealth` | `TokenHealthStatus?` | Most recent session assessment |
| `topSessionHealths` | `[TokenHealthStatus]` | Top 5 sessions by highest usagePercentage (descending) |

Stored (pre-computed at construction): `dailyAverage: Int` (average messages/day from last 7 days of `dailyActivity`), `trendDirection: TrendDirection` (requires 14+ days of activity for a symmetric 7-vs-7 comparison; ±10% threshold → `.up`/`.down`/`.flat`), `busiestDayOfWeek: (name: String, averageCount: Int)?` (highest average from `dailyActivity` by weekday).

Static factory method: `computeActivityStats(_:)` — single-pass computation of all three metrics (average, trend, busiest day), called by `UsageAggregator` at construction time to avoid per-render iteration. Uses `private static let weekdaySymbols = Calendar.current.weekdaySymbols` for day-name lookup.

Stored: `rateLimitPercentConfirmed: Bool` — whether the rate-limit percentage is backed by genuinely fresh data (fresh unified headers this cycle) or an authoritative throttle. Set by `UsageAggregator.aggregate(rateLimitPercentConfirmed:)` from the value `UsageViewModel.refresh()` computes via `alarmConfirmed(rateLimitsFresh:displayedIsThrottled:)`. Part of the hand-written `==` (a confirmed↔unconfirmed flip changes the displayed %, so it must re-render).

Computed: `percent(for: MetricMode) -> Double` (shared metric percentage calculation used by both menu bar and popover) delegates rate-limit modes to the pure static `resolvedPercent(api:local:confirmed:)`: when `rateLimitPercentConfirmed` it trusts the API utilization (`rateLimits?.fiveHourPercent`/`sevenDayPercent`), falling back to `LocalUsageEstimate.fiveHourPercent`/`sevenDayPercent`; when **not** confirmed it *prefers* the local estimate over the held (possibly stale) API value, falling back to the API value only if uncalibrated — so a stale held 100% on wake reads as the real low % instead of a maxed bar. Context health uses `topSessionHealths.first?.usagePercentage` as primary, falls back to `tokenHealth?.usagePercentage`, so auto mode reflects the most critical session, not just the most recent), `isUsingLocalEstimate: Bool` (true when no API rate limits and local estimate can provide percentages — drives conditional rendering of `LocalEstimateSection`), `autoResolvedMode: MetricMode` (four-tier deterministic escalation ladder: **Tier 1** — if throttled, always shows the binding rate limit window; **Tier 2** — if either rate limit >= 80%, shows the higher rate limit window; **Tier 3** — if any active session has context >= 60%, shows context health; **Tier 4** — default shows binding (highest-consumed) rate limit. Used by `UsageViewModel` to derive the candidate for hysteresis filtering), `hasActiveSession: Bool` (whether any tracked session has been active within the staleness window — used by `autoResolvedMode` Tier 3 and `applyHysteresis` context hold check).

Static: `applyHysteresis(candidate:previous:snapshot:) -> MetricMode` — pure function that applies a 10pp de-escalation band to prevent mode flip-flopping near thresholds. When `previous` mode's metric is still above its release threshold (escalation threshold minus `hysteresisDeescalationBand`), holds the previous mode. Throttle (Tier 1) always bypasses hysteresis. Context health hold requires an active session (staleness is a hard gate). Called by `UsageViewModel.updateSnapshot` after each poll.

Static constants: `hysteresisDeescalationBand = 10.0` — the percentage point band below each escalation threshold that must be crossed before releasing the held mode. Release thresholds: rate limit modes at 70% (80% - 10pp), context health at 50% (60% - 10pp).

### ModelTokenSummary

| Field | Type |
|-------|------|
| `id` | `String` (model ID) |
| `displayName` | `String` |
| `inputTokens` | `Int` |
| `outputTokens` | `Int` |
| `cacheReadTokens` | `Int` |
| `cacheWriteTokens` | `Int` |
| `estimatedCost` | `Double` (pre-computed API-equivalent cost) |

Computed: `usageTokens` (input + output, excludes cache).

Computed: `totalTokens` = sum of all four token types. `cacheHitRate: Double?` = `cacheReadTokens / (cacheReadTokens + inputTokens) * 100` (nil when denominator is zero).

Conforms to `Identifiable`, `Equatable`. Equatable enables SwiftUI to diff ForEach collections efficiently (skip re-rendering unchanged rows).

### ProjectTokenSummary (`Models/ProjectTokenSummary.swift`)

Per-project token usage derived from JSONL `cwd` field. Cost is pre-computed per entry using model-specific pricing.

| Field | Type |
|-------|------|
| `id` | `String` (full cwd path; `"Other"` for nil cwd) |
| `projectName` | `String` |
| `inputTokens` | `Int` |
| `outputTokens` | `Int` |
| `cacheReadTokens` | `Int` |
| `cacheWriteTokens` | `Int` |
| `estimatedCost` | `Double` (pre-computed from per-entry model pricing) |

Computed: `totalTokens` = sum of all four token types

Conforms to `Identifiable`, `Equatable`. Equatable enables SwiftUI to diff ForEach collections efficiently.

### MetricMode (`Models/MetricMode.swift`)

Which metric drives the menu bar icon percentage and color.

| Case | rawValue | label | shortLabel |
|------|----------|-------|------------|
| `.fiveHour` | `"5h"` | `"5-Hour"` | `"5 Hour"` |
| `.sevenDay` | `"7d"` | `"7-Day"` | `"7 Day"` |
| `.contextHealth` | `"context"` | `"Context"` | `"Context"` |

`shortLabel` is a computed property used by the 3-segment picker.

Static: `orderedModes(current:) -> [MetricMode]` — returns all modes with `current` first, remaining in `allCases` order. Shared by `MetricToggleView` and `UsagePopoverView` for cached ordered mode lists.

### TrendDirection (`Models/TrendDirection.swift`)

| Case | Symbol |
|------|--------|
| `.up` | ↑ |
| `.down` | ↓ |
| `.flat` | → |


### APIProfile (`Models/APIProfile.swift`)

Account/workspace info extracted from Anthropic response headers or `client_data` JSON.

| Field | Type |
|-------|------|
| `organizationId` | `String?` |
| `workspaceId` | `String?` |
| `workspaceName` | `String?` |

`parse(headers:)` reads `anthropic-organization-id`, `anthropic-workspace-id`/`anthropic-workspace`, and `anthropic-workspace-name`/`x-workspace-name`. A `parse(clientData:)` overload extracts the same fields from the Claude Code client-data JSON.

### AccountRecord (`Models/AccountRecord.swift`)

Per-account identity record. Stored as JSON array in UserDefaults.

| Field | Type |
|-------|------|
| `id` | `String` — organizationId (or `"pending-<UUID>"` before first API call) |
| `displayName` | `String?` — user-editable label (max 30 chars) |
| `billingType` | `String?` |
| `addedAt` | `Date` |

Computed: `isPendingIdentity: Bool` — true when `id` starts with `"pending-"`

Conforms to `Codable`, `Identifiable`, `Equatable`.

### APIFetchResult (`Models/APIFetchResult.swift`)

Combined result from a single Messages API call.

| Field | Type |
|-------|------|
| `rateLimits` | `RateLimitUsage?` |
| `rateLimitSource` | `RateLimitSource?` — `.oauthUsageEndpoint` (primary), `.anthropicAPIHeaders`, or `.claudeCodeClientData` |
| `standardLimits` | `StandardRateLimits?` — per-minute API limits (fallback when 5h/7d unavailable) |
| `profile` | `APIProfile?` |
| `hasStandardRateLimitHeaders` | `Bool` — true when standard `anthropic-ratelimit-*` headers present |
| `fetchedAt` | `Date` — when this result was fetched (defaults to `Date()`) |
| `isCached` | `Bool` — whether this result came from cache rather than a fresh API response (defaults to `false`) |
| `authError` | `Bool` — true when the API (usage endpoint or Messages probe) has returned ≥ 3 consecutive 401/403 for this account (defaults to `false`). `UsageViewModel.refreshErrorMessage` overrides all other messages with a reconnect prompt when set. |

### StandardRateLimits (`Models/StandardRateLimits.swift`)

Parsed from standard Anthropic API rate limit headers (`anthropic-ratelimit-requests-*`, `anthropic-ratelimit-tokens-*`). Used as a fallback display when unified 5h/7d usage windows are unavailable.

| Field | Type |
|-------|------|
| `requestsLimit` | `Int` |
| `requestsRemaining` | `Int` |
| `requestsReset` | `Date?` |
| `tokensLimit` | `Int` |
| `tokensRemaining` | `Int` |
| `tokensReset` | `Date?` |

Computed: `requestsPercent` (utilization × 100), `tokensPercent`, `isRequestsExhausted`, `isTokensExhausted`.

`parse(headers:)` reads standard headers with case-insensitive key matching. Returns nil only when neither a requests-limit/remaining pair nor a tokens-limit/remaining pair is present (a tokens-only pair is accepted). Accepts ISO 8601 and Unix timestamp formats for reset dates.

### RateLimitUsage (`Models/RateLimitUsage.swift`)

Parsed from Claude Code usage metadata or Anthropic's legacy unified rate limit headers (`anthropic-ratelimit-unified-*`). The app's 5-hour and 7-day bars are specifically Claude Code usage windows, not generic public API request/token limits. Conforms to `Equatable` (used by `UsageAggregator` for redundant aggregation skip).

| Field | Type |
|-------|------|
| `representativeClaim` | `String` — `"five_hour"` or `"seven_day"` |
| `fiveHourUtilization` | `Double` — 0.0–1.0 |
| `fiveHourReset` | `Date?` |
| `fiveHourStatus` | `String` — `"allowed"` or `"throttled"` |
| `sevenDayUtilization` | `Double` |
| `sevenDayReset` | `Date?` |
| `sevenDayStatus` | `String` |
| `overallStatus` | `String` — `"allowed"` or `"throttled"` |

Computed: `requestsPercentUsed` (binding window utilization × 100), `fiveHourPercent`, `sevenDayPercent`, `bindingReset`, `bindingWindowLabel`, `isThrottled` (true if `overallStatus`, `fiveHourStatus`, or `sevenDayStatus` is `"throttled"`), `estimatedTimeToLimit(for window: String) -> TimeInterval?` (burn rate = utilization / elapsed, projects when 100% reached; returns nil if utilization ≤ 20%, elapsed < 60s, or estimate exceeds reset time)

Static: `countdownText(to date: Date, from now: Date = .now) -> String` — compact countdown for menu bar display. Pure function with injectable `now` for testing. Delegates to `DurationFormatter.compact()`. Used by `StatusBarManager` when throttled.

`parse(headers:)` reads legacy unified headers. `parse(clientData:)` reads Claude Code client-data JSON with tolerant key-path matching, accepts percent or fractional utilization, and parses reset timestamps from Unix epoch or ISO-8601/RFC 3339 strings.

**Throttle ≠ 100% utilization.** A window is `"throttled"` only when the API sends an explicit `"throttled"` status, or when a real HTTP 429 forces it via `markedThrottled()` (gated by `quotaThrottleLikely`). Reaching 100% utilization is the **"at capacity"** state, not a throttle — the user can typically keep working. Neither parser synthesizes `"throttled"` from a utilization of ≥ 1.0.

`markedThrottled(bindingWindow:)` forces throttled status on the binding (or named) window — used as an override when an HTTP 429 proves throttling but the headers haven't caught up. Callers must guard with `RateLimitFetcher.quotaThrottleLikely(_:)` so a non-quota 429 (per-minute, IP block, upstream incident) does not falsely flip the bar to `Throttled`.

`withClearedExpiredWindows(now:)` returns a copy normalizing two kinds of stale state: (1) any window whose `reset` is in the past → utilization `0`, reset `nil`, status `"allowed"` (rolled over); and (2) an **unbounded throttle** — a window with status `"throttled"` but *no* reset → status `"allowed"` (utilization kept). A genuine quota throttle always carries a reset, so a reset-less throttle can never be aged out by (1) and would otherwise stick forever on the stale/cache path; dropping the flag stops the bar from falsely claiming "Throttled". If the binding window is cleared by either rule, `overallStatus` is reset too. Applied at three call sites: cache restore (`RateLimitFetcher.restorePersistedRateLimits`), runtime cache hit (`RateLimitFetcher.cachedOrEmpty`), and the snapshot stale-fallback path (`UsageViewModel.effectiveRateLimits`). Without all three, the menu bar can render `100%` + broken star for hours after a window has reset, because Anthropic returns unified headers on only ~10% of polls and the snapshot reuses stale `rateLimits` for up to 24h.

`withClearedRolloverArtifacts(now:)` handles the *opposite* boundary case — a window that just rolled over but whose **fresh** reading is stale. At a reset boundary the `/api/oauth/usage` endpoint can briefly return the previous window's near-full utilization paired with the *new* window's reset (server-side eventual consistency). Because the reset is in the future, `withClearedExpiredWindows` can't catch it, and it arrives as fresh (not cached) data so the cache-path normalization never runs. For each window, if utilization ≥ `rolloverArtifactUtilizationThreshold` (0.95) **and** the window started less than `rolloverArtifactGracePeriod` (10 min) ago — derived as `windowDuration − (reset − now)` — the utilization is zeroed and status set to `"allowed"`, **keeping** the new reset so the countdown keeps running (unlike `withClearedExpiredWindows`, which nils it). If the binding window is the artifact, `overallStatus` clears too. Applied to the displayed rate limits in `UsageViewModel.refresh()` (active account), `UsageViewModel.fetchAllAccounts` (multi-account fan-out), the **wake / cold-start instant-paint** (`UsageViewModel+Lifecycle.swift` wake observer and `refresh()`'s empty-snapshot pre-fetch paint), and **launch restore** (`RateLimitFetcher.restorePersistedRateLimits`, chained after `withClearedExpiredWindows`) so a just-rolled near-full reading is never seeded into the snapshot as the stale 24h fallback. A suppression emits an `AppLogger.network.notice` (persisted) with the raw → corrected values; every fresh poll also emits an `.info` line with the raw server reading for live diagnosis. Genuine end-of-window limit-hits (near-full with the window nearly elapsed) are preserved — only the impossible "near-full on a minutes-old window" combination is suppressed.

### TokenHealthStatus (`Models/TokenHealthStatus.swift`) — `Identifiable`

| Field | Type |
|-------|------|
| `id` | `String` (sessionId) |
| `band` | `HealthBand` (.green, .orange, .red, .unknown) |
| `usagePercentage` | `Double` |
| `totalUsed` | `Int` |
| `contextWindow` | `Int` |
| `usableWindow` | `Int` — contextWindow × `usableContextRatio` (currently 1.0 = full window) |
| `remainingTokens` | `Int` — usableWindow - totalUsed |
| `inputTokens` | `Int` |
| `outputTokens` | `Int` |
| `cacheReadTokens` | `Int` |
| `cacheWriteTokens` | `Int` |
| `model` | `String` |
| `turnCount` | `Int` |
| `warnings` | `[HealthWarning]` |
| `tokensPerMinute` | `Double?` |
| `projectName` | `String?` — last path component of cwd |
| `gitBranch` | `String?` — from session entry metadata |
| `sessionStart` | `Date?` — first entry timestamp |
| `sessionDuration` | `TimeInterval?` — last - first entry |
| `lastActivity` | `Date?` — timestamp of most recent entry in session |

Static: `empty` — zero-value placeholder for defensive code paths (empty sessions guard in `TokenHealthSection`).

Computed: `suggestedAction` — nil for green/unknown, recommendation text for orange/red.

### HealthWarning

`id: UUID`, `severity: WarningSeverity` (.info, .mild, .strong), `message: String`, `suggestion: String?`

### TokenHealthConfig (`Models/TokenHealthConfig.swift`)

Instance properties with defaults: `greenThreshold = 60.0`, `redThreshold = 80.0`, `turnCountMild = 15`, `turnCountStrong = 25`, `inputOutputRatioThreshold = 20.0`, `staleSessionMinutes = 30`, `zeroOutputTurnThreshold = 3`, `rapidConsumptionSeconds = 60`, `rapidConsumptionTokens = 50_000`, `velocityMinDuration: TimeInterval = 60`

Static: `contextWindows: [String: Int]` dictionary (Claude 4.x = 1M, Claude 3.x = 200K), `defaultContextWindow = 1_000_000`, `usableContextRatio = 1.0` (full window — 1M context makes the whole window usable; no compaction reservation), `contextWindow(for model:) -> Int` (exact match → pre-computed prefix lookup via `prefixLookup` dictionary, built once at load time from 3-part prefixes of `contextWindows` keys).

**Bidirectional auto-detect from usage**: `TokenHealthMonitor.assess()` adjusts `contextWindow` in both directions based on observed token usage (tiers: 200K, 500K, 1M, 2M, 5M):
- **Upward**: if observed tokens exceed the hardcoded window, bumps to the next tier above observed. Prevents inflated percentages when Anthropic expands context windows upstream.
- **Downward**: if observed tokens fall below the next-lower tier boundary, downgrades to the smallest tier that still fits. Anti-thrash guard: only downgrades when `observedTokens < lowerTier` (e.g. 600K observed on a 1M window stays at 1M because 600K ≥ 500K — the next-lower tier boundary). This prevents false downgrade on early or small sessions within a large window.

Thresholds apply to the **usable window**, which currently equals the full context window (`usableContextRatio = 1.0`). Percentages are calculated against the full window.

### StatsCache (`Models/StatsCache.swift`)

Codable struct matching `~/.claude/stats-cache.json`:
- `version`, `lastComputedDate`
- `dailyActivity: [DailyActivity]` — date, messageCount, sessionCount, toolCallCount. `DailyActivity` has `private static let dateFormatter` for `parsedDate` computed property. Conforms to `Codable`, `Identifiable`, `Equatable`.
- `dailyModelTokens: [DailyModelTokens]` — date, tokensByModel: `[String: Int]` (model ID → token count)
- `modelUsage: [String: ModelUsageEntry]` — total per-model usage (includes `webSearchRequests?`, `contextWindow?`, `maxOutputTokens?`)
- `totalSessions`, `totalMessages`
- `longestSession: LongestSession?` — sessionId, duration (ms), messageCount, timestamp
- `hourCounts: [String: Int]` — message counts per hour of day (from stats-cache)
- `firstSessionDate: String?`
- `totalSpeculationTimeSavedMs: Int?`

### SessionEntry (`Models/SessionEntry.swift`)

JSONL line schema (Codable):
- `type`, `timestamp`, `sessionId`, `uuid` — all `String?`
- `cwd: String?`, `gitBranch: String?`
- `message: SessionMessage?` — contains `role`, `model`, `usage: TokenUsage?`, `id: String?`, `content: [ContentBlock]?`
- `ContentBlock` (nested struct, minimal decoding): `type: String?` — only the type field is decoded (sufficient for counting `tool_use` blocks without parsing id/name/input)
- `TokenUsage` includes `service_tier: String?` alongside the four token count fields

`AssistantUsageEntry` (processed form): `timestamp: Date`, `model: String`, `messageId: String`, `inputTokens/outputTokens/cacheReadTokens/cacheWriteTokens: Int`, `sessionId: String`, `cwd: String?`, `gitBranch: String?`, `toolCallCount: Int` (computed as `content?.filter { $0.type == "tool_use" }.count ?? 0`)

### ModelPricing (`Models/ModelPricing.swift`)

Per-model pricing for API cost equivalence. Shows what the same token usage would cost at Anthropic's published API per-token rates — Pro/Max/Teams subscribers aren't billed per-token.

| Field | Type |
|-------|------|
| `inputPerMillion` | `Double` |
| `outputPerMillion` | `Double` |
| `cacheWritePerMillion` | `Double` |
| `cacheReadPerMillion` | `Double` |

Methods:
- `cost(input:output:cacheRead:cacheWrite:) -> Double` — cost in dollars
- `static formatCost(_ cost: Double) -> String` — "$12.35" or "<$0.01"
- `static formatCompactCost(_ cost: Double) -> String` — "$12" (drops cents for >= $1), "$0.75" (keeps precision < $1), "$0" for zero
- `static pricing(for modelId: String) -> ModelPricing?` — lookup via `ModelNameMapper.displayName`, cached in `private static var pricingCache: [String: ModelPricing?]` to avoid repeated lookups
- `static totalCost(for models: [ModelTokenSummary]) -> Double` — aggregate across models

Pricing table (per million tokens):

| Model | Input | Output | Cache Write | Cache Read |
|-------|-------|--------|-------------|------------|
| Opus 4 | $15 | $75 | $18.75 | $1.50 |
| Sonnet 4 | $3 | $15 | $3.75 | $0.30 |
| Haiku 4 | $0.80 | $4 | $1.00 | $0.08 |
| Sonnet 3.5 | $3 | $15 | $3.75 | $0.30 |
| Haiku 3.5 | $0.80 | $4 | $1.00 | $0.08 |
| Opus 3 | $15 | $75 | $18.75 | $1.50 |

### LocalUsageEstimate (`Models/LocalUsageEstimate.swift`)

Fallback estimation when Anthropic's unified rate limit headers are unavailable. `@MainActor` enum (no instances).

**Calibration**: when the API returns both utilization and local token counts are available, derives the window's token limit (`limit = localTokens / utilization`) and persists to UserDefaults. Subsequent polls compute percentages locally. Only calibrates when utilization is inside the **20–80%** band (`calibrationBand`) and the derived limit exceeds 100K tokens. The edges are excluded because dividing by a small utilization magnifies measurement error (a 1% error at 5% utilization → ~20% error in the derived limit), which would let the local fallback read ≥100% when the API would report well under.

**Per-account scoping**: all calibration state is keyed per account (`{base}_{accountId}`) — with mixed plan tiers, one account's calibration must not misprice another's estimates. Every accessor takes `accountId: String?` defaulting to `AccountStore.persistedActiveAccountId` (the persisted active-account ID, readable off-MainActor), so UI read paths — which always render the active account — need no changes. A nil account (signed out) falls back to the legacy global keys.

| Static accessor | Type | Notes |
|-----------------|------|-------|
| `fiveHourLimit(for:)` / `setFiveHourLimit(_:for:)` | `Int` | Calibrated 5h token limit (0 = uncalibrated). `nonisolated` — UserDefaults is thread-safe |
| `sevenDayLimit(for:)` / `setSevenDayLimit(_:for:)` | `Int` | Calibrated 7d token limit (0 = uncalibrated). `nonisolated` |
| `calibratedAt(for:)` | `Date?` | When the account's limits were last calibrated |
| `isCalibrated(for:)` | `Bool` | `nonisolated` — true when either limit > 0 |
| `effectiveFiveHourLimit(for:)` | `Int?` | Fallback chain: calibrated > `PlanTier.effective(forAccountId:)` > nil |
| `effectiveSevenDayLimit(for:)` | `Int?` | Fallback chain: calibrated > `PlanTier.effective(forAccountId:)` > nil |
| `latestFiveHourTokens` | `Int` | Updated each refresh cycle for 429 calibration snapshot (active account's counts) |
| `latestSevenDayTokens` | `Int` | Updated each refresh cycle for 429 calibration snapshot (active account's counts) |

Methods:
- `migrateIfNeeded(activeAccountId:defaults:)` — clears stale pre-v2 calibrations (before cache-inclusive counting), then one-time-moves the legacy global calibration keys to the active account (`aibattery_calibration_perAccount_migrated` flag; only marks done when an account exists, else retries next launch). Called once at launch.
- `calibrate(fiveHourUtilization:sevenDayUtilization:localFiveHourTokens:localSevenDayTokens:accountId:)` — derives limits from API utilization + local counts; `UsageViewModel.refresh()` passes the poll's captured account ID
- `calibrateFrom429(accountId:activeAccountId:)` — when a 429 is received without headers, uses current local token count as the limit (with 95% buffer). **Only seeds the active account**: `latest*Tokens` hold the active account's local counts, so a fan-out 429 for another account is ignored
- `fiveHourPercent(tokens:accountId:) -> Double?` — 0–100, nil if no limit known. `nonisolated`
- `sevenDayPercent(tokens:accountId:) -> Double?` — 0–100, nil if no limit known. `nonisolated`
- `limitSource(for:accountId:) -> LimitSource?` — `.calibrated` or `.planEstimate` or nil
- `setManualFiveHourLimit(_:for:)` / `setManualSevenDayLimit(_:for:)` — user overrides

Nested: `LimitSource` enum (`.calibrated`, `.planEstimate`)

### PlanTier (`Models/PlanTier.swift`)

Claude subscription plan tiers with estimated 5h/7d token limits. Community-derived estimates — auto-calibrated when a 429 is detected.

| Case | rawValue | displayName | estimated5hLimit | estimated7dLimit |
|------|----------|-------------|------------------|------------------|
| `.pro` | `"pro"` | `"Pro"` | 7M | 35M |
| `.max5x` | `"max5x"` | `"Max 5×"` | 35M | 175M |
| `.max20x` | `"max20x"` | `"Max 20×"` | 140M | 700M |
| `.team` | `"team"` | `"Team"` | 10M | 50M |

Static: `current: PlanTier?` — the user-selected global tier, persisted to UserDefaults (`UserDefaultsKeys.planTier`).

`init?(billingType:)` — maps an account's API-reported `billingType` string to a tier (lowercased, separators stripped; `"pro"`, `"max5x"`, `"max20x"`, `"team"`/`"teams"`; anything unrecognized → nil rather than guessing).

`effective(forAccountId:defaults:)` — the tier for a specific account's estimates: the account's `billingType` when it maps to a known tier, else `current`. Reads the persisted `AccountRecord` JSON directly (`UserDefaultsKeys.accounts`) so nonisolated estimate paths don't cross into the `@MainActor` `AccountStore`.

Conforms to `CaseIterable`, `Codable`.

### RateLimitSource (`Models/RateLimitSource.swift`)

Describes where displayed rate-limit values came from. `Equatable`, `Codable`.

| Case | shortLabel | Explanation |
|------|-----------|-------------|
| `.oauthUsageEndpoint` | `"Via Anthropic API"` | OAuth usage endpoint |
| `.claudeCodeClientData` | `"Via Claude Code"` | Claude Code account metadata |
| `.anthropicAPIHeaders` | `"Via Anthropic API"` | Anthropic API response headers |

### ClaudeSystemStatus + StatusIndicator (`Models/ClaudeSystemStatus.swift`)

`ClaudeSystemStatus`: `indicator: StatusIndicator`, `description: String`, `incidentNames: [String]`, `statusPageURL: String`, `componentStatuses: [String: StatusIndicator]` (keyed by Statuspage component ID, default empty). Computed: `incidentName: String?` (first incident, convenience accessor).

`StatusComponent`: `id: String`, `name: String`, `alertKey: String`. Catalog: `StatusChecker.knownComponents` (5 entries: claude.ai, Console, Claude API, Claude Code, Claude for Gov).

`StatusIndicator`: enum with cases `.operational`, `.degradedPerformance`, `.partialOutage`, `.majorOutage`, `.maintenance`, `.unknown`. Has `severity: Int` for comparison (higher = worse). `from(_:)` maps Statuspage API strings to cases — notably `"elevated"` maps to `.degradedPerformance` (yellow). Also used to parse incident impact strings (`"none"`, `"minor"`, `"major"`, `"critical"`).

## Services

### OAuthManager (`Services/OAuthManager.swift`)
- Singleton: `.shared`, `@MainActor ObservableObject`
- Published: `isAuthenticated: Bool`, `accountStore: AccountStore`
- OAuth 2.0 PKCE flow with Anthropic (same protocol as Claude Code)
- Client ID: `9d1c250a-e61b-44d9-88ed-5944d1962f5e`
- Auth URL: `https://claude.ai/oauth/authorize`
- Token URL: `https://console.anthropic.com/v1/oauth/token`
- Scopes: `org:create_api_key user:profile user:inference`
- **Multi-account**: supports up to 3 accounts (separate Claude orgs). Each account's refresh token stored in Keychain (`refreshToken_{accountId}`); access token held in memory only (re-derived from refresh on launch); expiry timestamp in UserDefaults (`aibattery_expiresAt_{accountId}`). `AccountStore` tracks known accounts; `activeAccountId` drives which one polls. New accounts get a temporary `"pending-<UUID>"` ID until the first API call returns the real `anthropic-organization-id`.
- `startAuthFlow(addingAccount:)` → opens browser with PKCE challenge. `addingAccount` flag tracks whether this is an additional-account flow. Generates a separate random `state` parameter (never reuses the PKCE verifier).
- `exchangeCode(_:) -> Result<Void, AuthError>` → exchanges auth code for access + refresh tokens. Creates `AccountRecord` with pending ID, stores refresh token in Keychain and expiry in UserDefaults (access token stays in memory). Validates state parameter (CSRF protection). Only clears PKCE state on success.
- `getAccessToken()` → returns active account's valid token, refreshes 5 minutes before expiry. `getAccessToken(for:)` for specific account. Serializes concurrent refresh attempts per account via `refreshTasks` dictionary.
- `resolveAccountIdentity(tempId:realOrgId:billingType:)` → called after first API call returns real org ID. Moves `refreshToken_{tempId}` → `refreshToken_{realOrgId}` in Keychain and `aibattery_expiresAt_` key in UserDefaults. Updates AccountStore. Migrates **both** the token ledger (`TokenLedger.migrate`) **and** the rate-limit cache (`RateLimitFetcher.migrate`) from the pending id to the real org id, so neither orphans under the dead `pending-<uuid>` key. (A pending account's *first* fetch persists a rate-limit blob under `pending-<uuid>`; if left behind it reloads into the cache every launch and a stale `"throttled"`/100% reading could surface a false "Limit reached" on the resolved account — the v2.5.0 bug.) Idempotent. Handles duplicate detection (same org authed twice → merge, keep newer tokens).
- `pruneOrphanedLedgerAccounts()` (launch-only, never called from `init`) prunes **both** the token ledger and the rate-limit cache via `pruneAccounts(keeping: liveAccountIds)` — dropping in-memory entries and persisted `aibattery_rateLimits_*` keys for accounts the user no longer has. Both prunes no-op on an empty live set so a logged-out / fresh-launch transient can't wipe held state.
- `updateAccountMetadata(accountId:displayName:billingType:)` → updates existing account's display name and/or billing type in AccountStore.
- `signOut(accountId:)` → removes specific account (or active if nil), auto-switches to remaining account if any.
- **Legacy migration**: `migrateFromLegacy()` on init — detects old unprefixed Keychain entries, creates AccountRecord with temp ID, copies refresh token to prefixed format (verify-before-delete: the new entry is read back and compared before legacy entries are removed; on write failure the legacy entries are kept and migration retries next launch), moves expiresAt to UserDefaults, deletes old entries. Runs only when accounts array is empty.
- **Stale item migration**: `migrateStaleKeychainItems()` on init — removes legacy `accessToken_*` and `expiresAt_*` entries from Keychain (no longer stored there), moves expiresAt values to UserDefaults if not already present.
- **Keychain accessibility migration**: `migrateKeychainAccessibility()` on init — one-time migration from `kSecAttrAccessibleWhenUnlocked` to `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. Prevents iCloud Keychain from syncing refresh tokens to other Apple devices. Deletes and re-adds each item (Keychain doesn't support updating `kSecAttrAccessible` in-place). Hardened against token loss: each re-add is verified by reading the value back (`setAndVerify`), retried once on failure, and the `aibattery_keychainThisDeviceOnlyMigrated` flag is only set when EVERY account verified — a failed item leaves the flag unset so the next launch retries instead of silently signing the user out. `KeychainHelper.set` returns `@discardableResult Bool` so delete-then-set callers can detect a failed write.
- **Per-account storage**: `saveTokens(for:)`, `loadTokens(for:)`, `deleteTokens(for:)` — refresh token in Keychain under `"refreshToken_{accountId}"`, service `"AIBattery"`; expiry in UserDefaults; access token in memory only.
- `AuthError` enum: `.noVerifier`, `.invalidCode`, `.expired`, `.networkError`, `.serverError(Int)`, `.maxAccountsReached`, `.unknownError(String)` — each has `userMessage` for display. `isTransient` for `.networkError`/`.serverError`.
- **Token endpoint retry**: `postToken(body:transport:retryPolicy:)` retries up to 2 times with exponential backoff (1s, 2s) with jitter on 429 and 5xx. Parses `Retry-After` header on 429 when present. Non-retryable errors fail immediately. `transport` (defaults to `SecureNetworking.data(for:)`) and `retryPolicy` (defaults to `.oauth`) are injectable — tests pin the retry contract (exactly `maxRetries + 1 == 3` attempts; 5xx→`.serverError`, timeout→`.networkError`, 401→immediate `.invalidCode`, `invalid_grant`→`.expired`, malformed-200→retry) via a scripted transport and a zero-delay policy instead of URLProtocol stubs (global/racy under parallel Swift Testing suites).
- **Refresh resilience**: transient errors during refresh do NOT mark `isAuthenticated = false`. Only auth errors trigger logout.

### AccountStore (`Services/AccountStore.swift`)
- `@MainActor ObservableObject`, owned by `OAuthManager`
- Published: `accounts: [AccountRecord]`, `activeAccountId: String?`
- Computed: `activeAccount`, `canAddAccount` (< maxAccounts)
- `add(_:)` — appends record, sets as active if first, rejects duplicates and over-max
- `remove(id:)` — removes account, auto-switches active to remaining
- `setActive(id:)` — changes active account (no-op for unknown IDs)
- `update(oldId:with:)` — replaces account record, handles identity resolution (pending → real org ID). Detects and merges duplicates (same org authed twice): preserves earliest `addedAt`, keeps existing `displayName`/`billingType` when new record has nil. Handles index ordering correctly when removing the old entry.
- Persistence: JSON-encoded `[AccountRecord]` to `UserDefaults(aibattery_accounts)` + `activeAccountId` string to `UserDefaults(aibattery_activeAccountId)`
- Load on init: fixes dangling `activeAccountId` pointing at removed accounts
- `nonisolated static let maxAccounts = 3`

### RateLimitFetcher (`Services/RateLimitFetcher.swift`)
- Singleton: `.shared`
- `fetch(accessToken:accountId:) async -> APIFetchResult` — returns Claude Code usage windows plus account/profile metadata when available
- **Primary endpoint**: `GET /api/oauth/usage` (`fetchUsageEndpoint`) — dedicated usage endpoint, no model probe needed; first call every cycle. Returns a `UsageEndpointOutcome`: `.success(APIFetchResult)`, `.authFailed` (401/403 — counts toward `consecutiveAuthFailures` and **skips the Messages probe entirely**, since probing with the same dead token would only produce a second 401), or `.unavailable` (server error / unparseable body / transport failure — fall through to the probe).
- **Fallback**: `POST /v1/messages?beta=true` with `max_tokens: 1`, content `"."` (unified-header probe, ~10% hit rate). `GET /api/oauth/claude_cli/client_data` is a nested fallback invoked only inside the Messages-probe paths.
- **Dynamic probe order** (deduped): `activeUserModel` (from latest JSONL entry) → `lastWorkingModel[accountId]` (persisted per account) → `observedModels` (JSONL-observed models, most recent first) → `ultimateFallback` (single newest Sonnet for fresh installs). Self-heals when Anthropic deprecates model IDs — no hardcoded list.
- `observedModels: [String]` — dynamic list populated by `UsageAggregator.setObservedModels(_:accountId:)` after each aggregation cycle; persisted to UserDefaults under `aibattery_observedModels_{accountId}`. Restored on launch (best-effort, overwritten on first aggregation).
- `static let ultimateFallback = "claude-sonnet-4-6-20250929"` — single model for fresh installs with no JSONL data.
- `setObservedModels(_ models: [String], accountId: String)` — updates `observedModels` and persists to UserDefaults. Called by `UsageAggregator`.
- `restoreWorkingModels()` — restores `lastWorkingModel` dictionary and `observedModels` from UserDefaults on init.
- `saveWorkingModel` records the working model on every response with parseable headers. The 200-OK model is saved by the caller `fetch()` (not inside `tryFetch`); the 429+headers, retry-after, and 400/404 paths save via `buildHeaderResult`, plus explicit saves on the 429-no-data and 5xx-retry paths.
- **`buildHeaderResult` helper**: builds an `APIFetchResult` from parsed rate limit headers with `.anthropicAPIHeaders` source. Saves working model, applies optional throttle marking. Used by 429, retry-after, and 400/404 code paths in `tryFetch`.
- Headers: `Authorization: Bearer {token}`, `anthropic-version: 2023-06-01`, `anthropic-beta: oauth-2025-04-20,interleaved-thinking-2025-05-14`, `User-Agent: AIBattery/{version} (macOS)` (dynamic from bundle)
- Caller provides token and account ID. Per-account caching: `cachedResults: [String: APIFetchResult]` and `lastWorkingModel: [String: String]` keyed by account ID.
- Timeout: 15 sec
- Parses Claude Code 5-hour / 7-day usage from the `/api/oauth/usage` endpoint first, then `client_data`, then `anthropic-ratelimit-unified-*` response headers when present. Detects standard public `anthropic-ratelimit-*` headers for diagnostics but does not map them onto the 5-hour / 7-day UI.
- `APIProfile` parsing accepts org/workspace metadata from headers or `client_data` JSON.
- Logs a warning when no Claude Code-compatible usage data is found in a successful response (lists any `ratelimit`-containing header names for debugging)
- Caches last successful `APIFetchResult`; returns cached on network error or auth failure (with `isCached: true`, preserving original `fetchedAt`). Cache never expires — stale rate limits are shown rather than empty bars (e.g., after long sleep). Fresh fetches replace stale data on success.
- Model unavailable (400/404 with model/access error message) → tries next model in list
- **429 handling**: parses rate limit headers directly from the 429 response (they're always present on throttled responses). Returns as success so the UI continues showing usage bars and reset times while the user is rate limited. Falls through to Retry-After logic only if headers are missing (unexpected).
- **`quotaThrottleLikely(_:)`** (`nonisolated static`) — gates whether a 429 should call `markedThrottled()` on the parsed headers. Returns `true` when the parsed `RateLimitUsage.isThrottled` is already set OR the binding window utilization is ≥ `quotaExhaustionThreshold` (0.95). Below that, headers reporting `"allowed"` are trusted and the 429 is presumed upstream / per-minute / IP-block — the bar must not flip to `Throttled`.
- **Consecutive auth-failure tracking** — `consecutiveAuthFailures: [String: Int]` keyed by account. Incremented on each 401/403 from **either path** (usage endpoint or Messages probe) via the shared `registerAuthFailure(accountId:path:)` helper, reset on any successful result (both paths). At or above `authErrorThreshold` (3) the returned `APIFetchResult.authError = true`. Network errors do NOT count as auth failures and do NOT reset the counter (a flaky network shouldn't trigger reconnect prompts but also shouldn't mask a persistent auth problem).
- **`restorePersistedRateLimits(defaults:)`** applies `RateLimitUsage.withClearedExpiredWindows().withClearedRolloverArtifacts()` so neither a stale `"throttled"` flag from before a long absence nor a just-rolled near-full reading displays (or is seeded as the 24h stale fallback) until the first fresh fetch lands. `withClearedExpiredWindows` also fires in **`cachedOrEmpty(accountId:)`** for the runtime cache hit (wake from sleep, offline, cold start). Self-heals corrupt persisted blobs (undecodable entry → removed from defaults, other accounts unaffected) and clamps future `fetchedAt` timestamps to now (system clock went backward). `defaults` is injectable for tests (as is `persistRateLimits(_:accountId:defaults:)`), defaulting to `.standard`.
- **`migrate(from:to:defaults:)`** and **`pruneAccounts(keeping:defaults:)`** mirror the `TokenLedger` lifecycle for the rate-limit cache (in-memory `cachedResults` + persisted `aibattery_rateLimits_*` blobs). `migrate` moves a `pending-<uuid>`'s entry to its resolved org id (the resolved id wins if a fresh fetch already landed there; the pending key is always dropped), called from `OAuthManager.resolveAccountIdentity`. `pruneAccounts` drops entries for non-live accounts, called from `OAuthManager.pruneOrphanedLedgerAccounts` on launch; no-op on an empty live set. Together these stop an orphaned pending blob (a high `"throttled"`/100% first-fetch reading) from lingering in the cache and surfacing a false "Limit reached" on the resolved account. `defaults` injectable for tests.
- **Pure response interpreters**: `interpretUsageEndpoint(statusCode:data:headers:cachedProfile:) -> UsageEndpointOutcome` (in `RateLimitFetcher+UsageEndpoint.swift`) and `interpretClaudeCodeClientData(statusCode:data:headers:cachedProfile:callerStandardLimits:) -> APIFetchResult?` (in `RateLimitFetcher+ClientData.swift`) are `nonisolated static` pure functions that own the status-code / payload / 429-throttle contract for both OAuth endpoints. The async `fetchUsageEndpoint` / `fetchClaudeCodeClientData` wrappers (same files) do the HTTP call + diagnostic logging and delegate interpretation. Allows contract testing of every payload shape and status-code combination without mocking URLSession.
- Non-model 400/404 errors: extracts rate limit headers if present and returns as success; otherwise returns `.networkError` (never silently falls through to header-less success)
- `static parseRetryAfter(_ value: String?, maxDelay: Double = 30) -> Double?` — parses `Retry-After` header; returns nil for nil/non-numeric/zero/negative; caps at `maxDelay`

### StatusChecker (`Services/StatusChecker.swift`)
- Singleton: `.shared`
- `fetchStatus() async -> ClaudeSystemStatus`
- GET `https://status.claude.com/api/v2/summary.json`
- Timeout: 5 sec
- `knownComponents: [StatusComponent]` catalog of all 5 tracked components (claude.ai, Console, Claude API, Claude Code, Claude for Gov)
- Uses ALL API-returned components for worst-status calculation (no filter)
- Populates `componentStatuses: [String: StatusIndicator]` dictionary keyed by component ID
- **Incident impact escalation**: when components report "operational" but active incidents exist, factors in incident `impact` field (`"none"`, `"minor"`, `"major"`, `"critical"`) to determine overall indicator. If impact is `"none"` but incidents are active, escalates to at least `.degradedPerformance` (yellow dot).
- Checks for active incidents (status not `resolved` or `postmortem`)
- Returns `.unknown` on any error
- **Backoff**: exponential backoff with jitter on failure — base 60s doubles per failure, capped at 5 min, ±20% jitter to prevent thundering herd; stored once per failure increment (not re-randomized on every check); resets on success

### StatsCacheReader (`Services/StatsCacheReader.swift`)
- `@MainActor`, Singleton: `.shared`
- `read() -> StatsCache?`
- Reads and JSON-decodes `~/.claude/stats-cache.json`
- **Static decoder**: `private static let jsonDecoder = JSONDecoder()` — shared instance avoids per-read allocation
- **Result caching**: caches decoded `StatsCache` with file modification date and size; skips re-decode when file unchanged. `invalidate()` clears cache (called by FileWatcher on change).
- **File size guard**: `maxFileSize = 10_000_000` (10 MB). Rejects files exceeding this before `Data(contentsOf:)` — stats-cache.json is typically a few KB; anything larger suggests a symlink to a large file or runaway writer. Guard checked in both stat-based and fallback code paths.
- `lastModificationDate: Date?` — exposes cached file modification date (read-only). Used by `UsageAggregator` as a fingerprint component for redundant aggregation skip.

### SessionLogReader (`Services/SessionLogReader.swift`)
- NOT `@MainActor` (file I/O must not block UI), Singleton: `.shared`, `@unchecked Sendable` + NSLock
- `readAllUsageEntries() -> [AssistantUsageEntry]`
- Discovers JSONL by recursively enumerating each `~/.claude/projects/*` directory for `.jsonl` files (subagent files under `*/subagents/` are picked up by the recursion, not a dedicated glob).
- **Non-Claude-Code directory filter**: decodes the encoded project-dir name back to a path and skips it when any path component is dot-prefixed (hidden, e.g. `.claude-mem`). Filters out MCP observer sessions and other tools that write JSONL to `~/.claude/projects/`.
- FileHandle streaming: 64KB buffer, line-by-line, 1MB max line size safety cap (discards oversized lines)
- **Static members** (avoid per-file allocation): `isoFormatter: ISO8601DateFormatter`, `assistantMarkers: [Data]` (both `"type":"assistant"` and `"type": "assistant"` with space), `usageMarker: Data`, `jsonDecoder: JSONDecoder`
- Pre-filter: byte search for either assistant marker variant AND `"usage"` before JSON decode
- **Decode error logging**: when pre-filter matches but JSON decode fails, logs via `AppLogger.files.debug` with filename and error description
- **Trailing line safety**: remaining data after last newline is only processed if it ends with `}` (skips incomplete/partial writes still being written)
- **Per-file fingerprint cache**: `FileCacheEntry` stores `modDate`, `fileSize`, nullable `entries`, and `messageIds`. Fingerprint (modDate + fileSize) determines whether a file needs re-parsing. After merge into `cachedAllEntries`, raw entry arrays are released (set to nil) for files not modified today — only fingerprints and messageIds retained.
- **Result-level caching**: `cachedAllEntries` is the authoritative merged array. Preserved across invalidations for incremental rebuilds — only changed files are re-parsed and merged in. Stale entries from deleted/changed files are removed via tracked messageIds.
- **Symlink boundary check**: after discovery, resolves symlinks on each file URL and filters out any that resolve outside `~/.claude/projects/`. Prevents a symlink inside the projects directory from reading arbitrary files on disk.
- **Discovery caching**: per-directory file lists (`discoveredFilesByDir`) with parent directory modification dates AND a TTL (`discoveryTTL = 60s`). Unchanged directories skip enumeration entirely. `lastFullEnumerationDate` tracks when the last full scan occurred. `expireDiscoveryTTLForTesting()` test hook forces TTL expiry.
- **Memory eviction**: after successful merge into `cachedAllEntries`, `evictOldFileEntries()` nils out entry arrays for files with modDate before today. Eliminates double-storage between per-file cache and merged result. On dirty rebuild, evicted files with unchanged fingerprint are skipped (entries already in `cachedAllEntries`).
- Deduplication by messageId across all files (set-based). Fallback messageId uses a stable composite key (`sessionId:timestamp:inputTokens:outputTokens`) from entry fields — survives cache eviction without inflating counts
- Sorted by timestamp ascending
- **Entry construction**: `makeUsageEntry(from:)` static helper extracts `AssistantUsageEntry` from decoded `SessionEntry` — shared between main line loop and trailing-data handler (DRY)
- **Corruption tracking**: `lastCorruptLineCount` (public getter) counts decode failures and oversized line skips per `readAllUsageEntries()` call; reset at start of each call (before cache check) to avoid stale values on cache hits

### UsageAggregator (`Services/UsageAggregator.swift`)
- `@unchecked Sendable` + NSLock, created per-ViewModel (not singleton)
- **Static formatters**: `private static let dateFormatter: DateFormatter` and `isoFormatter: ISO8601DateFormatter` — created once at load time
- **Time window constants**: `fiveHourWindow` (18,000s), `sevenDayWindow` (604,800s — rolling 7×86400 for rate-limit token count, mirrors Anthropic's sliding-window quota), `twentyFourHourWindow` (86,400s), `fiveHourBucketCount` (20), `bucketDuration` (900s). The aggregator computes two distinct 7-day cutoffs: `sevenDayRateLimitCutoff` (rolling, drives `sevenDayTokens`) and `sevenDaysAgo` (calendar-day, drives `weekTokenMap` UI breakdown).
- **Injectable `now`**: `aggregate(...)` accepts `now: Date = Date()`. Production callers use the default; tests pin window-boundary behavior with deterministic timestamps independent of wall-clock time of day.
- **TokenMap typealias**: `private typealias TokenMap = [String: (input: Int, output: Int, cacheRead: Int, cacheWrite: Int)]` — class-level type used by accumulator methods and `buildModelTokens`
- **`accumulate(into:key:entry:)`** and **`accumulate(into:key:tokens:)`**: static helpers for per-model token accumulation — replaces 9 inline patterns in the single-pass loop and post-loop merge
- `aggregate(rateLimits:accountId:) -> UsageSnapshot`
- **Redundant aggregation skip**: tracks a lightweight fingerprint (stats-cache modification date, rate limits via `Equatable`, standard limits via `Equatable`, rate limit source, idle session minutes setting, account ID). Returns cached `UsageSnapshot` when all fingerprint components match — avoids rebuilding the entire snapshot during idle periods.
- **Single-pass filtering**: iterates all entries once to extract today's entries (avoids separate `.filter()` passes)
- Reads: stats cache, all JSONL entries (single scan)
- **Token aggregation**: always all-time mode — stats-cache `modelUsage` + uncached JSONL, anti-double-counting for dates already in stats cache. All models from `modelUsage` are shown (no recency filter) so totals match the Anthropic dashboard.
- **Non-Claude model filter**: excludes model IDs that don't start with `"claude-"` (e.g. `"synthetic"`)
- **Token ledger merge**: after `buildModelTokens`, merges with `TokenLedger.shared.merge()` when `accountId` is non-nil. Preserves high-water marks and restores historical models lost from stats-cache. Skipped when unauthenticated (nil account).
- **`buildModelTokens` helper**: private static method that filters non-Claude models, maps to `ModelTokenSummary`, and sorts by `totalTokens` descending
- **`buildProjectTokens` helper**: private static method that groups all JSONL entries by full `cwd` path (nil/empty → "Other"), accumulates 4 token types per project, computes cost per entry via `ModelPricing.pricing(for:)`, and returns `[ProjectTokenSummary]` sorted by `totalTokens` descending. Display name uses `lastPathComponent` of the cwd. Filters non-Claude models. Project data is JSONL-only (stats-cache lacks per-entry cwd).
- **All-dates daily activity merge**: groups all JSONL entries by date via `entriesByDate` dictionary, then merges every date into `dailyActivity` (not just today). This fills gaps between a stale stats-cache rebuild date and the present. If JSONL has more messages for a date than the cache entry, replaces it; if no entry exists, appends one. Preserves the higher of JSONL or cache tool-call counts.
- **Hourly merge + todayHourCounts**: extracts hour-of-day from today's JSONL entries into `todayHourCounts` (today-only, for the 24H chart). Also merges into all-time `hourCounts` using `max()` per hour. Peak hour is computed after the merge so it reflects live data.
- **totalMessages/totalSessions dedup**: iterates all `entriesByDate` keys and computes `max(jsonlCount - cachedCount, 0)` per date, summing across all dates. Prevents inflation when stats-cache already includes recent data.
- **Tool calls merged**: `max(jsonlTodayToolCalls, statsCacheToolCalls)` — JSONL counts `tool_use` content blocks from today's `AssistantUsageEntry.toolCallCount` values; stats-cache provides its own daily count; `max()` prevents either source from underreporting. The JSONL count accumulates in the single-pass loop via `jsonlTodayToolCalls += entry.toolCallCount` for entries where `ts >= today`.
- **`lastSeenByModel` tracking**: in the single-pass loop, `lastSeenByModel[entry.model] = ts` records the most recent timestamp per model (entries are sorted ascending, so last write wins without comparison). After the loop, models are sorted by recency (most recent first) and fed to `RateLimitFetcher.shared.setObservedModels(_:accountId:)` when `accountId` is non-nil.
- **Idle session cutoff**: reads `aibattery_idleSessionMinutes` from UserDefaults (0 = never hide), passes to `TokenHealthMonitor.assessSessions(idleCutoffMinutes:)` to filter stale sessions from context health
- Token health via `TokenHealthMonitor.assessSessions` (single-pass: returns both current + top 5)

### TokenLedger (`Services/TokenLedger.swift`)
- Singleton: `.shared`, `@unchecked Sendable`
- Persistent high-water-mark storage for per-model token totals per account
- File: `~/Library/Application Support/AIBattery/token-ledger.json` (1MB size guard on load)
- Thread safety: `NSLock` guards all reads/writes to the in-memory ledger — prevents concurrent `Task.detached` calls from racing on dictionary mutation
- `merge(_ tokens: [ModelTokenSummary], accountId: String) -> [ModelTokenSummary]` — takes max of current vs stored for each token type (input, output, cacheRead, cacheWrite). Restores historical models no longer in current data. Returns sorted by totalTokens descending. Writes to disk only when values increase (background `Task.detached`, atomic write).
- `LedgerData`: `{ accounts: { accountId: { modelId: ModelTokenRecord } } }` — per-account isolation
- `ModelTokenRecord`: `Codable, Equatable` struct with 4 Int fields
- Injectable `fileURL` for testing (defaults to Application Support path)

### TokenHealthMonitor (`Services/TokenHealthMonitor.swift`)
- Singleton: `.shared`
- `assessSessions(entries:topLimit:idleCutoffMinutes:) -> (current: TokenHealthStatus?, top: [TokenHealthStatus])` — pre-filters entries to current session + those with activity within the idle cutoff before `Dictionary(grouping:)` to avoid allocating dictionary buckets for stale sessions. `idleCutoffMinutes` controls the cutoff: 0 = never hide (uses 24h performance bound), >0 = that many minutes. Returns current session health + top N sorted by `usagePercentage` descending (highest context usage first). Default topLimit is 5.
- `assessCurrentSession(entries:) -> TokenHealthStatus?` — convenience wrapper, returns `assessSessions().current`
- `topSessions(entries:limit:) -> [TokenHealthStatus]` — convenience wrapper, returns `assessSessions().top` (sorted by highest usagePercentage)
- Groups by sessionId, each session assessed independently. Current session is always included in `top` results even when idle past the cutoff — ensures it appears in the session browser.
- **Core calculation**: `totalUsed = latestEntry.inputTokens + latestEntry.cacheReadTokens + latestEntry.cacheWriteTokens + latestEntry.outputTokens` — input + cache tokens are the full conversation context for the latest turn (non-overlapping API components); latest output is added because it will be part of the next turn's input. Each component capped at contextWindow to guard against overflow from corrupted data. The `outputTokens` field in `TokenHealthStatus` stores the total across all entries (for display), while context calculation uses only the latest.
- **Usable window**: `usableWindow = contextWindow × usableContextRatio` (currently 1.0 = full window) — percentages calculated against it
- Band: `< greenThreshold` → green, `< redThreshold` → orange, else red
- Warnings: high turn count (>15 mild, >25 strong), input:output ratio (>20:1, includes cache tokens)
- Velocity: `totalUsed / duration` if 2+ entries and duration > `config.velocityMinDuration` seconds (no double-counting)
- **Anomaly detection**: three additional warnings (all thresholds configurable via `TokenHealthConfig`):
  - Zero output: `outputTokens == 0 && turnCount > config.zeroOutputTurnThreshold` → "Session has no output — check for errors"
  - Rapid consumption: `sessionDuration < config.rapidConsumptionSeconds && totalUsed > config.rapidConsumptionTokens` → "Rapid token consumption detected"
  - Stale session: `lastActivity > config.staleSessionMinutes * 60 && band != .green` → "Session idle for X min — context may be stale"
- **Session metadata**: extracts projectName from cwd (last path component), gitBranch, sessionStart, sessionDuration. Uses **first** entry with cwd for project name (session identity), **latest** entry for git branch (current state).

### FileWatcher (`Services/FileWatcher.swift`)
- `@MainActor`, created per-ViewModel
- Dual watch: DispatchSource on `stats-cache.json` + FSEventStream on `~/.claude/projects/`
- DispatchSource monitors: write, rename, delete events
- FSEventStream flags: `kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes`
- WeakBox wrapper for C callback to prevent retain cycles
- Debounce: 2 seconds via `DispatchWorkItem`
- **Selective cache invalidation**: stats-cache watcher only invalidates `StatsCacheReader`, JSONL watcher only invalidates `SessionLogReader` — avoids unnecessary cache rebuilds when only one data source changed. Fallback timer invalidates both (safe catch-all)
- Fallback timer: 60 seconds — starts if either DispatchSource or FSEventStream fails (ensures changes are picked up even if one watcher is unavailable)
- Calls `onChange` closure → triggers `viewModel.refresh()`
- **Stats-cache retry**: if `stats-cache.json` doesn't exist on launch (normal before first `/stats` run), retries with exponential backoff (60s base, doubles each retry, capped at 300s, max 10 retries ~30 min). Counter resets on success or `stopWatching()`
- **Failure logging**: logs via `AppLogger.files.warning` when file descriptors fail to open, projects directory not found, or FSEventStream creation fails — falls back to timer in all cases
- File paths sourced from `ClaudePaths` (centralized)

### NotificationManager (`Services/NotificationManager.swift`)
- Singleton: `.shared`, `@MainActor`
- `requestPermission()` — requests notification authorization via `UNUserNotificationCenter` (fire-and-forget, system remembers choice)
- `checkStatusAlerts(status:)` — checks single `alertStatus` toggle, iterates all `StatusChecker.knownComponents`, fires notification when any component is non-operational
- `testAlerts()` — fires fake outage notifications for all 5 components (verifies delivery)
- **Migration**: one-time `migrateAlertKeys()` in init — if any legacy per-component key was enabled, enables unified `alertStatus` key; cleans up old keys (tracked via `aibattery_alertKeysMigrated_v2`)
- Deduplication: `hasFired: Set<String>` tracks fired keys, removes on recovery
- **Batch delivery**: queues alerts for 500ms via `Task.sleep`; single alert sent as-is, multiple alerts combined into one notification ("AI Battery: Multiple alerts"). Uses structured concurrency (no GCD queues).
- Delivery: uses `UNUserNotificationCenter` for native macOS notifications with the app's own icon. Each notification gets a unique identifier (`aibattery-{UUID}`).
- Notification: title "AI Battery: {label} is down", body includes status text, default sound

#### Rate Limit Alerts
- `checkRateLimitAlerts(rateLimits:)` — reads `aibattery_alertRateLimit` (Bool) and `aibattery_rateLimitThreshold` (Double, default 80)
- Checks both 5h and 7d windows independently against threshold
- Same dedup pattern: `hasFired` set per window, removes when dropping below threshold
- `shouldAlert(percent:threshold:previouslyFired:)` — static pure function for testability
- **Caller-side stale-data gate**: `UsageViewModel` only passes rate limits from fresh (non-cached) `APIFetchResult`s, via `UsageViewModel.alertableRateLimits(_:)` — a cached reading never fires a notification (gated on `isCached`); the menu bar / popover *alarm* uses the stricter `alarmConfirmed(rateLimitsFresh:displayedIsThrottled:)` gate, which also suppresses a successful-but-header-less fetch that reuses held stale limits

### VersionChecker (`Services/VersionChecker.swift`)
- Singleton: `.shared`
- `checkForUpdate() async -> UpdateInfo?` — fetches GitHub Releases API once per 24h
- `forceCheckForUpdate() async -> UpdateInfo?` — bypasses 24h cache
- `isNewer(_:than:) -> Bool` — static semver comparison (major/minor/patch)
- `stripTag(_:) -> String` — strips leading "v" or "V"
- `currentAppVersion` — reads `CFBundleShortVersionString` from bundle
- `UpdateInfo`: `version: String`, `url: String`
- Cache: `lastCheck: Date?`, `cachedUpdate: UpdateInfo?` — restored from UserDefaults on init (`aibattery_lastUpdateCheck` as Unix timestamp, `aibattery_lastUpdateVersion` + `aibattery_lastUpdateURL`), persisted after each check. On restore, validates cached version against `currentAppVersion` — discards stale entries when the app has been upgraded past the cached version.
- Timeout: 10 sec

### SparkleUpdateService (`Services/SparkleUpdateService.swift`)
- Singleton: `.shared`
- Wraps `SPUStandardUpdaterController` from Sparkle 2
- Disables all automatic behavior: `automaticallyChecksForUpdates = false`, `automaticallyDownloadsUpdates = false`, `updateCheckInterval = 0`
- `checkForUpdates()` — temporarily sets `NSApp.setActivationPolicy(.regular)` + `activate(ignoringOtherApps:)` (LSUIElement workaround), reverts to `.accessory` after 5s, then triggers Sparkle's standard update dialog
- `canCheckForUpdates: Bool` — exposes Sparkle readiness
- Testable init accepts pre-configured controller
- Sparkle reads `SUFeedURL` and `SUPublicEDKey` from Info.plist
- Feed URL: `https://kylenesium.github.io/AIBattery/appcast.xml`
- EdDSA verification: Sparkle verifies download signature against `SUPublicEDKey` before installing

### SparkleUpdateDelegate (`Services/SparkleUpdateDelegate.swift`)
- `@MainActor`, conforms to `SPUUpdaterDelegate`
- Guarded by `#if ENABLE_SPARKLE`
- `lastError: String?` — last Sparkle error, surfaced for UI display
- `updater(_:didFinishUpdateCycleFor:error:)` — logs error/success, reverts activation policy to `.accessory`
- `updater(_:didAbortWithError:)` — logs abort, sets `lastError`
- `clearError()` — resets error state (e.g., user dismissal)
- Without this delegate, Sparkle fails silently — users see "nothing happens" when update download/verification/installation fails

### NetworkMonitor (`Services/NetworkMonitor.swift`)
- Singleton: `.shared`, `@MainActor ObservableObject`
- Published: `isConnected: Bool` (default true)
- Uses `NWPathMonitor` on a private `DispatchQueue`
- `start()` — begins monitoring; updates `isConnected` on main actor when path status changes
- Used by `UsageViewModel` to skip network calls when offline

### LaunchAtLoginManager (`Services/LaunchAtLoginManager.swift`)
- Public enum (no instances)
- `isEnabled: Bool` — reads `SMAppService.mainApp.status`
- `setEnabled(_:)` — register/unregister via SMAppService
- `reregisterIfNeeded()` — public, called on launch. Re-registers if user preference is on but system registration was lost (e.g. after ad-hoc re-signing from a Sparkle update). Reads `UserDefaultsKeys.launchAtLogin` to check intent.
- Requires installed .app bundle, silently fails during dev builds
- Logs failures via `AppLogger.general`

## ViewModel

### UsageViewModel (`ViewModels/UsageViewModel.swift`)
- `@MainActor`, `ObservableObject`
- Published: `snapshot: UsageSnapshot?`, `systemStatus: ClaudeSystemStatus?`, `isLoading: Bool`, `errorMessage: String?`, `lastFreshFetch: Date?`, `isShowingCachedData: Bool` (network fetch hit cache), `rateLimitsFresh: Bool` (this cycle returned unified headers AND wasn't cache-served — distinct from `!isShowingCachedData`; gates the alarm and the displayed %), `availableUpdate: VersionChecker.UpdateInfo?` (only compiled under `#if ENABLE_VERSION_CHECKER`), `resolvedMetricMode: MetricMode` (hysteresis-filtered auto-mode output — drives the active metric in auto mode), `perAccountRateLimits: [String: RateLimitUsage]` (keyed by account ID; populated only when `aibattery_showAllAccountsInMenuBar == true`; drives multi-account menu bar text)
- **Polling constants**: `defaultRefreshInterval` (120s), `minRefreshInterval` (30s), `maxRefreshInterval` (300s), `initialPollDelay` (2s)
- Static helpers: `clampedRefreshInterval(_:)` (clamps stored interval to [min, max], zero/negative → default), `refreshErrorMessage(hasRateLimits:hasStandardLimits:hasProfile:hasStandardRateLimitHeaders:totalMessages:authError:)` (error string or nil — `authError: true` overrides everything and returns the "log out and reconnect" prompt; otherwise: rate limits present → nil; standard limits present → nil; public API headers without Claude Code windows → nil; profile present but no windows → nil; neither present + no messages → first-use prompt; neither present → network error), `hasDataChanged(previousTotal:previousToday:newTotal:newToday:)` (adaptive polling change detection)
- **Throttle tracking** (delegates to `ThrottleTracker`): `recordThrottleEvent(_:source:)` uses `ThrottleTracker.evaluate(_:)` to detect the normal→throttled transition (genuine throttle only — explicit `isThrottled`; 100% utilization is *not* counted as a throttle event), records timestamp to UserDefaults `aibattery_throttleTimestamps` via `ThrottleTracker.appendAndPrune`. Emits one structured `AppLogger.network` line on each throttle on/off transition (binding window, reset timestamp, source: `api-fresh`/`stale-cache`) so a stuck throttle state is diagnosable. `throttleCount(days:)` reads timestamps from UserDefaults, parses via `ThrottleTracker.parseTimestamps(_:)` (handles Double/String/Int storage variants), counts via `ThrottleTracker.count(timestamps:days:)`.
- `refresh()`: captures the active account ID at poll start, then fetches a token **pinned to that account** via `OAuthManager.getAccessToken(for:)` (never the unpinned `getAccessToken()` — a mid-poll account switch would otherwise send account B's token on a request cached/persisted under account A's key), passes to `RateLimitFetcher.shared.fetch(accessToken:accountId:)`. Status check runs concurrently via `async let`. Guards against stale results **before any published state is written** — `shouldApplyFetchResult(fetchedAccountId:activeAccountId:)` (pure static) discards the result if the active account changed mid-flight, so `apiResult`/`systemStatus`/`isShowingCachedData`/`rateLimitsFresh`/`lastFreshFetch` are only assigned for the still-active account. `rateLimitsFresh = rateLimitsAreFresh(freshRateLimits: api.rateLimits, isCached: api.isCached)`; the offline / unauthenticated / instant-paint branches set it `false` and pass `rateLimitPercentConfirmed: false` to the aggregator. After the guard: resolves pending identity (`resolveAccountIdentity`) or updates metadata (`updateAccountMetadata`) from API response. Aggregation runs on the main actor (same thread as FileWatcher cache invalidation — no data races). Calls `NotificationManager.shared.checkStatusAlerts(status:)` and, only when the result is fresh (`alertableRateLimits(_:)` returns nil for cached results), `checkRateLimitAlerts(rateLimits:)`. Checks `VersionChecker.shared.checkForUpdate()` when no update cached. Tracks staleness from API result.
- **Rate limit stale TTL**: when the API returns nil rate limits, previously-fetched values are carried forward for up to `rateLimitStaleTTL` (86,400s / 24 hours — holds through overnight sleep cycles). After expiry, nil is passed to the aggregator so the UI transitions to `StandardRateLimits` fallback. `effectiveRateLimits(fresh:stale:lastFreshAt:ttl:now:)` is a pure static function with injectable `now` for testing. `effectiveValue(fresh:stale:lastFreshAt:ttl:now:)` is the generic version used for `rateLimitSource`. Prevents the "stale data treadmill" where frozen percentages were carried forward indefinitely.
- `switchAccount(to:)` — sets active account, clears snapshot/staleness/errors, triggers refresh, then triggers `fetchAllAccounts()` so the multi-account map stays current.
- `fetchAllAccounts(seed:)` — when `aibattery_showAllAccountsInMenuBar == true`, fans out a `TaskGroup` over `accountStore.accounts` (filtered to non-pending, authenticated accounts), fetches each via `OAuthManager.getAccessToken(for:)` + `RateLimitFetcher.fetch(accessToken:accountId:)`, and atomically publishes `perAccountRateLimits` (each value normalized via `withClearedRolloverArtifacts`). **Net cost is N requests for N accounts, not N+1.** `RateLimitFetcher.fetch` does *not* short-circuit on cache, so a naive fan-out would re-fetch the active account that `refresh()` just fetched. To avoid that, `refresh()` passes the active account's fresh result as the `seed:` parameter (`(accountId, rateLimits)`, only when non-`nil` and `!isCached`); `fetchAllAccounts` injects the seed directly into the result map and excludes that account ID from the fan-out. When toggle is OFF, clears the map. Fan-out triggers are coalesced via `scheduleFanOut()` (single in-flight `pendingFanOut` task). Triggered from end of `refresh()` (seeded), from `switchAccount(to:)`, and from a `UserDefaults.didChangeNotification` observer in init for instant toggle propagation. Skipped accounts (no access token, or a fetch that returned no rate limits) emit one `AppLogger.network` info line each — a skipped account renders as "—" in the menu bar, and these lines are the only diagnostic for why.
- `updatePollingInterval(_:)`: invalidates and recreates polling timer
- Init: synchronous local data load (shows data immediately if available), then sets up file watcher, starts polling timer (interval from `aibattery_refreshInterval` UserDefaults, default 120s), triggers async refresh
- Deinit: invalidates polling timer, removes sleep/wake observers (FileWatcher's own deinit handles its cleanup)
- **Adaptive polling**: delegates to `AdaptivePollingState` struct. Compares `totalMessages`/`todayMessages` before and after refresh. After 3 unchanged cycles, doubles polling interval (up to 5 min max). Any data change or file watcher trigger resets to configured interval.
- **Idle/lock suspension**: `isSuspended: Bool` tracks whether timers are paused. Idle check piggybacks on each polling tick via `IdleSuspendPolicy.shouldSuspend(secondsIdle:)` — no new timer. `suspendTimers()` invalidates polling timer and calls `FileWatcher.suspendFallbackTimer()`. `resumeTimers()` restarts polling and calls `FileWatcher.resumeFallbackTimer()`.
- **Sleep/wake lifecycle**: `setupSleepWakeObservers()` subscribes to `NSWorkspace.willSleepNotification` (suspends timers) and `didWakeNotification` (resumes timers, triggers immediate refresh). Also subscribes to `sessionDidResignActiveNotification` (screen lock → suspend) and `sessionDidBecomeActiveNotification` (unlock → resume + refresh).
- **Network awareness**: skips network calls when `NetworkMonitor.shared.isConnected` is false — aggregates local data with cached rate limits. `NetworkMonitor.start()` called in init.
- **Identity timeout**: warns if a pending account hasn't resolved identity after 1 hour (prompts re-auth).
- **JSONL corruption logging**: after aggregation, logs `SessionLogReader.lastCorruptLineCount` via `AppLogger.files.warning` if > 0.

## Views

### StatusBarManager (`Views/StatusBarManager.swift` + extensions)

- `@MainActor` class managing the `NSStatusItem` and `PopoverPanel`. Split across `+ButtonUpdate` / `+Countdown` / `+Panel` extension files (UsageViewModel precedent); shared stored state is declared non-private for cross-file extension visibility.
- **Exhausted state** — only on a genuine throttle (`RateLimitUsage.isThrottled`) the menu bar icon switches to a static broken star (12-pointed spiky star with solid 4-pointed overlay). No animation — the distinct shape communicates the state. Reaching 100% utilization *without* a throttle is the "at capacity" state: a solid red (non-broken) star, since the icon color is driven by percent.
- **Render skip** — `updateButton` builds a `MenuBarRenderKey` (text, whole-percent bucket, color, isBroken, isSparkle, appearance name) and only rebuilds the combined NSImage when the key changed. During a throttle countdown the ticker fires every 10s but the compact text changes ~once a minute, so most ticks skip the NSAttributedString+NSImage allocation entirely. Timer bookkeeping (start/stop countdown) always runs — it manages timers, not pixels.
- **Panel toggle** — `PanelToggleState` value type tracks `.isShowing`; `statusItemClicked` toggles show/hide; `panel.onDismiss` consolidates all dismiss paths.
- **Recovery sparkle** — 30s celebration animation triggered when throttle/exhaustion clears; `isSparkleActive` drives sparkle icon rendering.

## Utilities

### AppPaths (`Utilities/AppPaths.swift`)
- `applicationSupport() -> URL` — `~/Library/Application Support/AIBattery`, created if missing; fails fast (fatalError) when the system directory is unavailable. Single home for the guard previously duplicated in `SingleInstanceGuard` and `TokenLedger`.

### ClaudePaths (`Utilities/ClaudePaths.swift`)
- Centralized file paths for all Claude Code data locations (`static let` — computed once at load time)
- `statsCache` / `statsCachePath` — `~/.claude/stats-cache.json`
- `projects` / `projectsPath` — `~/.claude/projects/`
- Used by FileWatcher, StatsCacheReader, SessionLogReader, UsageAggregator

### TokenFormatter (`Utilities/TokenFormatter.swift`)
- `format(_ count: Int) -> String` — 500 → "500", 2500 → "2.5K", 15000 → "15K", 3200000 → "3.2M", 1500000000 → "1.5B"
- Supports K/M/B suffixes with rollover (999.5K → "1.0M", 999.5M → "1.0B")
- Guards against negative input (returns "0")

### ModelNameMapper (`Utilities/ModelNameMapper.swift`)
- `displayName(for modelId: String) -> String`
- Strips "claude-" prefix via `hasPrefix`/`dropFirst`, strips trailing date segment (8+ consecutive digits) using manual character iteration (no regex — avoids NSRegularExpression bridging overhead), converts hyphens to dots, capitalizes family
- **Result cache**: static `[String: String]` dictionary. Model IDs are immutable — same input always gives same output. Cache is permanent and small (~20 entries max). Access is guarded by an `NSLock` (`nonisolated(unsafe)` cache + `lock.withLock`) since Swift Testing runs suites concurrently.
- "claude-opus-4-6-20250929" → "Opus 4.6"

### DateFormatters (`Utilities/DateFormatters.swift`)
- Enum (no instances) — centralized, allocated-once date formatters
- `dateKey: DateFormatter` — `"yyyy-MM-dd"`, `en_US_POSIX` locale. Used for daily activity date keys, stats cache lookups.
- `iso8601: ISO8601DateFormatter` — with `.withFractionalSeconds`. Used for JSONL timestamps, firstSessionDate.
- `shortDay: DateFormatter` — `"EEE"`, `en_US_POSIX` locale. Used for day-of-week labels.
- `shortMonth: DateFormatter` — `"MMM"`, `en_US_POSIX` locale. Used for monthly chart labels.

### AdaptivePollingState (`Utilities/AdaptivePollingState.swift`)
- Pure value type (struct) — testable without `@MainActor` or framework dependencies
- `unchangedCycles: Int` — tracks consecutive refresh cycles with no data change
- `static let adaptiveThreshold = 3` — unchanged cycles before doubling
- `static let maxPollingInterval: TimeInterval = 300` — hard cap (5 min)
- `mutating func evaluate(dataChanged:baseInterval:) -> TimeInterval` — resets counter on data change (returns base); increments on no change; progressive doubling past threshold: `base × 2^(cyclesPastThreshold)` (capped at max)
- Used by `UsageViewModel` via `private var adaptivePolling = AdaptivePollingState()`

### UserDefaultsKeys (`Utilities/UserDefaultsKeys.swift`)
- Enum with `static let` constants for all `@AppStorage` / `UserDefaults` keys
- All keys prefixed with `aibattery_` to avoid collisions
- Keys: `metricMode`, `autoMetricMode`, `refreshInterval`, `idleSessionMinutes`, `chartMode`, `plan` (billing type from `~/.claude.json`, legacy naming), `planTier`, `accounts`, `activeAccountId`, `launchAtLogin`, `alertStatus`, `alertRateLimit`, `rateLimitThreshold`, `lastUpdateCheck`, `lastUpdateVersion`, `lastUpdateURL`, `colorblindMode`, `showAllAccountsInMenuBar`, `hasSeenTutorial`, `throttleTimestamps` (array of Unix epoch doubles for rate limit events), `contextCollapsed`, `projectsCollapsed`, `activityCollapsed`, `tokenExpiresAtPrefix` (prefix for per-account token expiry timestamps). (`showCostEstimate` and `tokensCollapsed` were removed since v1.9.0.)

### SecureNetworking (`Utilities/SecureNetworking.swift`)
- Enum (no instances) — centralized networking layer
- `session: URLSession` — shared ephemeral session (no disk cache, no cookies, no credential storage)
- `maxResponseSize = 2_000_000` (2 MB) — drops responses exceeding this limit
- `data(for:) async throws -> (Data, URLResponse)` — fetches via ephemeral session, throws `URLError(.dataLengthExceedsMaximum)` for oversized responses
- Used by all 4 network services: `OAuthManager`, `RateLimitFetcher`, `StatusChecker`, `VersionChecker`

### DurationFormatter (`Utilities/DurationFormatter.swift`)
- Enum (no instances) — shared compact time duration formatting
- `static func compact(_ seconds: TimeInterval) -> String` — formats a duration into the shortest human-readable form
  - `≤ 0` → `"0s"`
  - `< 60s` → `"Xs"` (actual seconds, minimum `"1s"`)
  - `1–59 min` → `"Xm"`
  - `1h–23h 59m` → `"Xh Ym"`
  - `≥ 24 hours` → `"Xd Yh"`
- Used by: `UsageBarsSection` (reset countdown), `TokenHealthSection` (session duration), `RateLimitUsage` (countdown text), menu bar throttle countdown

### AppLogger (`Utilities/AppLogger.swift`)
- Enum with `static let` `os.Logger` instances, subsystem `com.KyleNesium.AIBattery`
- Categories: `general`, `oauth`, `network`, `files`
- Used throughout services for structured logging (replaces bare `print()` calls)

### ThemeColors (`Utilities/ThemeColors.swift`)
- Enum (no instances)
- Reads `UserDefaultsKeys.colorblindMode` to switch palettes
- `barColor(percent:) -> Color` — usage bar fill color
- `bandColor(_: HealthBand) -> Color` — context health band color
- `statusColor(_: StatusIndicator) -> Color` — system status dot color
- `barNSColor(percent:isDarkMenuBar:) -> NSColor` — menu bar icon fill color. Optional `isDarkMenuBar` flag: when `false`, the 50–80% band uses `menuBarGold` (#B88F00) instead of `systemYellow`/`systemTeal` to maintain contrast on light menu bars
- Standard palette: green → yellow/gold → orange → red
- Colorblind palette: blue → teal/gold → amber → purple (deuteranopia/protanopia safe)

### IdleSuspendPolicy (`Utilities/IdleSuspendPolicy.swift`)
- Pure enum — no instances, fully `nonisolated`, no side effects
- `static let defaultThreshold: TimeInterval = 300` — 5-minute idle threshold
- `static func shouldSuspend(secondsIdle:threshold:) -> Bool` — returns true when idle time meets or exceeds threshold
- `static func idleSeconds() -> TimeInterval` — reads system HID idle seconds via `CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .mouseMoved)`. Returns 0 on failure (safe — never suspends on error).
- Used by `UsageViewModel.refresh()` to decide whether to suspend timers on each polling tick

### ThrottleTracker (`Utilities/ThrottleTracker.swift`)
- Pure value type (struct) — immutable pattern, `evaluate` returns a new tracker instead of mutating
- `private(set) var wasThrottled: Bool` — tracks whether the previous evaluation saw a genuine throttled state
- `evaluate(_ rateLimits: RateLimitUsage?) -> (tracker: ThrottleTracker, recordTimestamp: Double?)` — detects the normal→throttled transition. `effectivelyThrottled = rateLimits?.isThrottled ?? false` (genuine throttle only; 100% utilization is "at capacity", not a throttle). Returns a new `ThrottleTracker` with updated `wasThrottled` + optional Unix timestamp to record (non-nil only on the transition from false→true). Does not mutate self.
- `static parseTimestamps(_ raw: [Any]?) -> [Double]` — converts raw UserDefaults array to `[Double]`, handling Double, String, and Int storage variants (legacy data may be stored as strings)
- `static appendAndPrune(timestamps: [Double], newTimestamp: Double) -> [Double]` — appends new timestamp, prunes entries older than 30 days (cutoff = `newTimestamp - 30 * 86400`)
- `static count(timestamps: [Double], days: Int) -> Int` — counts timestamps within the last N days from now
- Used by `UsageViewModel` for throttle trend tracking. Extracted from `UsageViewModel` for testability without global mutable state.

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
| `totalSessions` | `Int` | stats-cache + today JSONL |
| `totalMessages` | `Int` | stats-cache + today JSONL |
| `longestSessionDuration` | `String?` | stats-cache (formatted) |
| `longestSessionMessages` | `Int` | stats-cache |
| `peakHour` | `Int?` | stats-cache hourCounts |
| `peakHourCount` | `Int` | stats-cache hourCounts |
| `todayMessages` | `Int` | Today's JSONL entries count |
| `todaySessions` | `Int` | Unique session IDs in today's entries |
| `todayToolCalls` | `Int` | stats-cache dailyActivity for today |
| `hourCounts` | `[String: Int]` | stats-cache hourCounts (hour "0"-"23" → message count) |
| `modelTokens` | `[ModelTokenSummary]` | Merged stats-cache + JSONL |
| `dailyActivity` | `[DailyActivity]` | stats-cache |
| `tokenHealth` | `TokenHealthStatus?` | Most recent session assessment |
| `topSessionHealths` | `[TokenHealthStatus]` | Top 5 sessions by most recent activity (descending) |

Computed: `totalTokens`, `percent(for: MetricMode) -> Double` (shared metric percentage calculation used by both menu bar and popover)

Projections & trends: `dailyAverage: Int` (average messages/day from last 7 days of `dailyActivity`), `projectedTodayTotal: Int` (extrapolate today's messages based on hour-of-day progress), `trendDirection: TrendDirection` (compare this week vs last week averages, ±10% threshold → `.up`/`.down`/`.flat`), `busiestDayOfWeek: (name: String, averageCount: Int)?` (highest average from `dailyActivity` by weekday).

### ModelTokenSummary

| Field | Type |
|-------|------|
| `id` | `String` (model ID) |
| `displayName` | `String` |
| `inputTokens` | `Int` |
| `outputTokens` | `Int` |
| `cacheReadTokens` | `Int` |
| `cacheWriteTokens` | `Int` |

Computed: `totalTokens` = sum of all four token types

### MetricMode (`Models/UsageSnapshot.swift`)

Which metric drives the menu bar icon percentage and color.

| Case | rawValue | label | shortLabel |
|------|----------|-------|------------|
| `.fiveHour` | `"5h"` | `"5-Hour"` | `"5h"` |
| `.sevenDay` | `"7d"` | `"7-Day"` | `"7d"` |
| `.contextHealth` | `"context"` | `"Context"` | `"Ctx"` |

### TrendDirection (`Models/UsageSnapshot.swift`)

| Case | Symbol |
|------|--------|
| `.up` | ↑ |
| `.down` | ↓ |
| `.flat` | → |


### APIProfile (`Models/APIProfile.swift`)

Organization info extracted from Messages API response headers.

| Field | Type |
|-------|------|
| `organizationId` | `String?` |

`parse(headers:)` static method: reads `anthropic-organization-id` from HTTP response.

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
| `profile` | `APIProfile?` |
| `fetchedAt` | `Date` — when this result was fetched (defaults to `Date()`) |
| `isCached` | `Bool` — whether this result came from cache rather than a fresh API response (defaults to `false`) |

### RateLimitUsage (`Models/RateLimitUsage.swift`)

Parsed from Anthropic's unified rate limit headers (`anthropic-ratelimit-unified-*`). The API uses a unified sliding-window system with two windows: 5-hour (short-term burst) and 7-day (long-term usage). Each reports a utilization fraction (0.0–1.0) and a reset timestamp. The `representative-claim` tells which window is the binding constraint.

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

Computed: `requestsPercentUsed` (binding window utilization × 100), `fiveHourPercent`, `sevenDayPercent`, `bindingReset`, `bindingWindowLabel`, `isThrottled`, `estimatedTimeToLimit(for window: String) -> TimeInterval?` (burn rate = utilization / elapsed, projects when 100% reached; returns nil if utilization ≤ 50%, elapsed < 60s, or estimate exceeds reset time)

`parse(headers:)` static method: reads `anthropic-ratelimit-unified-status`, `anthropic-ratelimit-unified-representative-claim`, `anthropic-ratelimit-unified-5h-utilization`, `anthropic-ratelimit-unified-5h-reset`, `anthropic-ratelimit-unified-5h-status`, and equivalent `7d` headers. Reset timestamps are parsed as Unix epoch seconds.

### TokenHealthStatus (`Models/TokenHealthStatus.swift`) — `Identifiable`

| Field | Type |
|-------|------|
| `id` | `String` (sessionId) |
| `band` | `HealthBand` (.green, .orange, .red, .unknown) |
| `usagePercentage` | `Double` |
| `totalUsed` | `Int` |
| `contextWindow` | `Int` |
| `usableWindow` | `Int` — contextWindow × 0.8 (auto-compact threshold) |
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

`id: UUID`, `severity: WarningSeverity` (.mild, .strong), `message: String`, `suggestion: String?`

### TokenHealthConfig (`Models/TokenHealthConfig.swift`)

Instance properties with defaults: `greenThreshold = 60.0`, `redThreshold = 80.0`, `turnCountMild = 15`, `turnCountStrong = 25`, `inputOutputRatioThreshold = 20.0`, `staleSessionMinutes = 30`, `zeroOutputTurnThreshold = 3`

Static: `contextWindows: [String: Int]` dictionary, `defaultContextWindow = 200_000`, `usableContextRatio = 0.80`, `contextWindow(for model:) -> Int` (exact match → pre-computed prefix lookup via `prefixLookup` dictionary, built once at load time from 3-part prefixes of `contextWindows` keys).

Thresholds apply to the **usable window** (80% of raw context). Claude Code auto-compacts at 80%, so 100% usage = imminent compaction.

### StatsCache (`Models/StatsCache.swift`)

Codable struct matching `~/.claude/stats-cache.json`:
- `version`, `lastComputedDate`
- `dailyActivity: [DailyActivity]` — date, messageCount, sessionCount, toolCallCount
- `dailyModelTokens: [DailyModelTokens]` — date, tokensByModel: `[String: Int]` (model ID → token count)
- `modelUsage: [String: ModelUsageEntry]` — total per-model usage (includes `webSearchRequests?`, `contextWindow?`, `maxOutputTokens?`)
- `totalSessions`, `totalMessages`
- `longestSession: LongestSession?` — sessionId, duration (ms), messageCount, timestamp
- `hourCounts: [String: Int]` — message counts per hour of day
- `firstSessionDate: String?`
- `totalSpeculationTimeSavedMs: Int?`

### SessionEntry (`Models/SessionEntry.swift`)

JSONL line schema (Codable):
- `type`, `timestamp`, `sessionId`, `uuid` — all `String?`
- `cwd: String?`, `gitBranch: String?`
- `message: SessionMessage?` — contains `role`, `model`, `usage: TokenUsage?`, `id`
- `TokenUsage` includes `service_tier: String?` alongside the four token count fields

`AssistantUsageEntry` (processed form): `timestamp: Date`, `model: String`, `messageId: String`, `inputTokens/outputTokens/cacheReadTokens/cacheWriteTokens: Int`, `sessionId: String`, `cwd: String?`, `gitBranch: String?`

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
- `static pricing(for modelId: String) -> ModelPricing?` — lookup via `ModelNameMapper.displayName`
- `static totalCost(for models: [ModelTokenSummary]) -> Double` — aggregate across models

Pricing table (per million tokens):

| Model | Input | Output | Cache Write | Cache Read |
|-------|-------|--------|-------------|------------|
| Opus 4 | $15 | $75 | $1.875 | $1.50 |
| Sonnet 4 | $3 | $15 | $0.375 | $0.30 |
| Haiku 4 | $0.80 | $4 | $0.10 | $0.08 |
| Sonnet 3.5 | $3 | $15 | $0.375 | $0.30 |
| Haiku 3.5 | $0.80 | $4 | $0.10 | $0.08 |
| Opus 3 | $15 | $75 | $1.875 | $1.50 |

### ClaudeSystemStatus + StatusIndicator (`Services/StatusChecker.swift`)

`ClaudeSystemStatus`: `indicator: StatusIndicator`, `description: String`, `incidentName: String?`, `statusPageURL: String`, `claudeAPIStatus: StatusIndicator` (default .unknown), `claudeCodeStatus: StatusIndicator` (default .unknown)

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
- **Multi-account**: supports up to 2 accounts (separate Claude orgs). Each account's tokens stored under prefixed Keychain entries (`accessToken_{accountId}`, etc.). `AccountStore` tracks known accounts; `activeAccountId` drives which one polls. New accounts get a temporary `"pending-<UUID>"` ID until the first API call returns the real `anthropic-organization-id`.
- `startAuthFlow(addingAccount:)` → opens browser with PKCE challenge. `addingAccount` flag tracks whether this is a second-account flow. Generates a separate random `state` parameter (never reuses the PKCE verifier).
- `exchangeCode(_:) -> Result<Void, AuthError>` → exchanges auth code for access + refresh tokens. Creates `AccountRecord` with pending ID, stores tokens under prefixed Keychain entries. Validates state parameter (CSRF protection). Only clears PKCE state on success.
- `getAccessToken()` → returns active account's valid token, refreshes 5 minutes before expiry. `getAccessToken(for:)` for specific account. Serializes concurrent refresh attempts per account via `refreshTasks` dictionary.
- `resolveAccountIdentity(tempId:realOrgId:billingType:)` → called after first API call returns real org ID. Renames Keychain entries from temp to real ID, updates AccountStore. Idempotent. Handles duplicate detection (same org authed twice → merge, keep newer tokens).
- `updateAccountMetadata(accountId:displayName:billingType:)` → updates existing account's display name and/or billing type in AccountStore.
- `signOut(accountId:)` → removes specific account (or active if nil), auto-switches to remaining account if any.
- **Legacy migration**: `migrateFromLegacy()` on init — detects old unprefixed Keychain entries, creates AccountRecord with temp ID, copies to prefixed format, deletes old entries. Runs only when accounts array is empty.
- **Per-account Keychain**: `saveTokens(for:)`, `loadTokens(for:)`, `deleteTokens(for:)` using `"accessToken_{accountId}"` format under service `"AIBattery"`.
- `AuthError` enum: `.noVerifier`, `.invalidCode`, `.expired`, `.networkError`, `.serverError(Int)`, `.maxAccountsReached`, `.unknownError(String)` — each has `userMessage` for display. `isTransient` for `.networkError`/`.serverError`.
- **Token endpoint retry**: `postToken()` retries up to 2 times with exponential backoff (1s, 2s) with jitter on 429 and 5xx. Parses `Retry-After` header on 429 when present. Non-retryable errors fail immediately.
- **Refresh resilience**: transient errors during refresh do NOT mark `isAuthenticated = false`. Only auth errors trigger logout.

### AccountStore (`Services/AccountStore.swift`)
- `@MainActor ObservableObject`, owned by `OAuthManager`
- Published: `accounts: [AccountRecord]`, `activeAccountId: String?`
- Computed: `activeAccount`, `canAddAccount` (< 2)
- `add(_:)` — appends record, sets as active if first, rejects duplicates and over-max
- `remove(id:)` — removes account, auto-switches active to remaining
- `setActive(id:)` — changes active account (no-op for unknown IDs)
- `update(oldId:with:)` — replaces account record, handles identity resolution (pending → real org ID). Detects and merges duplicates (same org authed twice): preserves earliest `addedAt`, keeps existing `displayName`/`billingType` when new record has nil. Handles index ordering correctly when removing the old entry.
- Persistence: JSON-encoded `[AccountRecord]` to `UserDefaults(aibattery_accounts)` + `activeAccountId` string to `UserDefaults(aibattery_activeAccountId)`
- Load on init: fixes dangling `activeAccountId` pointing at removed accounts
- `nonisolated static let maxAccounts = 2`

### RateLimitFetcher (`Services/RateLimitFetcher.swift`)
- Singleton: `.shared`
- `fetch(accessToken:accountId:) async -> APIFetchResult` — returns both rate limits and org profile from a single API call
- POST `/v1/messages?beta=true` with `max_tokens: 1`, content `"."`
- Model fallback list: tries `claude-sonnet-4-6-20250929` first, then `claude-sonnet-4-5-20250929`, then `claude-haiku-3-5-20241022`. Remembers last working model index to avoid repeated fallbacks.
- Headers: `Authorization: Bearer {token}`, `anthropic-version: 2023-06-01`, `anthropic-beta: oauth-2025-04-20,interleaved-thinking-2025-05-14`, `User-Agent: AIBattery/{version} (macOS)` (dynamic from bundle)
- Caller provides token and account ID. Per-account caching: `cachedResults: [String: APIFetchResult]` and `currentModelIndex: [String: Int]` keyed by account ID.
- Timeout: 15 sec
- Parses `anthropic-ratelimit-unified-*` response headers via `RateLimitUsage.parse(headers:)` and `APIProfile.parse(headers:)` from the same response
- Caches last successful `APIFetchResult`; returns cached on network error or auth failure (with `isCached: true`, preserving original `fetchedAt`). Cache expires after 1 hour (`cacheMaxAge = 3600s`) to avoid showing very old data.
- Model unavailable (400/404 with model/access error message) → tries next model in list
- Non-model 400/404 errors: extracts rate limit headers if present and returns as success; otherwise returns `.networkError` (never silently falls through to header-less success)

### StatusChecker (`Services/StatusChecker.swift`)
- Singleton: `.shared`
- `fetchStatus() async -> ClaudeSystemStatus`
- GET `https://status.claude.com/api/v2/summary.json`
- Timeout: 5 sec
- Component IDs exposed as `static let` constants: `claudeAPIComponentID`, `claudeCodeComponentID`
- Filters components to Claude API and Claude Code
- Returns worst status among relevant components
- Populates per-component statuses: `claudeAPIStatus` and `claudeCodeStatus`
- **Incident impact escalation**: when components report "operational" but active incidents exist, factors in incident `impact` field (`"none"`, `"minor"`, `"major"`, `"critical"`) to determine overall indicator. If impact is `"none"` but incidents are active, escalates to at least `.degradedPerformance` (yellow dot).
- Checks for active incidents (status not `resolved` or `postmortem`)
- Returns `.unknown` on any error
- **Backoff**: exponential backoff with jitter on failure — base 60s doubles per failure, capped at 5 min, ±20% jitter to prevent thundering herd; stored once per failure increment (not re-randomized on every check); resets on success

### StatsCacheReader (`Services/StatsCacheReader.swift`)
- Singleton: `.shared`
- `read() -> StatsCache?`
- Reads and JSON-decodes `~/.claude/stats-cache.json`
- **Result caching**: caches decoded `StatsCache` with file modification date and size; skips re-decode when file unchanged. `invalidate()` clears cache (called by FileWatcher on change).

### SessionLogReader (`Services/SessionLogReader.swift`)
- Singleton: `.shared`
- `readAllUsageEntries() -> [AssistantUsageEntry]`
- `readTodayEntries() -> [AssistantUsageEntry]`
- Discovers JSONL in `~/.claude/projects/*/*.jsonl` and `*/subagents/*.jsonl`
- FileHandle streaming: 64KB buffer, line-by-line, 1MB max line size safety cap (discards oversized lines)
- Pre-filter: byte search for `"type":"assistant"` AND `"usage"` before JSON decode
- **Decode error logging**: when pre-filter matches but JSON decode fails, logs via `AppLogger.files.debug` with filename and error description
- **Trailing line safety**: remaining data after last newline is only processed if it ends with `}` (skips incomplete/partial writes still being written)
- Mod-time + file-size cache to skip unchanged files
- **Result-level caching**: caches the merged `[AssistantUsageEntry]` result; invalidated by FileWatcher via `invalidate()`. Avoids re-sorting and re-deduplicating on every refresh.
- **Discovery caching**: caches discovered JSONL file list with parent directory modification dates; re-scans only when directory contents change.
- **Cache eviction**: evicts oldest entries when cache exceeds 200 files (`maxCacheEntries`) using batch-sort O(n log n) to find the oldest entries in a single pass
- Deduplication by messageId within each file
- Sorted by timestamp ascending
- **Entry construction**: `makeUsageEntry(from:)` static helper extracts `AssistantUsageEntry` from decoded `SessionEntry` — shared between main line loop and trailing-data handler (DRY)
- **Corruption tracking**: `lastCorruptLineCount` (public getter) counts decode failures and oversized line skips per `readAllUsageEntries()` call; reset at start of each call (before cache check) to avoid stale values on cache hits

### UsageAggregator (`Services/UsageAggregator.swift`)
- Created per-ViewModel (not singleton)
- `aggregate(rateLimits:) -> UsageSnapshot`
- **Single-pass filtering**: iterates all entries once to extract both today's entries and windowed token totals simultaneously (avoids separate `.filter()` passes)
- Reads: stats cache, all JSONL entries (single scan)
- **Token window modes**: `aibattery_tokenWindowDays` UserDefaults (0 = all time, 1–7 = windowed)
  - **All-time mode (0)**: stats-cache `modelUsage` + uncached JSONL, anti-double-counting for dates already in stats cache, 72-hour recent model filter
  - **Windowed mode (1–7)**: computes token totals from all JSONL entries within the window, bypasses stats-cache `modelUsage`
- **Non-Claude model filter**: excludes model IDs that don't start with `"claude-"` (e.g. `"synthetic"`)
- Tool calls from stats cache only (not parsed from JSONL)
- Token health via `TokenHealthMonitor.assessSessions` (single-pass: returns both current + top 5)

### TokenHealthMonitor (`Services/TokenHealthMonitor.swift`)
- Singleton: `.shared`
- `assessSessions(entries:topLimit:) -> (current: TokenHealthStatus?, top: [TokenHealthStatus])` — **single-pass**: groups entries once via `Dictionary(grouping:)`, assesses all sessions, returns current session health + top N most recent (excludes sessions with no activity in last 24 hours). Default topLimit is 5.
- `assessCurrentSession(entries:) -> TokenHealthStatus?` — convenience wrapper, returns `assessSessions().current`
- `topSessions(entries:limit:) -> [TokenHealthStatus]` — convenience wrapper, returns `assessSessions().top`
- `assessAllSessions(entries:) -> [String: TokenHealthStatus]` — all sessions keyed by sessionId (separate implementation, own grouping pass)
- Groups by sessionId, each session assessed independently
- **Core calculation**: `totalUsed = latestEntry.inputTokens + latestEntry.cacheReadTokens + latestEntry.cacheWriteTokens + sum(all outputTokens)` — input + cache tokens are cumulative (latest entry has total), output tokens are per-message. Each component capped at contextWindow to guard against overflow from corrupted data.
- **Usable window**: `usableWindow = contextWindow × 0.80` — percentages calculated against usable portion
- Band: `< greenThreshold` → green (of usable), `< redThreshold` → orange, else red
- Warnings: high turn count (>15 mild, >25 strong), input:output ratio (>20:1, includes cache tokens)
- Velocity: `totalUsed / duration` if 2+ entries and duration > 60 seconds (no double-counting)
- **Anomaly detection**: three additional warnings:
  - Zero output: `outputTokens == 0 && turnCount > zeroOutputTurnThreshold` → "Session has no output — check for errors"
  - Rapid consumption: `sessionDuration < 60 && totalUsed > 50_000` → "Rapid token consumption detected"
  - Stale session: `lastActivity > staleSessionMinutes * 60 && band != .green` → "Session idle for X min — context may be stale"
- **Session metadata**: extracts projectName from cwd (last path component), gitBranch, sessionStart, sessionDuration. Uses **first** entry with cwd for project name (session identity), **latest** entry for git branch (current state).

### FileWatcher (`Services/FileWatcher.swift`)
- Created per-ViewModel
- Dual watch: DispatchSource on `stats-cache.json` + FSEventStream on `~/.claude/projects/`
- DispatchSource monitors: write, rename, delete events
- FSEventStream flags: `kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes`
- WeakBox wrapper for C callback to prevent retain cycles
- Debounce: 2 seconds via `DispatchWorkItem`
- **Cache invalidation**: debounced handler calls `SessionLogReader.shared.invalidate()` and `StatsCacheReader.shared.invalidate()` before triggering refresh
- Fallback timer: 60 seconds — only starts if both DispatchSource and FSEventStream fail (avoids redundant polling)
- Calls `onChange` closure → triggers `viewModel.refresh()`
- **Stats-cache retry**: if `stats-cache.json` doesn't exist on launch (normal before first `/stats` run), retries with exponential backoff (60s base, doubles each retry, capped at 300s, max 10 retries ~30 min). Counter resets on success or `stopWatching()`
- **Failure logging**: logs via `AppLogger.files.warning` when file descriptors fail to open, projects directory not found, or FSEventStream creation fails — falls back to timer in all cases
- File paths sourced from `ClaudePaths` (centralized)

### NotificationManager (`Services/NotificationManager.swift`)
- Singleton: `.shared`
- `requestPermission()` — no-op (osascript needs no permission)
- `checkStatusAlerts(status:)` — reads `aibattery_alertClaudeAI` and `aibattery_alertClaudeCode` from UserDefaults, fires notification when component is non-operational
- `testAlerts()` — fires fake outage notifications for testing (bypasses toggle state)
- Deduplication: `hasFired[key]` bool per component, resets when service recovers
- **Batch delivery**: queues alerts for 500ms; single alert sent as-is, multiple alerts combined into one notification ("AI Battery: Multiple alerts")
- Delivery: uses `osascript` `display notification` for reliable delivery from unsigned/SPM-built menu bar apps. Process reaping via `waitUntilExit()` on background queue prevents zombie processes.
- Notification: title "AI Battery: {label} is down", body includes status text, default sound

#### Rate Limit Alerts
- `checkRateLimitAlerts(rateLimits:)` — reads `aibattery_alertRateLimit` (Bool) and `aibattery_rateLimitThreshold` (Double, default 80)
- Checks both 5h and 7d windows independently against threshold
- Same dedup pattern: `hasFired[key]` per window, resets when dropping below threshold
- `shouldAlert(percent:threshold:previouslyFired:)` — static pure function for testability

### VersionChecker (`Services/VersionChecker.swift`)
- Singleton: `.shared`
- `checkForUpdate() async -> UpdateInfo?` — fetches GitHub Releases API once per 24h
- `forceCheckForUpdate() async -> UpdateInfo?` — bypasses 24h cache
- `isNewer(_:than:) -> Bool` — static semver comparison (major/minor/patch)
- `stripTag(_:) -> String` — strips leading "v" or "V"
- `currentAppVersion` — reads `CFBundleShortVersionString` from bundle
- `UpdateInfo`: `version: String`, `url: String`
- Cache: `lastCheck: Date?`, `cachedUpdate: UpdateInfo?`
- Timeout: 10 sec

### LaunchAtLoginManager (`Services/LaunchAtLoginManager.swift`)
- Enum (no instances)
- `isEnabled: Bool` — reads `SMAppService.mainApp.status`
- `setEnabled(_:)` — register/unregister via SMAppService
- Requires installed .app bundle, silently fails during dev builds
- Logs failures via `AppLogger.general`

## ViewModel

### UsageViewModel (`ViewModels/UsageViewModel.swift`)
- `@MainActor`, `ObservableObject`
- Published: `snapshot: UsageSnapshot?`, `systemStatus: ClaudeSystemStatus?`, `isLoading: Bool`, `errorMessage: String?`, `lastFreshFetch: Date?`, `isShowingCachedData: Bool`, `availableUpdate: VersionChecker.UpdateInfo?`
- Computed: `metricMode: MetricMode` (from UserDefaults `aibattery_metricMode`), `menuBarPercent: Double` (delegates to `snapshot.percent(for:)`), `hasData: Bool`
- `refresh()`: gets active account + token from `OAuthManager.shared`, passes to `RateLimitFetcher.shared.fetch(accessToken:accountId:)`. Status check runs concurrently via `async let`. After fetch: resolves pending identity (`resolveAccountIdentity`) or updates metadata (`updateAccountMetadata`) from API response. Guards against stale results — discards if active account changed mid-flight. Aggregation runs on the main actor (same thread as FileWatcher cache invalidation — no data races). Calls `NotificationManager.shared.checkStatusAlerts(status:)` and `checkRateLimitAlerts(rateLimits:)`. Checks `VersionChecker.shared.checkForUpdate()` when no update cached. Tracks staleness from API result.
- `switchAccount(to:)` — sets active account, clears snapshot/staleness/errors, triggers refresh.
- `updatePollingInterval(_:)`: invalidates and recreates polling timer
- Init: synchronous local data load (shows data immediately if available), then sets up file watcher, starts polling timer (interval from `aibattery_refreshInterval` UserDefaults, default 60s), triggers async refresh
- Deinit: invalidates timer, stops file watcher
- **Adaptive polling**: tracks `unchangedCycles` counter comparing `totalMessages`/`todayMessages` before and after refresh. After 3 unchanged cycles, doubles polling interval (up to 5 min max). Any data change or file watcher trigger resets to configured interval.
- **Identity timeout**: warns if a pending account hasn't resolved identity after 1 hour (prompts re-auth).
- **JSONL corruption logging**: after aggregation, logs `SessionLogReader.lastCorruptLineCount` via `AppLogger.files.warning` if > 0.

## Utilities

### ClaudePaths (`Utilities/ClaudePaths.swift`)
- Centralized file paths for all Claude Code data locations (`static let` — computed once at load time)
- `statsCache` / `statsCachePath` — `~/.claude/stats-cache.json`
- `projects` / `projectsPath` — `~/.claude/projects/`
- Used by FileWatcher, StatsCacheReader, SessionLogReader, UsageAggregator

### TokenFormatter (`Utilities/TokenFormatter.swift`)
- `format(_ count: Int) -> String` — 500 → "500", 2500 → "2.5K", 15000 → "15K", 3200000 → "3.2M"
- Guards against negative input (returns "0")

### ModelNameMapper (`Utilities/ModelNameMapper.swift`)
- `displayName(for modelId: String) -> String`
- Strips "claude-" prefix, strips trailing date (8+ digits), converts hyphens to dots, capitalizes family
- "claude-opus-4-6-20250929" → "Opus 4.6"

### UserDefaultsKeys (`Utilities/UserDefaultsKeys.swift`)
- Enum with `static let` constants for all `@AppStorage` / `UserDefaults` keys
- All keys prefixed with `aibattery_` to avoid collisions
- Keys: `metricMode`, `refreshInterval`, `tokenWindowDays`, `alertClaudeAI`, `alertClaudeCode`, `chartMode`, `plan`, `accounts`, `activeAccountId`, `launchAtLogin`, `alertRateLimit`, `rateLimitThreshold`, `showCostEstimate`, `showTokens`, `showActivity`, `lastUpdateCheck`, `colorblindMode`, `hasSeenTutorial`

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
- `barNSColor(percent:) -> NSColor` — menu bar icon fill color
- Standard palette: green → yellow → orange → red
- Colorblind palette: blue → cyan → amber → purple (deuteranopia/protanopia safe)

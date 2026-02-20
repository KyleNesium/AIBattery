# Data Layer

Every model struct, service class, and algorithm.

## Models

### UsageSnapshot (`Models/UsageSnapshot.swift`)

Main aggregated data struct consumed by all views.

| Field | Type | Source |
|-------|------|--------|
| `lastUpdated` | `Date` | Generated at aggregation time |
| `rateLimits` | `RateLimitUsage?` | API response headers |
| `displayName` | `String?` | `~/.claude.json` oauthAccount.displayName |
| `organizationName` | `String?` | API header → `~/.claude.json` → UserDefaults |
| `billingType` | `String?` | `~/.claude.json` oauthAccount.organizationBillingType |
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

Computed: `totalTokens`, `planTier: PlanTier?` (from billingType → UserDefaults → nil), `percent(for: MetricMode) -> Double` (shared metric percentage calculation used by both menu bar and popover)

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

### PlanTier (`Models/UsageSnapshot.swift`)

Inferred from `organizationBillingType` in `~/.claude.json`.

| Field | Type |
|-------|------|
| `name` | `String` |
| `price` | `String?` |

`fromBillingType(_ type: String) -> PlanTier?`:

| billingType | Plan | Price |
|-------------|------|-------|
| `"pro"` | Pro | $20/mo |
| `"max"`, `"max_5x"` | Max | $100/mo per seat |
| `"teams"`, `"team"` | Teams | $30/mo per seat |
| `"free"` | Free | nil |
| `"api_evaluation"`, `"api"` | API | Usage-based |
| `""` (empty) | nil | — |
| Other | Capitalized type name | nil |

### APIProfile (`Models/APIProfile.swift`)

Organization info extracted from Messages API response headers.

| Field | Type |
|-------|------|
| `organizationId` | `String?` |
| `organizationName` | `String?` |

`parse(headers:)` static method: reads `anthropic-organization-id` and `x-organization-name` from HTTP response.

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

Computed: `requestsPercentUsed` (binding window utilization × 100), `fiveHourPercent`, `sevenDayPercent`, `bindingReset`, `bindingWindowLabel`, `isThrottled`

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

Computed: `suggestedAction` — nil for green/unknown, recommendation text for orange/red.

### HealthWarning

`id: UUID`, `severity: WarningSeverity` (.mild, .strong), `message: String`, `suggestion: String?`

### TokenHealthConfig (`Models/TokenHealthConfig.swift`)

Instance properties with defaults: `greenThreshold = 60.0`, `redThreshold = 80.0`, `turnCountMild = 15`, `turnCountStrong = 25`, `inputOutputRatioThreshold = 20.0`

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

### ClaudeSystemStatus + StatusIndicator (`Services/StatusChecker.swift`)

`ClaudeSystemStatus`: `indicator: StatusIndicator`, `description: String`, `incidentName: String?`, `statusPageURL: String`, `claudeAPIStatus: StatusIndicator` (default .unknown), `claudeCodeStatus: StatusIndicator` (default .unknown)

`StatusIndicator`: enum with cases `.operational`, `.degradedPerformance`, `.partialOutage`, `.majorOutage`, `.maintenance`, `.unknown`. Has `severity: Int` for comparison (higher = worse). `from(_:)` maps Statuspage API strings to cases — notably `"elevated"` maps to `.degradedPerformance` (yellow). Also used to parse incident impact strings (`"none"`, `"minor"`, `"major"`, `"critical"`).

## Services

### OAuthManager (`Services/OAuthManager.swift`)
- Singleton: `.shared`, `@MainActor ObservableObject`
- Published: `isAuthenticated: Bool`
- OAuth 2.0 PKCE flow with Anthropic (same protocol as Claude Code)
- Client ID: `9d1c250a-e61b-44d9-88ed-5944d1962f5e`
- Auth URL: `https://claude.ai/oauth/authorize`
- Token URL: `https://console.anthropic.com/v1/oauth/token`
- Scopes: `org:create_api_key user:profile user:inference`
- `startAuthFlow()` → opens browser with PKCE challenge
- `exchangeCode(_:) -> Result<Void, AuthError>` → exchanges auth code for access + refresh tokens, returns typed errors. Validates state parameter matches PKCE verifier (CSRF protection).
- `getAccessToken()` → returns valid token (auto-refreshes if expired)
- `signOut()` → clears all stored tokens
- Tokens stored in macOS Keychain under service `"AIBattery"` (separate from Claude Code)
- `AuthError` enum: `.noVerifier`, `.invalidCode`, `.expired`, `.networkError`, `.unknownError(String)` — each has `userMessage` for display
- **Refresh resilience**: network errors during token refresh do NOT mark `isAuthenticated = false` — preserves auth state so retry happens on next refresh cycle. Only auth errors (invalid/revoked tokens) trigger logout.

### RateLimitFetcher (`Services/RateLimitFetcher.swift`)
- Singleton: `.shared`
- `fetch() async -> APIFetchResult` — returns both rate limits and org profile from a single API call
- POST `/v1/messages?beta=true` with `max_tokens: 1`, content `"."`
- Model fallback list: tries `claude-sonnet-4-5-20250929` first, falls back to `claude-haiku-3-5-20241022`. Remembers last working model index to avoid repeated fallbacks.
- Headers: `Authorization: Bearer {token}`, `anthropic-version: 2023-06-01`, `anthropic-beta: oauth-2025-04-20,interleaved-thinking-2025-05-14`, `User-Agent: AIBattery/1.0.2 (macOS)`
- Gets access token from `OAuthManager.shared.getAccessToken()` (auto-refreshes if expired)
- Timeout: 15 sec
- Parses `anthropic-ratelimit-unified-*` response headers via `RateLimitUsage.parse(headers:)` and `APIProfile.parse(headers:)` from the same response
- Caches last successful `APIFetchResult`; returns cached on network error or auth failure (with `isCached: true`, preserving original `fetchedAt`). Cache expires after 1 hour (`cacheMaxAge = 3600s`) to avoid showing very old data.
- Model unavailable (400/404 with model/access error message) → tries next model in list

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
- **Backoff**: on failure, skips fetches for 60 seconds (`backoffInterval = 60`) to avoid noise; clears on success

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
- FileHandle streaming: 64KB buffer, line-by-line
- Pre-filter: byte search for `"type":"assistant"` AND `"usage"` before JSON decode
- **Decode error logging**: when pre-filter matches but JSON decode fails, logs via `AppLogger.files.debug` with filename and error description
- **Trailing line safety**: remaining data after last newline is only processed if it ends with `}` (skips incomplete/partial writes still being written)
- Mod-time + file-size cache to skip unchanged files
- **Result-level caching**: caches the merged `[AssistantUsageEntry]` result; invalidated by FileWatcher via `invalidate()`. Avoids re-sorting and re-deduplicating on every refresh.
- **Discovery caching**: caches discovered JSONL file list with parent directory modification dates; re-scans only when directory contents change.
- **Cache eviction**: evicts oldest entries when cache exceeds 200 files (`maxCacheEntries`) using O(n) single-pass min-find (not sort)
- Deduplication by messageId within each file
- Sorted by timestamp ascending

### UsageAggregator (`Services/UsageAggregator.swift`)
- Created per-ViewModel (not singleton)
- `aggregate(rateLimits:orgName:) -> UsageSnapshot`
- **Single-pass filtering**: iterates all entries once to extract both today's entries and windowed token totals simultaneously (avoids separate `.filter()` passes)
- Reads: stats cache, all JSONL entries (single scan), account info from `~/.claude.json` (displayName, organizationName, organizationBillingType)
- **Token window modes**: `aibattery_tokenWindowDays` UserDefaults (0 = all time, 1–7 = windowed)
  - **All-time mode (0)**: stats-cache `modelUsage` + uncached JSONL, anti-double-counting for dates already in stats cache, 72-hour recent model filter
  - **Windowed mode (1–7)**: computes token totals from all JSONL entries within the window, bypasses stats-cache `modelUsage`
- **Non-Claude model filter**: excludes model IDs that don't start with `"claude-"` (e.g. `"synthetic"`)
- Tool calls from stats cache only (not parsed from JSONL)
- Token health via `TokenHealthMonitor.assessCurrentSession` (single) + `TokenHealthMonitor.topSessions` (top 5)
- **Org name priority**: API header → `~/.claude.json` → UserDefaults
- **Org name persistence**: writes API-sourced org name to `UserDefaults("aibattery_orgName")` for future sessions — only when user hasn't manually set one (protects user-edited values)

### TokenHealthMonitor (`Services/TokenHealthMonitor.swift`)
- Singleton: `.shared`
- `assessCurrentSession(entries:) -> TokenHealthStatus?` — most recent session only
- `topSessions(entries:limit:) -> [TokenHealthStatus]` — top N sessions sorted by most recent activity (newest first); excludes archived sessions (no activity in last 24 hours). Default limit is 5
- `assessAllSessions(entries:) -> [String: TokenHealthStatus]` — all sessions keyed by sessionId
- Groups by sessionId, each session assessed independently
- **Core calculation**: `totalUsed = latestEntry.inputTokens + latestEntry.cacheReadTokens + latestEntry.cacheWriteTokens + sum(all outputTokens)` — input + cache tokens are cumulative (latest entry has total), output tokens are per-message. Each component capped at contextWindow to guard against overflow from corrupted data.
- **Usable window**: `usableWindow = contextWindow × 0.80` — percentages calculated against usable portion
- Band: `< greenThreshold` → green (of usable), `< redThreshold` → orange, else red
- Warnings: high turn count (>15 mild, >25 strong), input:output ratio (>20:1, includes cache tokens)
- Velocity: `totalUsed / duration` if 2+ entries and duration > 60 seconds (no double-counting)
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
- **Failure logging**: logs via `AppLogger.files.warning` when file descriptors fail to open, projects directory not found, or FSEventStream creation fails — falls back to timer in all cases

### NotificationManager (`Services/NotificationManager.swift`)
- Singleton: `.shared`
- `requestPermission()` — no-op (osascript needs no permission)
- `checkStatusAlerts(status:)` — reads `aibattery_alertClaudeAI` and `aibattery_alertClaudeCode` from UserDefaults, fires notification when component is non-operational
- `testAlerts()` — fires fake outage notifications for testing (bypasses toggle state)
- Deduplication: `hasFired[key]` bool per component, resets when service recovers
- Delivery: uses `osascript` `display notification` for reliable delivery from unsigned/SPM-built menu bar apps
- Notification: title "AI Battery: {label} is down", body includes status text, default sound

## ViewModel

### UsageViewModel (`ViewModels/UsageViewModel.swift`)
- `@MainActor`, `ObservableObject`
- Published: `snapshot: UsageSnapshot?`, `systemStatus: ClaudeSystemStatus?`, `isLoading: Bool`, `errorMessage: String?`, `lastFreshFetch: Date?`, `isShowingCachedData: Bool`
- Computed: `metricMode: MetricMode` (from UserDefaults `aibattery_metricMode`), `menuBarPercent: Double` (delegates to `snapshot.percent(for:)`), `hasData: Bool`
- `refresh()`: single API call via `RateLimitFetcher.shared.fetch()` returns both rate limits and org profile. `async let` for API + status concurrently, then `Task.detached` for aggregation on background thread. Passes `orgName` from API response to aggregator. After updating snapshot, calls `NotificationManager.shared.checkStatusAlerts(status:)` to check for outages. Tracks `isCached` and `fetchedAt` from API result for staleness indicator. Sets `errorMessage` when API returns no data and no local data exists.
- `updatePollingInterval(_:)`: invalidates and recreates polling timer
- Init: synchronous local data load (shows data immediately if available), then sets up file watcher, starts polling timer (interval from `aibattery_refreshInterval` UserDefaults, default 60s), triggers async refresh
- Deinit: invalidates timer, stops file watcher

## Utilities

### TokenFormatter (`Utilities/TokenFormatter.swift`)
- `format(_ count: Int) -> String` — 500 → "500", 2500 → "2.5K", 15000 → "15K", 3200000 → "3.2M"

### ModelNameMapper (`Utilities/ModelNameMapper.swift`)
- `displayName(for modelId: String) -> String`
- Strips "claude-" prefix, strips trailing date (8+ digits), converts hyphens to dots, capitalizes family
- "claude-opus-4-6-20250929" → "Opus 4.6"

### UserDefaultsKeys (`Utilities/UserDefaultsKeys.swift`)
- Enum with `static let` constants for all `@AppStorage` / `UserDefaults` keys
- All keys prefixed with `aibattery_` to avoid collisions
- Keys: `metricMode`, `orgName`, `displayName`, `refreshInterval`, `tokenWindowDays`, `alertClaudeAI`, `alertClaudeCode`, `chartMode`, `plan`

### AppLogger (`Utilities/AppLogger.swift`)
- Enum with `static let` `os.Logger` instances, subsystem `com.KyleNesium.AIBattery`
- Categories: `general`, `oauth`, `network`, `files`
- Used throughout services for structured logging (replaces bare `print()` calls)

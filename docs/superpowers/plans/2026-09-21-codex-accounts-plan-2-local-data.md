# Codex Accounts — Plan 2: Local Data Layer + Insights Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** With a Codex account active, every popover section (bars, Insights charts, per-model cost, Projects, Context Health, status dot, footer links, notifications) is Codex-sourced — closing the "interim state" Plan 1 left (Codex bars + Claude Insights) so PR #193 can leave draft.

**Architecture:** Provider seams on the existing pipeline (spec Approach A). A new `CodexSessionLogReader` produces the *existing* `AssistantUsageEntry` from `~/.codex/sessions` rollout JSONL, so `UsageAggregator` runs unchanged structurally — it becomes provider-parameterised (model-ID filter, optional stats cache). `UsageViewModel` owns one aggregator per provider and routes by the active account's provider. `StatusChecker` becomes instance-configurable (Claude + OpenAI feeds). `UsageSnapshot` carries `provider` so views label themselves without new plumbing.

**Tech Stack:** Swift 6 / SwiftUI, SPM, Swift Testing (`import Testing`, `@testable import AIBatteryCore`), FileHandle streaming, FSEvents.

**Spec:** `docs/superpowers/specs/2026-09-02-codex-support-design.md` (§4 Local data layer, §5 UI status feed, §6 Error handling, §7 Testing, "Spec/code sync obligations"). Plan 1 ledger with the deferred items: `.superpowers/sdd/2026-09-02-codex-accounts-plan-1-foundation/progress.md` (F7–F10 + residual nits).

## Global Constraints

- macOS 13+, Swift 6 strict concurrency, zero new warnings; `swiftformat AIBattery/ AIBatteryApp/ Tests/` + `swiftlint` clean before every push.
- JSONL reads are **token-count-only**: `response_item` lines are never decoded (privacy). FileHandle streaming, 64 KB chunks, 1 MB leftover cap, trailing partial line skipped. Never load a whole session file.
- `~/.codex` is **read-only**. No writes.
- Cost framing everywhere is **"API-equivalent cost"** (subscription value), never a bill.
- Headless-CI rules: no dynamic `NSColor` equality off-main; new tests never touch `SparkleUpdateService.shared`; `UsageViewModel` is never constructed in tests.
- `Result<Void, AuthError>` contracts and every Plan 1 hardening (spike filter, rollover guard, write-back routing) stay intact.
- README "Test Coverage" table updated in the same commit as any test change; `CLAUDE.md` test/file counts updated at wrap-up.
- One integration branch (`feat/codex-accounts`), one PR (#193). No push to `main`. Commit per task, `<type>: <description>`, **no Co-Authored-By trailers**.
- Model-ID prefixes: Claude entries `claude-`, Codex entries `gpt-` (observed locally: `gpt-5.4`, `gpt-5.6-sol`).

---

## File Structure

| Action | Path | Responsibility |
|---|---|---|
| Create | `AIBattery/Services/UsageEntrySource.swift` | Protocol `UsageEntrySource` (readAllUsageEntries / invalidate / lastCorruptLineCount) — the aggregator's reader seam |
| Create | `AIBattery/Services/CodexSessionLogParser.swift` | Pure per-file state machine: `session_meta` → identity, `turn_context` → model, `token_count` → `AssistantUsageEntry` (spec §4 mapping) |
| Create | `AIBattery/Services/CodexSessionLogReader.swift` | Discovery under `~/.codex/sessions`, fingerprint cache, streaming, eviction — sibling of `SessionLogReader` |
| Create | `AIBattery/Models/OpenAIModelPricing.swift` | `gpt-*` pricing table (per-1M rates fetched 2026-09-21 from developers.openai.com/api/docs/pricing) |
| Create | `AIBattery/Services/OpenAIStatusFeed.swift` | Codex component IDs on status.openai.com + `StatusChecker.codex` instance |
| Modify | `AIBattery/Services/SessionLogReader.swift` | Conform to `UsageEntrySource` |
| Modify | `AIBattery/Services/UsageAggregator.swift` | `provider` param, optional stats cache, prefix filter, `firstSessionDate` fallback, `SideEffects.provider`, `UsageSnapshot.provider` |
| Modify | `AIBattery/Models/UsageSnapshot.swift` | `let provider: AIProvider` (+ Equatable) |
| Modify | `AIBattery/Models/ModelPricing.swift` | Route `gpt-` IDs to `OpenAIModelPricing` |
| Modify | `AIBattery/Utilities/ModelNameMapper.swift` | `gpt-5.6-sol` → "GPT-5.6 Sol" |
| Modify | `AIBattery/Models/TokenHealthConfig.swift` | `gpt-` family context window (258 400, from `model_context_window` in Codex logs) |
| Modify | `AIBattery/Services/StatusChecker.swift`, `AIBattery/Models/ClaudeSystemStatus.swift` | Instance config (URL, page URL, components, component filter); `parseStatus` takes them |
| Modify | `AIBattery/Services/NotificationManager.swift` | Provider-aware window labels (F7); status alerts iterate the feed's components |
| Modify | `AIBattery/Services/CodexRateLimitFetcher.swift` | Endpoint backoff `RetryPolicy.statusCheck` per account (F9) |
| Modify | `AIBattery/Services/FileWatcher.swift` | Second FSEventStream on `CodexPaths.sessionsPath` |
| Modify | `AIBattery/ViewModels/UsageViewModel.swift`, `+Lifecycle.swift` | Per-provider aggregator routing, remove `accountId: nil` gating, provider-aware status checker, `repaintCachedNotFresh` routing, both readers in corruption log |
| Modify | `AIBattery/Views/UsagePopoverView.swift`, `PopoverFooterView.swift`, `LocalEstimateSection.swift`, `InsightsRowsAndHover.swift`, `TutorialOverlay.swift`, `UsageGateViews.swift` | Provider-aware links, labels, All-Time caveat |
| Modify | `AIBattery/Views/AuthView.swift` | `cliLoginAvailable` off the render path (F8) |
| Modify | `AIBattery/Services/CodexOAuth/CodexAuthSession.swift` | Buffer an early callback (F10) |
| Modify | `spec/*.md`, `README.md`, `CLAUDE.md`, design spec §4 | Sync |
| Delete | `AGENTS.md` | Accidental sed copy of CLAUDE.md ("Claude"→"Codex") |
| Tests | `Tests/AIBatteryCoreTests/Services/CodexSessionLogParserTests.swift`, `CodexSessionLogReaderTests.swift`, `OpenAIStatusFeedTests.swift`, `StatusCheckerComponentFilterTests.swift`, `CodexRateLimitFetcherBackoffTests.swift`; extend `ModelPricingTests`, `ModelNameMapperTests`, `TokenHealthConfigTests`, `UsageAggregatorTests`, `NotificationManagerTests`, `UsageSnapshotTests` | |

---

### Task 1: `UsageEntrySource` seam + `UsageAggregator` provider parameter

**Files:**
- Create: `AIBattery/Services/UsageEntrySource.swift`
- Modify: `AIBattery/Services/SessionLogReader.swift` (conformance only)
- Modify: `AIBattery/Services/UsageAggregator.swift`
- Modify: `AIBattery/Models/UsageSnapshot.swift`
- Test: `Tests/AIBatteryCoreTests/Services/UsageAggregatorTests.swift`, `Tests/AIBatteryCoreTests/Models/UsageSnapshotTests.swift`

**Interfaces:**
- Produces:
  ```swift
  protocol UsageEntrySource: AnyObject, Sendable {
      func readAllUsageEntries() -> [AssistantUsageEntry]
      func invalidate()
      var lastCorruptLineCount: Int { get }
  }
  // UsageAggregator
  init(statsCacheReader: StatsCacheReader?, sessionLogReader: any UsageEntrySource, ledger: TokenLedger = .shared, provider: AIProvider = .claude)
  convenience init(provider: AIProvider = .claude)   // .claude → (.shared, SessionLogReader.shared); .codex → (nil, CodexSessionLogReader.shared)  [CodexSessionLogReader lands in Task 3; until then the convenience init only handles .claude]
  static func isTrackedModel(_ modelId: String, provider: AIProvider) -> Bool  // "claude-" / "gpt-" prefix
  struct SideEffects { activeUserModel, observedModels, accountId, provider: AIProvider }
  // UsageSnapshot
  let provider: AIProvider   // default .claude in the memberwise init via a trailing parameter
  ```
- Consumers: Task 3 (`CodexSessionLogReader: UsageEntrySource`), Task 6 (VM), Task 8 (views read `snapshot.provider`).

- [ ] **Step 1: Failing tests** — in `UsageAggregatorTests` add:
  - `isTrackedModel_claudeProvider_acceptsClaudeOnly` (`claude-opus-4-6` true, `gpt-5.4` false, `synthetic` false)
  - `isTrackedModel_codexProvider_acceptsGPTOnly`
  - `aggregate_codexProvider_noStatsCache_usesJSONLOnly`: temp JSONL dir is irrelevant here — use a `StubEntrySource` (test-local class conforming to `UsageEntrySource`, returns two `gpt-5.4` entries + one `claude-…` entry); `UsageAggregator(statsCacheReader: nil, sessionLogReader: stub, ledger: TokenLedger(fileURL: temp), provider: .codex)`; expect `modelTokens` contains only `gpt-5.4`, `totalMessages == 3` (message counts are provider-agnostic today — keep), `snapshot.provider == .codex`, `firstSessionDate == earliest entry timestamp`, `longestSessionDuration == nil`, `effects.provider == .codex`.
  - `aggregate_claudeProvider_firstSessionDate_fallsBackToEarliestEntryWhenNoStatsCache`.
  - In `UsageSnapshotTests`: `equality_differsOnProvider` (two otherwise-identical snapshots, `.claude` vs `.codex`, `!=`).
- [ ] **Step 2:** `swift test --filter UsageAggregatorTests` → compile failure (no `provider:` init).
- [ ] **Step 3: Implement.**
  - New file with the protocol; `extension SessionLogReader: UsageEntrySource {}` (it already has the three members).
  - Aggregator: store `provider`; `statsCacheReader` optional (`statsCacheReader?.lastModificationDate`, `statsCacheReader?.read()`); replace the three `hasPrefix("claude-")` with `Self.isTrackedModel(entry.model, provider: provider)`; `buildModelTokens(from:provider:)` filter; `firstSessionDate = statsCache?.firstSessionDate.flatMap(iso) ?? allEntries.first?.timestamp`; pass `provider` into `UsageSnapshot` and `SideEffects`.
  - `UsageSnapshot`: add `let provider: AIProvider` as the **last** memberwise field with default `.claude` (Swift memberwise inits honour property defaults) and include in `==`.
- [ ] **Step 4:** `swift test --filter "UsageAggregator|UsageSnapshot"` → PASS; `swift build` clean.
- [ ] **Step 5:** Commit `refactor: provider-parameterise UsageAggregator behind a UsageEntrySource seam`.

---

### Task 2: `CodexSessionLogParser` (pure state machine, TDD)

**Files:**
- Create: `AIBattery/Services/CodexSessionLogParser.swift`
- Test: `Tests/AIBatteryCoreTests/Services/CodexSessionLogParserTests.swift`

**Interfaces:**
```swift
/// Per-file parse state. NOT thread-safe; one instance per file parse.
struct CodexSessionLogParser {
    private(set) var sessionId: String?      // session_meta.payload.id ?? .session_id
    private(set) var cwd: String?
    private(set) var gitBranch: String?      // session_meta.payload.git.branch
    private(set) var currentModel: String?   // last turn_context.payload.model
    private(set) var corruptLineCount = 0
    let fallbackSessionId: String            // file stem, used when session_meta is absent
    init(fallbackSessionId: String)
    /// Feed one complete JSONL line (no trailing newline). Returns an entry only for a
    /// token_count line with non-null `info.last_token_usage` and a known model.
    mutating func consume(line: Data, lineIndex: Int) -> AssistantUsageEntry?
    /// Byte pre-filter — cheap reject before JSON decode.
    static func mightBeRelevant(_ line: Data) -> Bool   // contains "session_meta", "turn_context" or "token_count"
}
```
Mapping (spec §4, amended in Task 10 for cache-write): `inputTokens = max(0, input − cached − cacheWrite)`, `cacheReadTokens = cached`, `cacheWriteTokens = cache_write`, `outputTokens = output`, `model = currentModel`, `sessionId`/`cwd`/`gitBranch` from state, `timestamp` = the line's top-level `timestamp` (ISO8601 fractional, `DateFormatters.iso8601`), `messageId = "\(sessionId):\(ordinal ?? lineIndex)"`, `toolCallCount = 0`. Decoding uses `JSONSerialization` (payload shapes vary; numbers may arrive as `Int` or `NSNumber` — mirror `CodexUsageParser`'s `NSNumber` handling).

- [ ] **Step 1: Failing tests** (fixtures lifted from a real 2026-09 rollout file, redacted):
  - `sessionMeta_setsIdentity` — id, cwd, git.branch parsed.
  - `tokenCount_beforeTurnContext_isSkipped` — no model yet → nil, `corruptLineCount` unchanged (not corrupt, just unattributable).
  - `tokenCount_afterTurnContext_mapsFields` — input 31 894, cached 21 376, cache_write 0, output 233 → entry(input 10 518, cacheRead 21 376, cacheWrite 0, output 233, model `gpt-5.4`, messageId `<sid>:21`, cwd, timestamp equal to `2026-09-03T13:10:58.838Z`).
  - `tokenCount_cacheWriteSubtractedAndClamped` — input 100, cached 80, cache_write 30 → input 0.
  - `tokenCount_nullInfo_isSkipped` — `"info":null` (rate-limit-only event) → nil.
  - `responseItem_isNeverDecoded` — a `response_item` line containing `"token_count"` inside message text still returns nil AND `mightBeRelevant` is allowed to be true (pre-filter only) — assert the decode path checks `type` first.
  - `malformedJSON_countsCorrupt`.
  - `missingSessionMeta_usesFallbackSessionId`.
  - `turnContext_switchesModelMidFile` — two turn_contexts, entries carry the latest model.
- [ ] **Step 2:** run → compile failure.
- [ ] **Step 3: Implement** per interface. Only three `type` values are inspected; everything else returns nil without touching `payload`.
- [ ] **Step 4:** run → PASS.
- [ ] **Step 5:** Commit `feat: add CodexSessionLogParser mapping rollout token_count events to AssistantUsageEntry`.

---

### Task 3: `CodexSessionLogReader` (discovery + cache + streaming)

**Files:**
- Create: `AIBattery/Services/CodexSessionLogReader.swift`
- Modify: `AIBattery/Services/UsageAggregator.swift` (convenience init `.codex` branch)
- Test: `Tests/AIBatteryCoreTests/Services/CodexSessionLogReaderTests.swift`

**Interfaces:**
```swift
final class CodexSessionLogReader: @unchecked Sendable, UsageEntrySource {
    static let shared = CodexSessionLogReader()
    init(sessionsURL: URL? = nil)             // default CodexPaths.sessions
    func readAllUsageEntries() -> [AssistantUsageEntry]
    func invalidate()
    private(set) var lastCorruptLineCount: Int
    static let discoveryTTL: TimeInterval = 60
    func cacheEntriesWithLiveEntriesCountForTesting() -> Int
}
```
Behaviour mirrors `SessionLogReader` exactly: NSLock + `pendingInvalidation` `AtomicBool`, `FileCacheEntry` fingerprint (modDate + fileSize) with `entries` released for files not modified today, incremental `rebuild(base:)`, stale-file purge by messageId, ascending sort. Discovery: `FileManager.enumerator` over the root (depth is `YYYY/MM/DD/*.jsonl`), `.jsonl` only, regular-file check, **symlink boundary** (resolved path must stay under the resolved root), TTL 60 s + root-dir mod-date check (the nested date dirs make per-dir mtimes unhelpful — use TTL + `.skipsHiddenFiles`). Streaming: 64 KB chunks, `mightBeRelevant` pre-filter, 1 MB oversized-line discard (`lastCorruptLineCount += 1`), trailing partial line only if it ends with `}`. Fallback session id = file name without extension.

- [ ] **Step 1: Failing tests** (temp dir `codex-reader-<UUID>/2026/09/21/rollout-a.jsonl` etc.):
  - `readsEntriesAcrossNestedDateDirs` (two files, two days → 3 entries sorted ascending).
  - `unchangedFile_isNotReparsed` (write, read, read again → same count; mutate file → `invalidate()` → new entry appears).
  - `deletedFile_entriesRemoved`.
  - `evictsOldFileEntries` (set modDate yesterday → live count 0 after read).
  - `skipsTrailingPartialLine`.
  - `symlinkOutsideRoot_isIgnored`.
  - `invalidateDuringScan_marksDirty` — skip if it would need timing; instead test `invalidate()` before first read leaves `isDirty` semantics (read returns fresh data).
- [ ] **Step 2:** run → compile failure.
- [ ] **Step 3: Implement**; add `case .codex: self.init(statsCacheReader: nil, sessionLogReader: CodexSessionLogReader.shared, provider: .codex)` to the aggregator convenience init.
- [ ] **Step 4:** run → PASS.
- [ ] **Step 5:** Commit `feat: add CodexSessionLogReader streaming ~/.codex/sessions with fingerprint cache`.

---

### Task 4: OpenAI pricing, display names, context window

**Files:**
- Create: `AIBattery/Models/OpenAIModelPricing.swift`
- Modify: `AIBattery/Models/ModelPricing.swift`, `AIBattery/Utilities/ModelNameMapper.swift`, `AIBattery/Models/TokenHealthConfig.swift`
- Test: extend `ModelPricingTests`, `ModelNameMapperTests`, `TokenHealthConfigTests`

**Interfaces:**
```swift
enum OpenAIModelPricing {
    /// Longest-prefix match on the lowercased model ID. cacheWrite billed at input rate
    /// (OpenAI has no separate cache-write price); cacheRead = cached-input rate.
    static func pricing(for modelId: String) -> ModelPricing?
    static let table: [(prefix: String, pricing: ModelPricing)]  // ordered longest prefix first
}
```
Table ($/1M, fetched 2026-09-21): `gpt-5.6-sol` 4.00/20.00 cached 0.40 · `gpt-5.6-terra` 2.00/12.00 cached 0.20 · `gpt-5.6-luna` 0.20/1.20 cached 0.02 · `gpt-5.5` 5.00/30.00 cached 0.50 · `gpt-5.4` 2.50/15.00 cached 0.25 · `gpt-5.3-codex` 1.75/14.00 cached 0.175 · `gpt-5.2-pro` 21/168 cached 21 · `gpt-5.2` 1.75/14.00 cached 0.175 · `gpt-5.1` 1.25/10 cached 0.125 · `gpt-5-pro` 15/120 cached 15 · `gpt-5-mini` 0.25/2 cached 0.025 · `gpt-5-nano` 0.05/0.40 cached 0.005 · `gpt-5-codex` 1.25/10 cached 0.125 · `gpt-5` 1.25/10 cached 0.125.

- [ ] **Step 1: Failing tests:** `pricing_gpt54`, `pricing_gpt56Sol_longestPrefixWins` (not gpt-5), `pricing_gpt5Mini`, `pricing_unknownGPT_isNil` (`gpt-4o`); `displayName_gpt54 == "GPT-5.4"`, `displayName_gpt56Sol == "GPT-5.6 Sol"`, `displayName_gpt5Mini == "GPT-5 Mini"`, `displayName_gpt53Codex == "GPT-5.3 Codex"`; `contextWindow_gptFamily == 258_400`, existing Claude lookups unchanged.
- [ ] **Step 2:** run → FAIL.
- [ ] **Step 3: Implement.** `ModelPricing.pricing(for:)`: before the Claude scan, `if modelId.lowercased().hasPrefix("gpt-") { result = OpenAIModelPricing.pricing(for: modelId) }` (keep cache). `ModelNameMapper.computeDisplayName`: `gpt-` branch → `"GPT-" + version + " " + remaining parts capitalised`. `TokenHealthConfig.contextWindow(for:)`: after exact/prefix miss, `if model.hasPrefix("gpt-") { return openAIDefaultContextWindow }` with `static let openAIDefaultContextWindow = 258_400`.
- [ ] **Step 4:** run → PASS.
- [ ] **Step 5:** Commit `feat: add OpenAI gpt-5.x pricing, display names and context window`.

---

### Task 5: Status feed generalisation + OpenAI feed

**Files:**
- Modify: `AIBattery/Services/StatusChecker.swift`, `AIBattery/Models/ClaudeSystemStatus.swift`
- Create: `AIBattery/Services/OpenAIStatusFeed.swift`
- Modify: `AIBattery/Services/NotificationManager.swift` (status alerts take components)
- Test: `Tests/AIBatteryCoreTests/Services/StatusCheckerComponentFilterTests.swift`, `OpenAIStatusFeedTests.swift`

**Interfaces:**
```swift
struct StatusFeedConfig: Sendable {
    let summaryURL: URL
    let statusPageBaseURL: String
    let knownComponents: [StatusComponent]
    /// nil → consider every component in the summary (Claude, unchanged). Non-nil → only these IDs
    /// drive the worst-indicator / description / incident escalation (OpenAI's page lists 25+ unrelated products).
    let componentFilter: Set<String>?
    static let claude: StatusFeedConfig
    static let codex: StatusFeedConfig   // https://status.openai.com/api/v2/summary.json, page https://status.openai.com
}
@MainActor final class StatusChecker {
    static let shared = StatusChecker(config: .claude)
    static let codex  = StatusChecker(config: .codex)
    init(config: StatusFeedConfig)
    let config: StatusFeedConfig
    nonisolated static let statusPageBaseURL = "https://status.claude.com"   // kept for ClaudeSystemStatus.unknown + legacy callers
    static func shared(for provider: AIProvider) -> StatusChecker
    nonisolated static func fetchAndParse(config: StatusFeedConfig, timeout: TimeInterval) async -> FetchOutcome
    nonisolated static func parseStatus(_ summary: StatusPageSummary, config: StatusFeedConfig) -> ClaudeSystemStatus  // internal (not fileprivate) so tests can build summaries; StatusPageSummary etc. become internal structs
}
// ClaudeSystemStatus
static func unknown(statusPageURL: String) -> ClaudeSystemStatus
```
Codex components (IDs read live 2026-09-21): Codex API `01KMP3KP5MGE23B80K1EK4S8PV` (alertKey `codexAPI`), CLI `01KMKFAMWKNQ84Z1766MV08ZDE` (`codexCLI`), Codex in ChatGPT Desktop `01KMKFAMWKQ81YWSE1Z18R6VHR` (`codexDesktop`), Codex Web `01JVCV8YSWZFRSM1G5CVP253SK` (`codexWeb`), VS Code extension `01KMP3KP5M8X0EBTVW6KN327EE` (`codexVSCode`). Incidents: `StatusPageIncident` gains `components: [StatusPageComponent]?`; with a filter, an incident counts only when it lists a filtered component (or lists none).
`NotificationManager.checkStatusAlerts(status:components:)` — iterate the passed components (default `StatusChecker.knownComponents` stays for `testAlerts`).

- [ ] **Step 1: Failing tests:** `parse_filter_ignoresUnrelatedComponentOutage` (Sora major_outage + Codex API operational + filter → `.operational`, description "All Systems Operational"); `parse_filter_flagsFilteredComponent`; `parse_noFilter_behavesAsBefore`; `parse_incidentOnUnfilteredComponent_isIgnored`; `codexConfig_hasFiveComponents_andOpenAIURLs`; `statusPageURL_propagatesFromConfig`.
- [ ] **Step 2:** run → FAIL.
- [ ] **Step 3: Implement**; keep `StatusChecker.shared` behaviour byte-identical for Claude (filter nil).
- [ ] **Step 4:** run → PASS + full `StatusChecker*Tests`.
- [ ] **Step 5:** Commit `feat: make StatusChecker feed-configurable and add the OpenAI Codex status feed`.

---

### Task 6: Codex endpoint backoff (F9) + F7 notification vocab

**Files:**
- Modify: `AIBattery/Services/CodexRateLimitFetcher.swift`, `AIBattery/Services/NotificationManager.swift`
- Test: `Tests/AIBatteryCoreTests/Services/CodexRateLimitFetcherBackoffTests.swift`, extend `NotificationManagerTests`

**Interfaces:**
```swift
// CodexRateLimitFetcher
struct EndpointBackoff { var failureCount = 0; var lastFailedAt: Date?; var currentDelay: TimeInterval = 0 }
private var backoff: [String: EndpointBackoff]
nonisolated static func shouldSkipEndpoint(_ b: EndpointBackoff, now: Date) -> Bool
nonisolated static func recordingFailure(_ b: EndpointBackoff, now: Date, policy: RetryPolicy = .statusCheck) -> EndpointBackoff
func isInBackoffForTesting(accountId: String, now: Date = Date()) -> Bool
// NotificationManager
func checkRateLimitAlerts(rateLimits:)  // labels: "5-Hour" and rateLimits.provider.secondaryWindowLabel
```
`fetch`: if `shouldSkipEndpoint` → `sessionLogFallback` directly (no request). On `.unavailable` or transport error → `recordingFailure`; on `.success`/`.authFailed` → reset (auth failures have their own counter).

- [ ] **Step 1: Failing tests:** `backoff_firstFailure_60s±20%`, `backoff_doubles_capped300`, `shouldSkip_withinWindow_true_afterWindow_false`, `success_resetsBackoff`; `notification_codexLabel_isWeekly` (pure: expose `nonisolated static func windowLabels(for: AIProvider) -> (String, String)` and test it).
- [ ] **Step 2:** FAIL. **Step 3:** implement. **Step 4:** PASS.
- [ ] **Step 5:** Commit `fix: back off the Codex usage endpoint after failures and label Codex alerts Weekly`.

---

### Task 7: `FileWatcher` second root + `UsageViewModel` provider routing

**Files:**
- Modify: `AIBattery/Services/FileWatcher.swift`, `AIBattery/ViewModels/UsageViewModel.swift`, `AIBattery/ViewModels/UsageViewModel+Lifecycle.swift`

**Interfaces:**
```swift
// FileWatcher
nonisolated(unsafe) private var codexFsEventStream: FSEventStreamRef?
private func watchCodexSessionsDirectory()   // no-op (no fallback timer) when ~/.codex/sessions is absent
// debounceNotify gains invalidateCodexSessionLog: Bool
// UsageViewModel
let aggregator = UsageAggregator(provider: .claude)
let codexAggregator = UsageAggregator(provider: .codex)
func aggregator(for provider: AIProvider) -> UsageAggregator
func aggregateOffMain(rateLimits:, rateLimitSource:, standardLimits:, accountId:, provider: AIProvider = .claude, rateLimitsFresh:) async -> UsageSnapshot
```
Changes:
1. `aggregateOffMain` picks the aggregator by `provider`; applies `RateLimitFetcher.shared.activeUserModel/setObservedModels` **only when `effects.provider == .claude`**.
2. `init`, `refresh()` (wasEmpty paint, main aggregate, offline path, unauthenticated path), `refreshLocalData()`, `repaintCachedNotFresh()`: pass `provider: accountProvider` and the **real** `accountId` for Codex (delete the three "Codex has no local data layer yet" `nil` gates and comments).
3. `LocalUsageEstimate.calibrate` gate `accountProvider != .codex` removed (Codex local tokens are now Codex-derived).
4. `repaintCachedNotFresh`: route `cachedOrEmpty` by provider (bug: wake/unlock repaint ignored Codex cache).
5. `fetchAPIData`: `StatusChecker.shared(for: provider).fetchStatus()`; `handlePostFetchAlerts` passes `StatusChecker.shared(for:).config.knownComponents`.
6. `logCorruptionMetrics`: sum both readers.
7. `setupFileWatcher` closure invalidates both aggregators.
8. `switchAccount`: also `systemStatus = nil` (feed changes with provider).

- [ ] **Step 1:** `swift build` — no unit tests can construct the VM; rely on build + existing `UsageViewModelTests` (statics) staying green. Add `UsageAggregatorTests.convenienceInit_codex_hasNoStatsCacheAndCodexProvider`.
- [ ] **Step 2–4:** implement; `swift build && swift test`.
- [ ] **Step 5:** Commit `feat: route local data, status feed and file watching by the active account's provider`.

---

### Task 8: Provider-aware views

**Files:**
- Modify: `UsagePopoverView.swift` (pass `snapshot.provider` / active provider to footer + LocalEstimateSection), `PopoverFooterView.swift` (`provider` param: Usage link `https://claude.ai/settings/usage` vs `https://chatgpt.com/codex/settings/usage` — verify in smoke test; Status link uses `systemStatus?.statusPageURL ?? StatusChecker.shared(for: provider).config.statusPageBaseURL`; logout hint "Sign out of active \(provider.displayName) account"), `LocalEstimateSection.swift` (`provider` param → `secondaryWindowLabel`), `InsightsRowsAndHover.swift` (All Time tooltip for Codex: "Cumulative tokens across retained Codex session logs (no lifetime cache — bounded by log retention)"), `TutorialOverlay.swift` (provider-neutral copy), `UsageGateViews.swift` (no change unless needed).
- Test: extend `PopoverFooterStatusSymbolTests` with a pure `PopoverFooterView.usageDashboardURL(for: AIProvider)` test; `LocalEstimateSection` label via a pure static `windowLabel(_ mode: MetricMode, provider: AIProvider)`.

- [ ] Steps 1–4 as above (tests → fail → implement → pass; build + launch check deferred to the smoke test).
- [ ] **Step 5:** Commit `feat: provider-aware popover footer, local-estimate labels and Insights caveat`.

---

### Task 9: F8 + F10 deferred fixes

**Files:**
- Modify: `AIBattery/Views/AuthView.swift` — `@State private var cliLoginAvailable = false`; `.task { cliLoginAvailable = CodexAuthFileImporter.cliLoginAvailable }` on the Codex content; body no longer stats the file.
- Modify: `AIBattery/Services/CodexOAuth/CodexAuthSession.swift` — `private var pendingResult: Result<…>?`; `deliver` stores into `pendingResult` when no continuation is installed yet; `awaitCallback` resumes immediately from `pendingResult` if set. Document that `begin()` may receive the redirect before `awaitCallback()`.
- Test: `CodexAuthSessionTests.earlyDelivery_isBufferedUntilAwait` — construct via a new `static func makeForTesting(server:)`? `CodexCallbackServer` binds a port; instead expose the buffering as a pure nested type `CallbackMailbox` (`deliver`, `await`) and test that.

- [ ] Steps 1–5; Commit `fix: buffer an early Codex OAuth callback and move CLI-login detection off the render path`.

---

### Task 10: Spec + README + CLAUDE.md sync, cleanup

**Files:**
- Modify: `docs/superpowers/specs/2026-09-02-codex-support-design.md` §4 table (`inputTokens = input − cached − cache_write, clamped ≥ 0`, `messageId = <session_id>:<ordinal>`), §5 status feed resolved (R3 = yes, filtered components).
- Modify: `spec/ARCHITECTURE.md` (project tree: all Codex files from Plan 1 + 2; Data Flow provider branch; Network Calls: `chatgpt.com/backend-api/wham/usage`, `auth.openai.com` authorize/token, `status.openai.com/api/v2/summary.json`; Local File Access: `~/.codex/auth.json` read-only import, `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`; Keychain `refreshToken_codex_<id>`).
- Modify: `spec/DATA_LAYER.md` (AIProvider, AccountRecord.provider, RateLimitUsage provider/windowMinutes, CodexUsageParser, CodexRateLimitFetcher + backoff, CodexSessionRateLimitScanner, CodexSessionLogParser/Reader, UsageEntrySource, UsageAggregator provider param, OpenAIModelPricing, StatusFeedConfig, FileWatcher second root, UsageViewModel routing, CodexOAuth services, CodexPaths, JWTDecoder, OAuthPKCE).
- Modify: `spec/UI_SPEC.md` (provider glyphs in picker/menu bar, "Add Claude/Codex account", AuthView Codex branch + import link, footer provider links, Weekly label, All-Time caveat).
- Modify: `spec/CONSTANTS.md` (OpenAI URLs, port 1455, client-id, Codex component IDs, pricing table, 258 400 context window, backoff, `aibattery_codexRateLimits_` prefix, per-provider cap 3).
- Modify: `README.md` (feature blurb: two providers; Test Coverage table counts + Codex bullets), `CLAUDE.md` (tests/files count, "Claude API usage" → "Claude and Codex usage", key decisions: Codex JSONL mapping + no stats cache).
- Delete: `AGENTS.md`.
- [ ] Run `swift test` to get the exact test/file counts; `swiftformat`, `swiftlint`.
- [ ] Commit `docs: sync spec, README and agent guide for Codex account support`.

---

### Task 11: Whole-branch review + local smoke build

- [ ] Self-review diff `main...HEAD` for: provider leaks (any `RateLimitFetcher.shared` use under a Codex account), `response_item` decoding, writes under `~/.codex`, hardcoded "7-Day".
- [ ] `./scripts/build-app.sh` → hand the bundle to the user for the manual OAuth / import / bars / Insights smoke test (Plan 1's deferred human step + Plan 2 additions).
- [ ] Push branch; PR #193 stays draft until the smoke test passes.

---

## Self-review against the spec

- §4 reader discipline → Task 3; parsing model + mapping → Task 2 (spec amended Task 10); `AssistantUsageEntry` unchanged / aggregator unchanged structurally → Task 1; `CodexPaths` exists (Plan 1); FileWatcher second root → Task 7; no stats cache + honest UI caveat → Tasks 1, 8; pricing + `ModelNameMapper` → Task 4; Claude-only stats hide (Longest/Period from stats cache are nil for Codex; tool calls 0) → Task 1; popover reflects active provider end-to-end → Tasks 7, 8.
- §5 status feed (R3) → Task 5. §6 backoff → Task 6. Token values never logged — no new logging of tokens. §7 tests → every task. Sync obligations → Task 10.
- Plan 1 deferred: F7 → Task 6, F8 → Task 9, F9 → Task 6 + Task 10, F10 → Task 9, residual nit (compactMap vs `?? .claude`) → leave, cosmetic.
- Type consistency: `UsageEntrySource` name used in Tasks 1, 3, 7; `StatusFeedConfig` in Tasks 5, 7, 8; `UsageSnapshot.provider` in Tasks 1, 8; `aggregateOffMain(provider:)` Task 7 only.

# AIBattery full code review — 2026-10-16 (main @ 2719888, v3.1.0)

Scope: all 22,203 lines of Swift in `AIBattery/` + `AIBatteryApp/`, reviewed in four lanes (file I/O, network/auth, ViewModel/models, views/AppKit). Every `path:line` was verified against source. Lint/format baseline: `swiftformat --lint` clean, `swiftlint` 0 errors (warnings only: force-unwraps listed under Hygiene).

Items from the June perf backlog that are already done or measured-and-declined are NOT repeated here. One backlog item is closed by this review: the MenuBarIcon pulse/breath frame machinery is already deleted (UI_SPEC.md:563, v2.5.0).

Legend: effort S/M/L, confidence H/M/L.

---

## A. Correctness bugs (fix first)

### A1. Tool-call count under-counted ~25x — HIGH, S–M
`AIBattery/Services/SessionLogReader.swift:509` counts `tool_use` blocks from one JSONL line; `:206`/`:234` dedup first-wins per `message.id`. Claude Code writes one line per content block sharing the same id, and the first line is usually `thinking`. Verified on a real file: 187 tool_use blocks → 7 counted. `UsageAggregator.swift:325` takes `max(jsonl, statsCache)` and stats-cache.json hasn't been written since Feb, so the UI shows the undercount. Token totals unaffected (identical `usage` on every line).
Fix: coalesce within `readSessionFile` via `[messageId: index]`; on repeated id add the new line's tool_use count. Add test: text line + tool_use line sharing an id → `toolCallCount == 1`.

### A2. "Hidden project directory" filter is dead; 83% of files are observer sessions — HIGH, S (product decision)
`SessionLogReader.swift:328-331` decodes `-`→`/` and skips `.`-prefixed components, but Claude Code also encodes `.` as `-`, so the check never matches. `~/.claude/projects/-Users-kyle--claude-mem-observer-sessions` holds 1,571 of 1,888 JSONL files. They're stat'd every dirty cycle, parsed on cold start, trigger FSEvents → re-aggregate while idle, and land in 5h/7d estimates, Projects and Insights. Do NOT "fix" the decode: it would also exclude `.claude/worktrees/*` sessions. Either delete the filter (everything counts, honestly) or deny-list `--claude-mem-observer-sessions` explicitly and document in DATA_LAYER.md. Add a test either way.

### A3. Claude token endpoint signs out on unparseable 200 / unexpected 4xx — HIGH, S
`AIBattery/Services/OAuthManager.swift:653-659` (200 + bad JSON → `.unknownError`), `:626-650` (any non-200 non-5xx → `.unknownError`), `:601-609` (401/403 → `.invalidCode` without body check). `AuthError.isTransient` (`:215-220`) is false for all → `refreshAccessToken` (`:494-498`) calls `signOut`, deleting the Keychain item. `CodexTokenClient.swift:45-50,62-66` deliberately treats these as transient. A captive-portal HTML 200 or WAF 403 wipes a Claude login.
Fix: map unparseable 2xx and non-{400,401,403} to `.serverError`; 401/403 terminal only when the body is a JSON OAuth error. Update `OAuthPostTokenTests.swift:132`.

### A4. Refresh completing after `signOut` resurrects tokens + Keychain item — HIGH, S
`OAuthManager.swift:401-437` cancels the task, but success branches `:483-489` / `:517-522` write `tokens[accountId]` + `saveTokens` unconditionally. `postToken` swallows cancellation (`:594` `try? Task.sleep`; cancelled URLSession → `.networkError` → `continue`). Record gone → `provider(for:)` → `.claude` → writes `refreshToken_<id>` (wrong prefix for Codex).
Fix: `guard !Task.isCancelled, tokens[accountId] != nil` in both success branches; `guard !Task.isCancelled` per loop iteration in `postToken` and `CodexTokenClient.send` (`:142`).

### A5. `refreshLocalData()` leaks Codex token counts into Claude 429-calibration globals — HIGH, S
`UsageViewModel.swift:647-648` writes `LocalUsageEstimate.latestFiveHourTokens/SevenDayTokens` unconditionally; the network path `:558-560` guards with `if accountProvider == .claude` and explains why. FS path fires every ~2s during a Codex session, defeating the guard.
Fix: same `if accountProvider == .claude` wrapper.

### A6. Windowed Codex plan with purchased-credit balance renders as "Credits 0%" on card + menu bar — HIGH, S
`CodexUsageParser.swift:97-107` returns a balance-only `CodexCreditBudget(limit: 0, usedPercent: 0)` for subscription plans with `credits.balance`. `RateLimitUsage.isCreditBudget` (`:75-78`) exists to distinguish this, but `AccountReading.swift:38` (`worstPercent`), `AccountCard.swift:136` (`barRows`) and `:214` (`state`) nil-check `creditBudget` instead. Result: headline 0% on the card and multi-account menu bar, single Credits bar instead of 5h/Weekly, no time-to-limit.
Fix: use `windows.isCreditBudget` at all three sites; add test with `CodexCreditBudget(limit: 0, balance: 100)`.

### A7. Cancelled fan-out recorded as endpoint failure → 60s–5min backoff — HIGH, S
`UsageViewModel+FanOut.swift:16` cancels in-flight fan-out on toggle flip / account-count change; children get `URLError(.cancelled)`; `CodexRateLimitFetcher.swift:314-317`, `:254-257` call `recordEndpointFailure`, `StatusChecker.swift:133-137` bumps `failureCount`. Right after adding/removing an account, Codex drops to session-log fallback and the status dot freezes.
Fix: in those catches, `if Task.isCancelled || (error as? URLError)?.code == .cancelled` → return cached without recording.

### A8. Account-switch guard covers only the first await in `performRefresh` — M-H, S
`UsageViewModel.swift:437-440` guards; `:542` `await aggregateOffMain` can take seconds on a cold scan; `:542-593` then publishes old-account snapshot/errorMessage/resolvedMetricMode under the new identity, and `handlePostFetchAlerts` (`:769-772`) keys a notification to the NEW `activeAccountId` with the OLD limits. `refreshLocalData` and `repaintCachedNotFresh` re-check; `performRefresh` doesn't. Offline branch `:384-397` and unauthenticated `:367-371` have no guard.
Fix: a `displayGeneration` counter bumped by `switchAccount`/`clearAccountDisplayState`, captured at cycle start, compared after every await; pass fetched `accountId` into `handlePostFetchAlerts`.

### A9. Throttle-event counter is global across accounts — HIGH, S
`UsageViewModel.swift:859,868-888`, `ThrottleTracker.swift:13-24`: single `static var`; switching throttled A → healthy B → A logs a fresh "engaged" and appends a timestamp to `aibattery_throttleTimestamps`, inflating Insights trend rows (`ActivityChartTrend.swift:38/46/68`).
Fix: key by account id, or reset on switch and skip the first evaluation.

### A10. Aggregator short-circuit has no time component → idle polls return time-stale snapshots — M-H, S
`UsageAggregator.swift:139-152` fingerprint excludes `now`; `invalidate()` only fires on FS events. `aggregateOtherProviders` (`+FanOut.swift:75-82`) returns the same cached snapshot indefinitely while that CLI is idle (frozen 5h-window tokens on the non-active card); on the active provider, `todayMessages` can survive past midnight until a JSONL write.
Fix: include a 15-min bucket of `now` in the fingerprint, or treat `cachedSnapshot.lastUpdated` > 15 min as a miss.

### A11. `refresh()` coalescing loop can spin the main actor — M, S
`UsageViewModel.swift:323-331,337-343`: a waiter for a different account that resumes before the owner finds `inflightRefresh` still set to the finished task, re-awaits (returns synchronously), loops without a suspension point. Reachable on `switchAccount` mid-cycle.
Fix: after `await inflight.task.value`, `if inflightRefresh?.task == inflight.task { inflightRefresh = nil }`. Add a refresh-join test.

### A12. Auto mode never reorders metric sections — HIGH, S
`UsagePopoverView.swift:49-50,123-125,524-526`: `cachedOrderedModes` recomputed only on `metricModeRaw`/`autoMetricMode` change; in auto mode `metricMode` reads `viewModel.resolvedMetricMode` which has no `onChange`. Tabs highlight the new mode, sections stay in old order (contradicts UI_SPEC.md:78,203).
Fix: drop the cache and compute `MetricMode.orderedModes(current:)` in body (3-element array), or add `.onChange(of: viewModel.resolvedMetricMode)`.

### A13. Percent rounding differs across surfaces — HIGH, S
Truncating: `UsageBarsSection.swift:198,138,161`, `MenuBarMultiAccountText.swift:256`, `CreditBudgetSection.swift:79`, `LocalEstimateSection.swift:62`. Rounding: `AccountCardView.swift:127,167`, `MenuBarMultiAccountText.swift:45,236`, `StatusBarManager+ButtonUpdate.swift:24`. 99.6% reads "100%" on the card/menu bar and "99%" in the detail bar, with no "Limit reached".
Fix: one `PercentFormat.display(_:)` helper (truncate), used everywhere; test 99.6 → "99%".

### A14. `@State` mutated during body evaluation — HIGH, S
`MarqueeText.swift:48` `let _ = updateContainerWidth(geo.size.width)` inside GeometryReader builder. Move to `.onAppear` + `.onChange(of: geo.size.width)`.

### A15. Oversized-line discard counts the same line as corrupt once per MB, then parses its tail — HIGH, S
`SessionLogReader.swift:430-435`, `CodexSessionLogReader.swift:246-251`. 10 Codex rollouts and 3 Claude files have >1MB lines (max seen 1.4MB). Inflates `lastCorruptLineCount` + `.warning` logs. Fix: `skippingOversizedLine` flag; drop bytes to next newline via memchr; count once; log at `.debug`.

### A16. Smaller correctness items — S each
- `SessionLogReader.swift:503-507`: missing/unparseable timestamp falls back to `Date()` (Codex parser treats as corrupt). Use `DateFormatters.parseISO8601`, skip on nil. (M, latent)
- `FileWatcher.swift:112-131`: stats-cache vnode source never re-armed after `.rename`/`.delete`. (M)
- `UsagePopoverView.swift:154-158`: overview → detail via account removal never arms `deferredRender`; Projects/Insights stay collapsed until reopen. (M)
- `StatusBarManager.swift:313-324`: text colour baked from `button.effectiveAppearance` but invalidated on `NSApp.effectiveAppearance`; observe the button's KVO. (M)
- `StatusBarManager.swift:245-268`: `$isAuthenticated` sink fires `refresh()` at t≈0 and the VM fires another at 2s; add `.dropFirst()`. (M)
- `StatusBarManager.swift:232-242`: colorblind toggle doesn't call `updateButton`; star stays old palette up to 5 min. (H)
- `MetricToggleView.swift:70,75` vs UI_SPEC.md:200,202: auto-mode tab highlight/disable drift; spec-first rule says decide and fix. (H)
- `MetricToggleView.swift:59-83`: no `.isSelected` trait for VoiceOver. (M)
- `UsageViewModel.swift:409-425` (wasEmpty paint) lacks the post-await guard. Same class as A8.

---

## B. Efficiency wins (ranked by cost saved)

### B1. Fan-out is N+1 (and double-billed) for API-key active accounts, and whenever the active fetch was cached — HIGH, S
`UsageViewModel.swift:588-592` seeds only if `api.rateLimits != nil && !api.isCached`; `interpretAPIKeyProbe` (`CodexRateLimitFetcher.swift:208-214`) always returns `rateLimits: nil`, so an active API-key account never seeds; `MultiAccountFanOut.swift:116` keeps it in `idsToFetch` → a second paid `/v1/responses` probe every cycle. Same re-fetch for OAuth accounts exactly when the endpoint is struggling.
Fix: seed from `AccountReading(api:)` (windows or apiLimits); always exclude the active id and carry its previous reading forward.

### B2. Claude fetcher has no endpoint backoff: 3 requests per poll (5 on 429) while `/api/oauth/usage` is down — HIGH, M
`RateLimitFetcher.swift:168-225,194,529,390,418,433`. Codex has `EndpointBackoff` (`CodexRateLimitFetcher.swift:40-64`). Apply the same to the usage endpoint's `.unavailable`; delete the second client_data call in the retry branch.

### B3. Codex reader copies every line (incl. multi-MB response_items) before the relevance pre-filter — HIGH, S
`CodexSessionLogReader.swift:255,270`: `Data(leftover[...])` vs Claude reader's slice-pass. ~80–160ms on cold scan, 2–10ms per 2s invalidation during a Codex session. Pass the slice.

### B4. Codex discovery re-walks the tree + `realpath`s every file on every invalidation — HIGH, M
`CodexSessionLogReader.swift:54-63,181-215`. No per-directory mtime skip (Claude reader has it: 19.4ms → 1.0ms). ~15–40ms per 2s during active use. Cache per-leaf-dir mtime + file list; resolve symlinks per parent dir.

### B5. `seenIds` Set rebuilt from full merged array every dirty cycle — HIGH, S–M
`SessionLogReader.swift:179`, `CodexSessionLogReader.swift:110`; plus `removeAll` per changed file (`:219`/`:139`). Keep `cachedSeenIds` alongside `cachedAllEntries`; batch stale removal. Cheap half of backlog #2, shippable independently.

### B6. Session-log fallback does file I/O synchronously on MainActor — HIGH, S
`CodexRateLimitFetcher.swift:355-380` → `CodexSessionRateLimitScanner.latestRateLimits()` (seek + 256KB read + JSON, or full tree walk after invalidate) every poll per account during backoff. Wrap in `Task.detached(priority: .utility)`. Violates the project's own "never @MainActor for file I/O" rule.

### B7. `lastPathComponent` computed twice per entry per aggregate pass — HIGH, S
`UsageAggregator.swift:286-288`. ~15–20ms per pass over 9k entries, risk-free (unlike the declined CoW item). Look up `projectMap[cwd]` first; compute only on new `ProjectAccum`.

### B8. `attributesOfItem` still used for directory mtimes — HIGH, S
`SessionLogReader.swift:306,338,397`, `CodexSessionLogReader.swift:185`. Own comment at `:185-188` measured 9x cost vs `resourceValues`. Also `discoveryDirModDatesChanged()` double-stats every dir. ~12ms → ~1.5ms per discovery.

### B9. Redundant @Published writes → 4–5 popover re-renders per poll — HIGH, S
`ClaudeSystemStatus` not `Equatable` (`ClaudeSystemStatus.swift:10-17`, trivially so); `UsageViewModel.swift:443-453,705,732` and `+FanOut.swift:82,95` write value-equal `systemStatus`/`providerStatuses`/`isShowingCachedData`/`rateLimitsFresh`/`errorMessage`/`isLoading`/`providerSnapshots` across separate run-loop ticks. Add `Equatable` + `setIfChanged`.

### B10. Each overview card runs its own 10s `TimelineView` around its whole body — HIGH, S
`AccountCardView.swift:16-49`; only `stateLine` (`:23`) and `isLive` (`:97`) use `now`. Hoist one TimelineView in `OverviewContentView` or wrap just the state line.

### B11. Transient refresh failures retry 3x with sleeps on every poll, no memory — M, S–M
`OAuthManager.swift:590-595`, `CodexTokenClient.swift:142-147`. Add per-account `lastRefreshFailedAt` + short backoff in `getAccessToken(for:)`.

### B12. Root popover body repeats derived work per publish — M, M
`UsagePopoverView.swift`: `displayKind(snapshot)` 4x (320,370,380,454), `eligibleAccountCount` 3x (205,301,499), `overviewCards` rebuilt in detail mode (208-218). Compute once at top of `mainContent`; build cards only in overview.

### B13. Smaller wins — S each
- `UsageViewModel.swift:686-702` `scheduleRolloverClear` recreates a Timer on every FS burst; early-return if fire date within 1s.
- `UsageViewModel.swift:255-257,285` `aggregateOffMain` lets 2+ parked callers run concurrently and nils a newer caller's task; chain instead.
- `StatusBarManager.swift:374,389`, `+Panel.swift:31-32`: `hosting.fittingSize` read twice per refit (each is a layout pass).
- `MenuBarIcon.swift:78-79`: provider marks re-tinted per image rebuild (1/s during countdown); cache next to `iconCache`.
- `MenuBarIcon.swift:41,150,186`: `NSLock` on a `@MainActor` cache; remove.
- `UsageAggregator.swift:429-442`: `calendar.component(.hour)` + `String(hour)` extra passes; fold into main loop with Int keys.
- `SessionLogReader.swift:252-259`, `CodexSessionLogReader.swift:167-169`: mutating `cache` while iterating forces a CoW copy each cycle.
- `SettingsRow.swift:121-133`: alias persisted + `$accounts` published per keystroke; draft + commit on submit.
- `AboutSection.swift:7` observes whole VM for one optional; `RefreshSettingsSection.swift:5,33` holds an unobserved `let viewModel` (hint doesn't update).
- Three `UserDefaults.didChangeNotification` subscribers with own debounce (`StatusBarManager:232`, `UsageViewModel:216`, `ThemeColors:21`); one KVO on specific keys replaces all and fixes the colorblind/showAll invalidation gaps.
- `OAuthManager.swift:771-788` `migrateStaleKeychainItems` runs 3 Keychain ops per account every launch; gate with a done-flag like `:796-821`.
- `UserDefaults.dictionaryRepresentation()` 6x at launch (`RateLimitFetcher.swift:96,112`, `+Persistence.swift:73,156`, `CodexRateLimitFetcher.swift:431,510`).
- `OAuthManager.swift:519` rewrites an unchanged Codex refresh token to Keychain hourly.
- `VersionChecker` + Sparkle both check for updates (`UsageViewModel.swift:777`); one GitHub call/24h, redundant.

---

## C. Security / robustness (networking)

- **No redirect policy on `SecureNetworking`** (`Utilities/SecureNetworking.swift:12-18`): URLSession follows 3xx and replays `Authorization` to the new host. No endpoint legitimately redirects. Add a `URLSessionTaskDelegate` returning nil from `willPerformHTTPRedirection`. (S, M impact)
- **2MB cap checked after full buffering** (`SecureNetworking.swift:22-26`): doesn't protect memory as the comment claims. Use `bytes(for:)` with an accumulator, or reject on `expectedContentLength`. (S–M)
- `RateLimitFetcher.swift:498` `lower.contains("access")` also matches billing errors → cycles every probe model per poll.
- `CodexRateLimitFetcher.swift:119` any 429 → throttled, unlike Claude's `quotaThrottleLikely` gate.
- `CodexCallbackServer.swift:96-101` parses a single `receive` chunk; split request line → 404 until timeout (theoretical on loopback).
- `OAuthManager.swift:809` accessibility migration `continue`s on failed read but still sets done flag.

---

## D. Structure / dead code

**Files over the 800 max / 400 typical:**
- `UsageViewModel.swift` (909): split into `+Refresh` (`:346-780`), `+Accounts` (`:782-848`), `+Throttle` (`:850-896`), `+LocalRefresh` (`:605-702`), and extract a pure `RateLimitDisplayPipeline` struct from `:457-531` (rollover clear → spike confirm → write-back; the most-patched region, currently untestable as a unit). Main file lands ≈300 lines.
- `RateLimitUsage.swift` (641): move `:424-640` client-data parser to `+ClientDataParsing.swift`.
- `UsagePopoverView.swift` (550): extract `MetricSectionsView` (`:348-420`) and `+Overview.swift` (`:202-289`).
- `AuthView.swift` (504): `+Claude.swift` (`:170-273`), `+Codex.swift` (`:275-392`).

**Duplication:**
- `UsageViewModel.swift:809-822` `clearAccountDisplayState` vs `:825-845` `switchAccount` — comment says shared, code re-lists the same assignments inline and has already diverged (`isLoading = true`).
- Three identical "paint from provider cache" blocks: `UsageViewModel.swift:174-198`, `:409-425`, `+Lifecycle.swift:107-134` → one `paintFromCache(accountId:provider:)`.
- Hysteresis block `UsageViewModel.swift:666-677` == `:720-730`.
- Claude/Codex readers: `invalidate`, purge, `rebuild`, `evictOldFileEntries`, chunk loop, oversize handling are near-verbatim copies (bugs A15, B5, B8 exist twice). Extract `JSONLLineStreamer` + `FingerprintedFileCache` when fixing A15.
- `StatusBarManager+Panel.swift:29-30` hard-codes 900/40 where `Layout.fallbackScreenHeight`/`menuBarInset` exist; 11pt mono font built in `StatusBarManager.swift:142` and `MenuBarIcon.swift:104`; amber literal at `ThemeColors.swift:40,342,360`.

**Dead code (0 production call sites, grep-verified):**
- `MetricToggleView.swift:16-18,41,132-135` `cachedOrderedModes`/`recomputeOrderedModes`
- `PopoverFooterView.swift:243-259` `RelativeTimeText.alternateText/alternateTooltip`
- `MenuBarMultiAccountText.swift:303-314` `percent(for:mode:)`, ignored `metricMode` param at `:41`, `isExhausted` alias
- `StatusBarManager.swift:104-105` `currentPercent`/`currentColor` (written `+ButtonUpdate.swift:180-181`, never read)
- `CopyableText.swift:80-111` `LightCopyableModifier`
- `InsightsRowsAndHover.swift:199,207` `formatHourLabelFull`, `quarterlyLabelDates` (tests only)
- Tokens: `Layout.cardResetWidth`, `ThemeColors.disabledOpacity`, `.surfaceLevel1`, `.hoverStroke` (UI_SPEC.md:504 still describes it), `Typography.heroValue`, `.base`

**Other:**
- `UsageViewModel.swift:134-141` contradictory doc comment on `rateLimitStaleTTL` (5 min vs 24h; value is 86_400).
- `TokenHealthStatus.swift:13` `HealthWarning.id = UUID()` regenerates per aggregation; derive from severity+message.
- `TokenHealthMonitor.swift:18` hard-codes `now`; `AccountCard.swift:218` reads wall clock via `estimatedTimeToLimit` despite "pure" doc. Thread `now:` through.
- `lastCorruptLineCount` (`SessionLogReader.swift:98/129`, `CodexSessionLogReader.swift:47/68`) is a lock-free cross-thread read and is reset on the cached fast path, so the logged sum is usually 0.
- `UsageAggregator.swift:376` `firstSessionDate` uses the fractional-only formatter.
- Dedup across files is dictionary-order dependent (`SessionLogReader.swift:383`); sort `jsonlFiles` by path.

**UI_SPEC.md drift (spec-first rule):** :439 loading state copy/size, :609 panel background, :613 gold in light mode, :617 tertiary opacity, :522 `build(order:limits:metricMode:)` signature, :200/:202 auto-mode tabs.

**SwiftLint warnings in production code:** force-unwraps at `CodexSessionRateLimitScanner.swift:76`, `CodexCallbackServer.swift:62`, `CodexOAuthConstants.swift:12,15,28`; orphaned doc comments `DateFormatters.swift:6,19`.

---

## Status (updated 2026-10-16, end of the fix pass)

**Fixed on this branch:** A1–A15 (all correctness bugs except the smaller A16 items listed below), B1, B2, B3, B5, B7, B8, B9, B10, B13 (reader + eviction parts), the C networking items, the Keychain-migration and dead-code hygiene items, and the `UsageViewModel` split (968 → 457 lines, back under the 800 ceiling).

**Second pass (same day) closed the rest:** B4, B11, B12, the B13 remainder, the A16 remainder, the UI_SPEC drift, and the file splits that mattered. Details:
- **B4** — Codex discovery now caches a per-directory listing. Measured on the real 939-file tree: 0 directories re-read across 20 consecutive invalidations, and `resolvingSymlinksInPath()` runs only on entries that are actually symlinks.
- **B11** — transient refresh failures arm a per-account window on the shared backoff curve.
- **B12** — `displayKind` resolved once per body evaluation. Two of the three claims here did not survive checking: `overviewCards` is already branch-scoped (it is only reachable from `overviewContent`), and `eligibleAccountCount` is a filter-and-count over at most six records, so it was left alone.
- **B13** — `fittingSize` read once per refit, tinted provider marks cached, MenuBarIcon's obsolete `NSLock` removed, and the account alias field switched to a focused draft.
- **A16** — the auth-sink `.dropFirst()`, the overview→detail `deferredRender` arming and the VoiceOver `.isSelected` trait were all already in place from the first pass.
- **File splits** — `OAuthManager` was over the hard maximum at 927 lines and is now 647, with the launch migrations and the token endpoint in their own files. `RateLimitUsage` split its wire-format parsing out (367 + 289).

**Still deliberately not done, with reasons:**
- **`AuthView` (504 lines)** — under the 800 maximum. Splitting it by provider was attempted and reverted: it forced about ten pieces of private view state to become internal, which costs more than the file length.
- **`AboutSection` observing the whole ViewModel** — the proposed Binding would silently break it. Its parent (`SettingsRow`) does not observe the ViewModel either, so nothing would re-render when an update is found and the "Install" button would never appear. With a macOS 13 minimum there is no per-property observation; `@ObservedObject` is correct here, and the cost is bounded to while the Settings pane is open.
- **`RefreshSettingsSection`'s unobserved ViewModel** — its "×N accounts" hint does update, because the fan-out count only changes when accounts change and `accountStore` is observed. Passing values in would make the dependency explicit without changing behaviour.
- **Unused design tokens** — they belong to coherent scales (`cardResetWidth` sits beside `cardPercentWidth`/`cardTokensWidth`). `hoverStroke` turned out to be a genuine spec/code gap: UI_SPEC claimed the gear draws it and the code does not. The spec now says so; whether to restore the edge is a design decision.
- **Keychain accessibility read failure** — distinguishing "item absent" from "read failed" needs a `KeychainHelper` API change, which is disproportionate for a pre-2.x-install edge case.

## Suggested PR grouping (one integration branch per group, tested locally)

1. **Data correctness** — A1, A2 (decide filter policy first), A15, A16-timestamp, B3, B5, B7, B8, reader-scaffolding extraction. Measure with `AIBATTERY_REAL_CLAUDE_LOGS=1` / `AIBATTERY_REAL_CODEX_LOGS=1`.
2. **Auth hardening** — A3, A4, A7, B11, C-redirect, C-size-cap, Keychain migration flag.
3. **Account identity seams** — A5, A6, A8, A9, A10, A11, B1, B9, `switchAccount` dedupe, `paintFromCache` extraction, `RateLimitDisplayPipeline` extraction + VM split.
4. **Views** — A12, A13, A14, remaining A16 view items, B10, B12, B13 view items, dead-code sweep, UI_SPEC sync.
5. **Claude endpoint backoff** — B2 on its own (behavioural, needs soak).

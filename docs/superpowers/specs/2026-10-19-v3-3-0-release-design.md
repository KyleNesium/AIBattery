# v3.3.0 Release — Design Spec

**Date:** 2026-10-19 (revision 3: brainstorm → `/plan-eng-review` + outside voice → second
outside voice, all the same day)
**Status:** Reviewed; awaiting Kyle's read before `writing-plans`
**Base:** `main` @ `e768fa6` (v3.2.0). Branch `worktree-v3-3-0`, worktree `.claude/worktrees/v3-3-0`.
**Ships as:** one integration branch, one draft PR, tested locally per task, CI once when ready
(project rule: no CI fan-out). Tag `v3.3.0` after Kyle's manual check of the Phase 2 + arrow
behaviour; attribution ships fixture-verified (see §3 "Verification").

## Goal

Three pieces of work, in this order. The sure things go first; the likeliest cut goes last so a
cut never reorders commits:

1. **Header update arrow.** Replace the update banner + gear badge with one arrow button that
   appears only when a release is available.
2. **Phase 2 — provider-relevant display.** The already-approved spec
   `2026-10-12-provider-relevance-design.md` and its plan, re-based onto v3.2.0.
3. **Codex per-account attribution.** With two or more ChatGPT-backed Codex accounts, the active
   account's Insights / Projects / Context show only its own turns.

Preceded by **housekeeping on `main`** (no app code): verify and remove the stale worktrees, sync
`aibattery-web` to 3.2.0.

## Decisions

| Question | Decision | When |
|---|---|---|
| Release structure | One branch, one PR; arrow → Phase 2 → attribution. | brainstorm; order revised in review 1 |
| Turns without `creator_account_id` when ≥ 2 ChatGPT Codex accounts exist | **Hidden** from every account, never over-counted. With ≤ 1 ChatGPT Codex account nothing changes. | brainstorm |
| Where the hidden count is shown | A caption under the Insights chart, **visible in every chart mode** when N > 0, plus the All-Time tooltip. (There is no existing caveat line; the only Codex caveat today is the tooltip at `InsightsRowsAndHover.swift:49`.) | review 1 D6, visibility fixed in review 2 |
| How the attributed and provider-wide figures are produced | **One pass, two snapshots.** The aggregator loop body becomes an accumulator struct; under attribution two instances run per entry. No second pass, no attribution-keyed cache. Replaces review 1's D2 (keyed cache) and the "extra `.all` pass" — on the FS path (every ~2 s during a Codex session) that would have been two cold passes. | review 2 D7 |
| Ledger with ≥ 2 ChatGPT Codex accounts | **Namespaced keys.** Attributed series `"<accountId>#attributed"`; the provider-wide series under attribution `"codex#all"` (today's `.all` pass keys by the *active* account, which would split one dataset into two series). No reset, no migration flag. With ≤ 1 ChatGPT account the plain account-id key and its history are untouched. | review 1 D4, provider-wide key added in review 2 |
| Overview cards with two ChatGPT Codex accounts | **Provider-wide**, as labelled. They read the provider-wide snapshot, which every pass now produces. | review 1 D1 |
| Session-log fallback maximum age | **Built in this PR** (TODOS.md third-review item): new readings *and* the in-memory cached fallback are refused past `codexFallbackMaxAge`. | review 1 D3, cache half added in review 2 |
| Attribution verification | **Fixture-verified**; this machine has one Codex account. CHANGELOG says so and asks two-account users to report. No debug override. | review 1 D5 |
| Update arrow visibility | Only when `availableUpdate != nil`. Banner and gear badge removed. Settings → About unchanged. | brainstorm |
| Phase 2 contents | Unchanged: 2026-10-12 spec §1–§5, §7, §8. §6 shipped in v3.1.0, §9 superseded. §5 conditional on Task 0. | brainstorm |
| Billing heuristic (`billsLocalCodexCosts`) | Kept. R4 decides whether attribution can replace it. | brainstorm |

## 0. Housekeeping (before the feature branch starts; no app code)

- **Pull first.** The main checkout at `~/workspace/Github/KyleNesium/AIBattery` is at `2719888`
  (v3.1.0), two commits behind `origin/main`.
- Worktrees to retire (from `git worktree list`): six `agent-*` entries (subagent scratch from the
  v3.2.0 review-fixes session, branches `worktree-agent-*`), `sparkle-2-10` (branch
  `worktree-sparkle-2-10`, PR #199 absorbed into #201), `review-fixes-2026-10` (branch
  `fix/dmg-detach-already-unmounted`, PR #203 merged; the orphaned branch
  `worktree-review-fixes-2026-10` goes too) and the mis-named entry at path
  `.claude/worktrees/Users/kyle/workspace/Github/KyleNesium` (merged).
  For each: (a) `git diff --stat origin/main <branch>` over the **whole tree** (not just
  `AIBattery Tests` — `sparkle-2-10` changed `Package.swift`, `Package.resolved`, `.github/`)
  must be empty or contain only changes already on `main` in another form; anything else is
  reported to Kyle before removal. (b) **No Claude session may be open on the path** — the
  session that ran this review had its scratchpad keyed to `review-fixes-2026-10`, so that one
  waits until that session has ended; ask Kyle, do not guess. Then `git worktree remove <path>`
  + `git branch -D <branch>`. Remove by **path**.
- `aibattery-web`: `npm run sync:app` for 3.2.0, copy update for the 1%-as-100% fix if the
  changelog warrants it, PR with a merge commit (recipe in the website memory).

## 1. Header update arrow

- New standalone view `UpdateArrowButton(update: VersionChecker.UpdateInfo)` in
  `AIBattery/Views/UpdateArrowButton.swift`:
  - `Image(systemName: "arrow.up.circle")`, `Typography.headerGear`, square frame of
    `Layout.accountChipHeight`, `ThemeColors.updateAvailable`, glow
    `.shadow(color: ThemeColors.updateAvailable.opacity(ThemeColors.chevronGlowOpacity), radius: Layout.glowRadius)`.
  - Opacity breathes between 1 and `ThemeColors.liveDotDimOpacity` with
    **`MotionConstants.breathe`** (1.6 s ease-in-out, repeat forever — the `LiveDot` pattern),
    disabled under `accessibilityReduceMotion`. Not `MotionConstants.standard` (0.15 s).
  - Primary click: `AboutSection.installUpdate(update)` (Sparkle check when available, release
    page otherwise). The arrow's *visibility* comes from GitHub Releases
    (`UsageViewModel+Refresh.swift:469`) while the click runs a Sparkle check against the appcast,
    so the two can disagree when the appcast lags. The button therefore carries a SwiftUI
    `.contextMenu` (precedent in this panel: `TokenHealthSection.swift:131`; the chip's
    `NSMenu.popUp` is for sizing, not necessity) with **"Release notes"** (opens `update.url`) and
    **"Check for Updates"** (`installUpdate` again). Help text
    `"v\(version) available — click to update"`.
  - Accessibility label "Update available, version \(version)", hint "Downloads and installs the
    update; right-click for release notes".
  - The two places that set `availableUpdate` (`UsageViewModel+Refresh.swift:470`,
    `AboutSection.swift` after a manual check) wrap the assignment in
    `withAnimation(MotionConstants.standard)` so `MotionConstants.expandTransition` on the arrow
    actually animates (today the banner appears without animation for the same reason).
- Placement: immediately left of the gear in **both** `PopoverHeaderView` (detail header) and
  `OverviewFooterView` (`OverviewContentView.swift:47`, a separate struct whose gear carries
  `label: "Settings"`; `OverviewContentView` itself has no gear). Both insert the same
  `UpdateArrowButton`. `OverviewFooterView.showsUpdateBadge: Bool` becomes
  `availableUpdate: VersionChecker.UpdateInfo?`, passed from `UsagePopoverView.swift:257`.
- Removed: `PopoverHeaderView.updateBanner`, `updateBannerDismissed`,
  `PopoverHeaderView.gearShowsUpdateBadge` (dismissal-gated, `:86-93`) and
  `UsagePopoverView.gearShowsUpdateBadge` (not dismissal-gated, `:227-233` — they were never
  twins), `SettingsGearButton.showsUpdateBadge` and its overlay / help / accessibility variants.
  `ThemeColors.updateAvailable` stays (Settings → About uses it).
- **Compile flag note.** `VersionChecker.swift` is inside `#if ENABLE_VERSION_CHECKER`, but
  `PopoverHeaderView.swift:12` and `UsagePopoverView.swift:305` already reference
  `VersionChecker.UpdateInfo` unguarded, and all three SPM targets define the flag
  (`Package.swift:24,35,46`). The flag is effectively always on; this PR adds the new sites
  unguarded too and **corrects `spec/ARCHITECTURE.md` and `spec/CONSTANTS.md`**, which still claim
  the define can be removed for an App Store build. (Wrapping every view-side reference is a
  separate cleanup, not this release.)
- Tests: no existing test references the banner or badge (`UpdateInfo` is only constructed in
  `VersionCheckerTests`). SwiftUI bodies are not testable here, so coverage is the pure helpers:
  `UpdateArrowButtonTests` for the help string, accessibility label, menu item titles and the
  reduce-motion → no-animation rule (a static that maps `(reduceMotion) -> Animation?`).

## 2. Phase 2 — provider-relevant display (re-base notes)

The 2026-10-12 spec is authoritative for behaviour. The plan is re-based, not rewritten; the
re-base touches these spots:

- Branch / changelog: `worktree-v3-3-0`, `## [3.3.0] — Unreleased`. The "Phase 2 of the v3.1.0
  release plan" framing is replaced by this spec.
- **Task 0 was never run, and its method does not work on this machine.** Re-based Task 0:
  (1) the log line is `AppLogger.network.error("usage endpoint keys: …", privacy: .public)` —
  `.notice`/`.info` are not retrievable with `log show` here (project memory; confirmed today:
  `log show --last 24h` for the subsystem returns nothing at any level); (2) start
  `log stream --predicate 'subsystem == "com.KyleNesium.AIBattery" AND eventMessage CONTAINS "usage endpoint keys"'`
  **before** launching; (3) `./scripts/build-app.sh && open .build/AIBattery.app` blocks on a
  Keychain prompt for an ad-hoc rebuild — the operator clicks "Always Allow"; (4) revert the line,
  record the key set, relaunch `/Applications/AIBattery.app`.
- `RateLimitUsage.swift` was split in v3.2.0: parsing now lives in
  `AIBattery/Models/RateLimitUsage+Parsing.swift`. Conditional Task 6's `modelWindows` parsing
  goes there.
- Line anchors moved (`makeUsageEntry` 557, `TokenHealthMonitor.assess` 119, `LedgerData` 215,
  `ModelTokenRecord` 219). Every task re-locates by symbol, not line.
- `TokenHealthSection`, `SessionLogReader`, `UsageAggregator`, `MultiAccountFanOut`,
  `CodexRateLimitFetcher` all changed in v3.2.0; the implementer re-reads each before editing.
- **New fields are `var … = default`**, trailing the existing ones, so the six
  `AssistantUsageEntry(` and six `UsageSnapshot(` memberwise call sites keep compiling (Phase 2
  plan Task 1 already says so; §3 below follows it).
- Task 1 (new entry fields) also adds `creatorAccountId` from §3 — one touch of
  `AssistantUsageEntry` and both parsers. The field is inert until §3's aggregation task lands.
- **Ledger key.** Task 2's `ModelTokenRecord.reasoning` and Task 9's `firstScan` both key by
  the ledger key (§3 "Ledger"), not the raw account id; Task 9's `firstScanDate(ledgerKey:)`.
- **One tooltip signature.** Task 9 names `InsightsView.allTimeTooltip(for:since:)`; the real
  function is `InsightsView.allTimeTooltip(for:)`, defined in `InsightsRowsAndHover.swift` (`:46`)
  as an `extension InsightsView`. The re-based plan uses
  `InsightsView.allTimeTooltip(for:since:unattributed:)`; Task 9 adds `since:`, §3 adds
  `unattributed:` (default 0). Task 9's test file becomes `Views/InsightsTooltipTests.swift`
  (the plan's `InsightsAllTimeTooltipTests` does not exist yet).
- **One caption line, always visible.** Task 9's "since <date>" caption (plan `:1264`, monthly
  mode only) and §3's hidden-turn caption share one `Typography.monoTiny` tertiary line under
  the chart, rendered in **every** chart mode when either half applies:
  `"since 12 Oct 2026 · N turns from older Codex CLI versions not shown"`. Pure formatter
  `InsightsView.sinceCaption(provider:since:unattributed:now:)`, defined in `InsightsCharts.swift`
  as an `extension InsightsView` — the chart body lives in
  `InsightsCharts.swift:185-204`, the mode enum in `ActivityChartView.swift:9`; Task 9's code
  block, its test and the plan's "Names used across tasks" line (`:1299`) are updated to the new
  home. The "since" half is shown in all modes too (one rule, not two).
- README "Test Coverage" is updated **in the same commit as any test change** (Phase 2 global
  constraint); `CLAUDE.md`'s count line at wrap-up.

## 3. Codex per-account attribution

### Ground truth (this machine, 2026-10-19, count-only greps)

- `~/.codex/sessions`: ~990 rollouts at the second count (942 in the morning). 47 files mention
  `creator_account_id`; in 42 it is on line 1; 43 `session_meta` lines carry it (one file has it
  on a *later* `session_meta` line); **38 non-`session_meta` lines** (`response_item` content)
  also contain the string — so any head check must still gate on `isResponseItem` and on
  `type == "session_meta"` before trusting a match. All March 2026 rollouts have `session_meta`
  without the key. One distinct id locally — equal to the app's Codex account id
  (`JWTDecoder.chatGPTAccountId(idToken:)`, `OAuthManager+Codex.swift:107`).
- `session_meta` is line 1 in every file, but that line carries `base_instructions`: max first
  line 23 254 B; none over 1 MiB (consistent with the reader's 1 MB oversized-line cap,
  `CodexSessionLogReader.swift:338`).
- Nothing on this machine shows what **API-key** mode writes (R4).
- "Rollouts" ≠ "turns": one rollout holds many `token_count` entries. Counts shown to the user
  are entries (turns), never files.

### Data model

- `AssistantUsageEntry` gains `var creatorAccountId: String? = nil` (trailing) — nil for Claude
  and for rollouts without the key.
- `CodexSessionLogParser.applySessionMeta` reads `payload["creator_account_id"] as? String`
  (non-empty) into `creatorAccountId`, carried onto every entry of the file like `cwd`. The parser
  applies **every** `session_meta` line (`:123-125`), so a later one wins for later entries;
  pinned by a test (see §5).
- `SessionLogReader.makeUsageEntry` leaves it nil.

### Aggregation: one pass, two snapshots

- `enum Attribution: Hashable, Sendable { case all; case account(String) }` in its own file
  `AIBattery/Services/Attribution.swift`, plus the pure
  `Attribution.partition(_ entries: [AssistantUsageEntry]) -> (kept: [AssistantUsageEntry], unattributed: Int)`
  (under `.all`: the input and 0, no copy; under `.account(id)`: keeps `creatorAccountId == id`,
  counts nil ids, drops foreign ids uncounted).
- **Refactor first, then the easy change** (Beck). The body of the entry loop in
  `UsageAggregator.aggregate` (`UsageAggregator.swift:224-334`) and the post-loop assembly become
  `struct AggregationPass` with `mutating func add(_ entry:)` and
  `func finish(…) -> UsageSnapshot`; `aggregate` keeps its signature and behaviour. This lands
  as its **own commit with zero behaviour change**, verified by the existing 43
  `UsageAggregatorTests` + integration + opt-in real-data tests, and timed before/after with
  `AIBATTERY_REAL_CODEX_LOGS=1` / `AIBATTERY_REAL_CLAUDE_LOGS=1` (`UsageAggregatorRealDataTests`).
- Then `aggregate(…, attribution: Attribution = .all)` returns
  `AggregateResult { detail: UsageSnapshot; providerWide: UsageSnapshot; effects: SideEffects }`.
  Under `.all`, `detail` and `providerWide` are the same value (one pass instance). Under
  `.account(id)`: two `AggregationPass` instances; every entry goes to `all.add`, kept entries
  also to `mine.add`; `mine.finish` uses the kept array for `todayEntries`, `firstSessionDate`,
  `TokenHealthMonitor.assessSessions` and `SideEffects.activeUserModel` (the review found a draft
  that filtered inside the loop and left those four on the unfiltered array). The health
  assessment runs once per instance — the only genuinely duplicated work.
- `UsageSnapshot` gains `var unattributedTurnCount: Int = 0` (trailing, in the hand-written `==`
  which spans `UsageSnapshot.swift:6-47`). Only `detail` carries a non-zero value.
- The redundant-aggregation cache (`UsageAggregator.swift:104-160`) stores the `AggregateResult`
  and adds `attribution` to its fingerprint. One slot is enough because every caller for a
  provider now runs with the same attribution (below). `invalidate()` unchanged.
- **Where attribution is decided: inside `UsageViewModel.aggregateOffMain`** (it already
  consults the store for `costIsBilled`, `UsageViewModel.swift:283`), so all seven call sites
  (`+Refresh.swift:37,56,85,220,315`, `UsageViewModel.swift:198`, `+Lifecycle.swift:133`) and
  the fan-out (`+FanOut.swift:79`) get it for free. Rule, as a pure tested helper
  `AccountStore.attribution(for accountId: String?, provider: AIProvider, accounts: [AccountRecord]) -> Attribution`:
  `.account(id)` when `provider == .codex`, the account is ChatGPT-backed (`!isAPIKeyAccount`)
  and the store holds ≥ 2 ChatGPT-backed Codex accounts; else `.all`. The fan-out's
  `aggregateOtherProviders` passes `providerWide: true` to force `.all` (its `eligible.first`
  id is only for cost framing).
- **Publishing.** `aggregateOffMain` publishes `providerSnapshots[provider] = result.providerWide`
  itself and returns `result.detail`; the `snapshot.didSet` mirror at `UsageViewModel.swift:13-15`
  is removed. Cards (`AccountCard.swift:94-100`: window tokens, today's model tokens, last
  activity) therefore stay provider-wide and live on every path, including the FS path.

### Ledger (namespaced keys, no migration)

- `TokenLedger.key(accountId:provider:attribution:) -> String`:
  - attribution inactive (`.all` because ≤ 1 ChatGPT account, or Claude, or API-key active):
    the plain `accountId` — **unchanged for every existing user**;
  - `.account(id)`: `"\(id)#attributed"` for the `mine` pass, `"codex#all"` for the `all` pass.
  `merge(_:accountId:)` becomes `merge(_:ledgerKey:)`.
- `pruneAccounts(keeping:)` keeps a record when the key with any `#…` suffix stripped is a live
  account id, and keeps `"codex#all"` while any Codex account is live. `migrate(from:to:)` is
  unaffected (Codex ids never carry `pending-`).
- Consequence: the first attributed scan starts a fresh series for the account; the provider-wide
  series under attribution is its own key, so switching accounts never moves a high-water mark
  between series. Nothing is deleted, nothing migrates, no flag.

### Session-log rate-limit fallback

- `CodexSessionRateLimitScanner.creatorAccountId(of file: URL) -> String?`: reads the file's
  **first line** (bounded by `sessionMetaMaxLineBytes = 1 MB`; longer → nil), rejects it with
  `CodexSessionLogParser.isResponseItem`, JSON-decodes it, returns `payload.creator_account_id`
  only when `type == "session_meta"`. Cached **next to the 60 s newest-file cache**
  (`CodexSessionRateLimitScanner.swift:18-21`): `(file, id)` is recomputed only when the newest
  file changes. `nonisolated`, lock-guarded like the rest of the scanner.
- `sessionLogFallback` (`CodexRateLimitFetcher.swift:356`, `@MainActor`) with ≥ 2 ChatGPT
  accounts: the first thing it does is `await Task.detached { newest file + creatorAccountId }`;
  if that id is not this account's, return `cachedOrEmpty` **before** any tail scan. Only the
  matching account proceeds to `latestRateLimits()`. Nothing new runs on the main actor.
- `shouldUseSessionLogFallback(cached:fallbackAsOf:codexAccountCount:rolloutAccountId:accountId:now:)`
  (`nonisolated static`; `now` injected) returns true only when
  `codexAccountCount <= 1 || rolloutAccountId == accountId`, **and**
  `now - fallbackAsOf <= codexFallbackMaxAge` (`7 × 86 400 s`, `spec/CONSTANTS.md`), and the
  existing `fallbackAsOf > cached.fetchedAt` rule.
- **The cached half of the TODOS item.** `cachedOrEmpty` (`:390-407`) re-serves a cached
  `.codexSessionLog` result forever. It now drops the rate limits of a cached result whose
  `rateLimitSource == .codexSessionLog` and `fetchedAt` is older than `codexFallbackMaxAge`
  (empty bars beat a week-old reading on this source only; endpoint-sourced cache keeps the
  "stale beats empty" rule).
- **Documented asymmetry:** only the newest rollout is inspected, so with two accounts the one
  whose CLI session is newest gets the fallback and the other serves its cache. Per-account
  newest-file search is out of scope (`TODOS.md`).

### UI

- `InsightsRowsAndHover.allTimeTooltip(for:since:unattributed:)` appends
  `" · N turns from older Codex CLI versions are not attributable"` when `N > 0`.
- The shared caption line (§2) shows the same count, visible in every chart mode.
- Overview cards unchanged (provider-wide).

### Verification

Fixture-only on this machine. Acceptance = §5 green plus CI. `CHANGELOG.md` under 3.3.0:
"With two or more ChatGPT-backed Codex accounts, each account now shows its own Codex sessions
(current Codex CLI versions stamp rollouts with the account). Verified with fixtures — if you run
two accounts, please report what you see."

## 4. Error handling

- Every new JSON field is optional with a safe default; malformed values never fail a record.
- `unattributedTurnCount` is never shown as a percentage; a nil `creatorAccountId` under `.all`
  is an ordinary entry.
- Head-read failures (short file, no `session_meta`, line over the cap, `response_item` first)
  return nil → the account is treated as not matching → fallback refused for it.
- No migration, so no partial-migration state.

## 5. Testing

- Swift Testing, `@testable import AIBatteryCore`; headless-CI rules from the Phase 2 spec.
- Arrow: §1 (pure helpers only).
- Refactor commit: the whole existing aggregator suite unchanged and green; real-data timing
  recorded in the commit message.
- Attribution:
  - `CodexSessionLogParserTests`: key present; absent; `response_item` noise mentioning the key;
    key present but empty → nil; **two `session_meta` lines** (second carries the key →
    entries after it attributed, entries before it nil); key only on a later `session_meta`.
  - `AttributionTests`: `partition` under `.all` (identity, 0) and `.account` (foreign dropped
    uncounted, nil counted, order preserved).
  - `UsageAggregatorTests`: under `.account`, `detail` excludes foreign and nil entries in every
    accumulator (today / week / month / all-time / projects / `tokenHealth.current` /
    `topSessionHealths` / `firstSessionDate` / `activeUserModel` / `dailyTokenTotals`) while
    `providerWide` equals the `.all` result on the same fixture; `.all` output byte-identical to
    v3.2.0's on the existing fixtures; cache hit on the second call with the same attribution,
    miss after a change of attribution.
  - `UsageSnapshotTests`: `==` differs on `unattributedTurnCount`.
  - `AccountStoreProviderTests`: `attribution(for:provider:accounts:)` truth table (0/1/2
    ChatGPT; API-key active; Claude; mixed).
  - `TokenLedgerTests`: key derivation for all three cases; merge under plain, `#attributed` and
    `codex#all` keeps separate series; prune keeps `"id#attributed"` and `"codex#all"` for a live
    Codex id and drops both when none is live; round-trip of a file holding all three keys.
  - `CodexSessionRateLimitScannerTests`: head read — id at 23 KB; first line over the cap;
    `response_item` first; no `session_meta`; wrong `type`; cache invalidates when the newest
    file changes.
  - `CodexRateLimitFetcherTests`: `shouldUseSessionLogFallback` truth table incl. max-age rows
    (at the limit, one second past); `cachedOrEmpty` drops a stale `.codexSessionLog` result and
    keeps a stale endpoint result.
  - `InsightsTooltipTests` / `InsightsCharts.sinceCaption`: all presence combinations × modes.

## 6. Research items (resolved before coding against them)

| # | Item | Method | Fallback |
|---|---|---|---|
| R1 | `/api/oauth/usage` per-model weekly windows | Phase 2 Task 0 (re-based method, §2) | Drop Phase 2 §5 |
| R2 | `spend_control` period length | glance during Phase 2 Task 8 | observed-pace method |
| R3 | `reasoning_output_tokens` > `output_tokens`? | numbers-only scan in Task 1 | clamp |
| R4 | What does Codex CLI write for `creator_account_id` in API-key mode? | Kyle runs one API-key turn and reports key presence (value masked); or a public fixture | keep `billsLocalCodexCosts`; API-key accounts stay `.all` |

## 7. NOT in scope

- Per-account Codex data with ≤ 1 ChatGPT account (nothing to split).
- Per-account overview cards (D1).
- Attributing old (pre-id) rollouts by any heuristic (time, cwd, login file).
- Per-account newest-rollout search for the fallback (documented asymmetry; `TODOS.md`).
- Reading `~/.codex/auth.json` outside the explicit import click.
- Guarding every view-side `VersionChecker` reference with the compile flag (docs corrected
  instead).
- Always-visible update control; auto-install; a debug override for attribution.
- Cross-provider aggregates; new network requests.
- The remaining `TODOS.md` Codex items (`FileWatcher` gating, `isLoading` reset, callback-server
  hardening) — unrelated to these seams.

## 8. What already exists (reused, not rebuilt)

- `CodexSessionLogParser.applySessionMeta` already decodes the line that carries the id.
- `UsageAggregator`'s loop is the shared cost; the refactor names it, the feature runs it twice
  per entry under attribution, nothing is re-read.
- `TokenLedger.merge` / `pruneAccounts` already key by string; namespacing is a key change.
- `CodexSessionRateLimitScanner.cachedNewestSessionFile` + `CodexSessionLogParser.isResponseItem`
  already provide the file choice and the privacy gate for the head read.
- `aggregateOffMain` already looks up the account store; attribution is decided there.
- `AboutSection.installUpdate`, `ThemeColors.updateAvailable`, `MotionConstants.breathe`,
  `LiveDot`'s reduce-motion pattern, `.contextMenu` precedent in `TokenHealthSection` — the arrow
  composes them.

## 9. Spec/code sync obligations

`spec/ARCHITECTURE.md` (tree: `UpdateArrowButton.swift`, `Attribution.swift`; dispatch seam list
gains `Attribution`; `providerSnapshots` published by `aggregateOffMain`; compile-flag claim
corrected), `spec/DATA_LAYER.md` (`AssistantUsageEntry`, `Attribution`, `AggregationPass`,
`AggregateResult`, `unattributedTurnCount`, ledger key rule, scanner head read + cache, fallback
max age on both paths), `spec/UI_SPEC.md` (header row, overview footer, banner removed, caption
line, tooltip text, context menu), `spec/CONSTANTS.md` (`sessionMetaMaxLineBytes`,
`codexFallbackMaxAge`, Phase 2 constants; compile-flag claim corrected), `CLAUDE.md` ("Codex local
data … same `AssistantUsageEntry`" bullet gains the attribution rule; "Multi-account overview"
bullet: cards stay provider-wide, the *detail* view is per-account for Codex with ≥ 2 ChatGPT
accounts; test counts), `README.md`, `CHANGELOG.md`, `TODOS.md` (close "Per-account attribution"
and "fallback has no maximum age"; add the per-account newest-file search) — all in the same PR.

## Worktree parallelization

| Step | Modules touched | Depends on |
|---|---|---|
| Housekeeping | none (worktrees, website repo) | — |
| Arrow | Views/ (header, overview footer, gear, new button), ViewModels/ (two `withAnimation` sites), Tests/Views | — |
| Aggregator refactor (`AggregationPass`) | Services/UsageAggregator.swift only | — |
| Phase 2 Tasks 0–9 | Models/, Services/ (parsers, aggregator, ledger, fetchers), Views/ (context row, insights, credits) | refactor commit |
| Attribution | Services/ (aggregator, ledger, scanner, fetcher, new Attribution.swift), ViewModels/, Models/ (snapshot), Views/ (insights caption) | Phase 2 Task 1 (entry field) |
| Spec sync | spec/, README, CLAUDE.md, CHANGELOG, TODOS | all |

Lane A: Arrow (independent). Lane B: refactor → Phase 2 → Attribution (sequential, shared
Services/ and Models/). Launch A and B in parallel worktrees; merge A first (small). Conflict
flag: `UsagePopoverView.swift` is touched by A (pass `availableUpdate`) and by Phase 2 only if
Task 6 is IN — merge A before starting Task 6; `UsageViewModel+Refresh.swift` is touched by A
(one `withAnimation`) and by Attribution — merge A first.

## GSTACK REVIEW REPORT

| Review | Trigger | Why | Runs | Status | Findings |
|--------|---------|-----|------|--------|----------|
| CEO Review | `/plan-ceo-review` | Scope & strategy | 0 | — | — |
| Codex Review | `/codex review` | Independent 2nd opinion | 2 (Claude subagents; Codex CLI blocked by the worktree shell guard) | issues_found | run 1: 16 findings, 15 folded, 1 deferred; run 2: 20 findings, 19 folded, 1 deferred (view-side flag guarding) |
| Eng Review | `/plan-eng-review` | Architecture & tests (required) | 2 | clean | 9 in-session issues + 36 outside-voice findings, 0 critical gaps, 7 decisions (D1–D7) resolved |
| Design Review | `/plan-design-review` | UI/UX gaps | 0 | — | — |
| DX Review | `/plan-devex-review` | Developer experience gaps | 0 | — | — |

- **CROSS-MODEL:** Run 2 independently found that the FS-driven path (every ~2 s during a Codex session) would run two cold passes and that the `.all` ledger series keyed by the active account would split; both reversed review-1 decisions (D2 keyed cache → single pass with two snapshots; plain key → `codex#all`). No remaining disagreement.
- **VERDICT:** ENG CLEARED — ready for `writing-plans`. Design review optional (arrow + caption are small UI changes on established patterns).

NO UNRESOLVED DECISIONS

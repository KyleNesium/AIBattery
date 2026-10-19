# v3.3.0 Release — Design Spec

**Date:** 2026-10-19 (revised the same day after `/plan-eng-review` + outside voice)
**Status:** Reviewed; awaiting Kyle's read before `writing-plans`
**Base:** `main` @ `e768fa6` (v3.2.0). Branch `worktree-v3-3-0`, worktree `.claude/worktrees/v3-3-0`.
**Ships as:** one integration branch, one draft PR, tested locally per task, CI once when ready
(project rule: no CI fan-out). Tag `v3.3.0` after Kyle's manual check of the Phase 2 + arrow
behaviour; attribution ships fixture-verified (see §2 "Verification").

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

Settled in brainstorming (morning) and revised in the engineering review (afternoon). Each row says
which.

| Question | Decision | When |
|---|---|---|
| Release structure | One branch, one PR; arrow → Phase 2 → attribution. | brainstorm, order revised in review (D-order) |
| Turns without `creator_account_id` when ≥ 2 ChatGPT Codex accounts exist | **Hidden** from every account, never over-counted. With ≤ 1 ChatGPT Codex account nothing changes. | brainstorm |
| Where the hidden count is shown | A visible caption in the Insights section when N > 0 **and** the All-Time tooltip. (Review note: the spec first said "the existing caveat line" — there is none; the only Codex caveat today is the All-Time tooltip at `InsightsRowsAndHover.swift:49`. The caption is new and shares the line Phase 2 §8 adds for "since <date>".) | review D6 |
| Ledger with ≥ 2 ChatGPT Codex accounts | **Namespaced ledger key** `"<accountId>#attributed"` for attributed scans. No reset, no migration flag. Replaces the brainstorm's one-time reset: `TokenLedger.save()` is async (`TokenLedger.swift:171`) so a flag-after-reset could land without the reset, and a single-account `.all` ledger already contains unattributable turns that a later-added second account could never purge. | review D4 |
| Overview cards with two ChatGPT Codex accounts | **Provider-wide** (`.all`), as the cards are labelled. Attribution exists only in the active detail view. An attributed snapshot never enters `providerSnapshots`. | review D1 |
| Aggregator redundant-skip cache | **Keyed by attribution** (small dictionary), so the detail pass and the overview pass both hit the cache on idle cycles instead of thrashing one slot. | review D2 |
| Session-log fallback maximum age | **Built in this PR** (TODOS.md third-review item): a rollout reading older than `codexFallbackMaxAge` is refused. | review D3 |
| Attribution verification | **Fixture-verified**; this machine has one Codex account and one id in 942 rollouts, so no manual check can see the split. CHANGELOG says so and asks two-account users to report. No debug override. | review D5 |
| Update arrow visibility | Only when `availableUpdate != nil`. Banner and gear badge removed. Settings → About unchanged. | brainstorm |
| Phase 2 contents | Unchanged from the 2026-10-12 spec: §1–§5, §7, §8. §6 shipped in v3.1.0, §9 superseded. §5 stays conditional on Task 0. | brainstorm |
| Billing heuristic (`billsLocalCodexCosts`) | Kept. R4 decides whether attribution can replace it. | brainstorm |

## 0. Housekeeping (before the feature branch starts; on `main`, no app code)

- Worktrees `agent-a75a12ee…`, `agent-a7d1d030…`, `agent-a8399f01…`, `agent-a92e92e3…`,
  `agent-ab144e4d…`, `agent-ab8106f4…` (subagent scratch from the v3.2.0 review-fixes session),
  `sparkle-2-10` (PR #199, absorbed into #201), `review-fixes-2026-10` (PR #203, merged) and the
  mis-named entry at path `.claude/worktrees/Users/kyle/workspace/Github/KyleNesium` (merged).
  For each: (a) `git diff --stat origin/main <branch> -- AIBattery Tests` must be empty or contain
  only changes already on `main` in another form — anything else is reported to Kyle before
  removal; (b) **no Claude session may be open on the path** (another session's scratchpad or cwd
  under it counts) — check with Kyle, do not guess; then `git worktree remove <path>` +
  `git branch -D <branch>`. Remove by **path**, not branch name.
- `aibattery-web`: `npm run sync:app` for 3.2.0, copy update for the 1%-as-100% fix if the
  changelog warrants it, PR with a merge commit (recipe in the website memory).

## 1. Header update arrow

- New standalone view `UpdateArrowButton(update: VersionChecker.UpdateInfo)` in
  `AIBattery/Views/UpdateArrowButton.swift`, compiled under `#if ENABLE_VERSION_CHECKER` like
  everything that touches `VersionChecker`:
  - `Image(systemName: "arrow.up.circle")`, `Typography.headerGear`, square frame of
    `Layout.accountChipHeight`, `ThemeColors.updateAvailable`, glow
    `.shadow(color: ThemeColors.updateAvailable.opacity(ThemeColors.chevronGlowOpacity), radius: Layout.glowRadius)`.
  - Opacity breathes between 1 and `ThemeColors.liveDotDimOpacity` with
    **`MotionConstants.breathe`** (1.6 s ease-in-out, repeat forever — the `LiveDot` pattern),
    disabled under `accessibilityReduceMotion`. Not `MotionConstants.standard` (0.15 s — a flicker).
  - Primary click: `AboutSection.installUpdate(update)` (Sparkle check when available, release
    page otherwise). Because the arrow's *visibility* comes from GitHub Releases
    (`UsageViewModel+Refresh.swift:469`) while the click runs a Sparkle check against the appcast,
    the two can disagree when the appcast lags a release. So the button also carries a
    `.contextMenu` with **"Release notes"** (opens `update.url`) and **"Check for Updates"**
    (`installUpdate` again), and the help text is `"v\(version) available — click to update"`.
  - Accessibility label "Update available, version \(version)", hint "Downloads and installs the
    update; right-click for release notes".
- Placement: immediately left of the gear in **both** `PopoverHeaderView` (detail header) and
  `OverviewFooterView` (`OverviewContentView.swift:47`, a separate struct whose gear carries
  `label: "Settings"`). Both insert the same `UpdateArrowButton`; there is no shared "gear with
  arrow" helper because the two gears differ by label. `OverviewFooterView` and
  `OverviewContentView` gain `availableUpdate: VersionChecker.UpdateInfo?` (replacing
  `showsUpdateBadge: Bool`), passed from `UsagePopoverView`. Appears/disappears with
  `MotionConstants.expandTransition`.
- Removed: `PopoverHeaderView.updateBanner`, `updateBannerDismissed`, both
  `gearShowsUpdateBadge` computed properties (`PopoverHeaderView.swift:86`,
  `UsagePopoverView.swift:227`), `SettingsGearButton.showsUpdateBadge` and its overlay / help /
  accessibility variants. `ThemeColors.updateAvailable` stays (Settings → About uses it).
- No existing test references the banner or badge (verified: zero hits under `Tests/`), so this
  is new coverage, not updates: `UpdateArrowButtonTests` (pure text helpers: help string,
  accessibility label, menu item titles) and an extension of `PopoverHeaderBackTests` /
  `OverviewClockTests` where header/footer composition is already pinned.

## 2. Phase 2 — provider-relevant display (re-base notes)

The 2026-10-12 spec is authoritative for behaviour. The plan is re-based, not rewritten:

- Branch / changelog: `worktree-v3-3-0`, `## [3.3.0] — Unreleased`. The plan's "Phase 2 of the
  v3.1.0 release plan" framing is replaced by this spec.
- **Task 0 was never run.** It stays first within Phase 2. Its log line goes in
  `RateLimitFetcher+UsageEndpoint.swift` `interpretUsageEndpoint` (line 31 on main).
- `RateLimitUsage.swift` was split in v3.2.0: parsing now lives in
  `AIBattery/Models/RateLimitUsage+Parsing.swift`. Conditional Task 6's `modelWindows` parsing
  goes there.
- Line anchors moved (`makeUsageEntry` 557, `TokenHealthMonitor.assess` 119, `LedgerData` 215,
  `ModelTokenRecord` 219). Every task re-locates by symbol, not line.
- `TokenHealthSection`, `SessionLogReader`, `UsageAggregator`, `MultiAccountFanOut`,
  `CodexRateLimitFetcher` all changed in v3.2.0; the implementer re-reads each before editing.
- Task 1 (new entry fields) also adds `creatorAccountId` from §3 below — one touch of
  `AssistantUsageEntry` and both parsers, not two. The field is inert until §3's aggregation
  task lands.
- **One tooltip signature.** Phase 2 Task 9 names `InsightsView.allTimeTooltip(for:since:)`; the
  real function is `InsightsRowsAndHover.allTimeTooltip(for:)` (`:46`). The re-based plan uses
  `InsightsRowsAndHover.allTimeTooltip(for:since:unattributed:)` once; Task 9 adds `since:`,
  §3 adds `unattributed:` (default 0) — the signature is touched twice but defined once.
- **One caption line.** Task 9's "since <date>" caption under the 12M chart and §3's hidden-turn
  caption are the same `Typography.monoTiny` tertiary line:
  `"since 12 Oct 2026 · 902 turns from older Codex CLI versions not shown"`; either half can be
  absent. Pure formatter `InsightsCharts.sinceCaption(provider:since:unattributed:now:)`.
- `firstScan` (Task 9) is keyed by the **ledger key**, so under attribution it is the first
  *attributed* scan for that account — exactly the "since" date the user should see. If Task 9 is
  cut, §3 has no dependency on it.

## 3. Codex per-account attribution

### Ground truth (this machine, 2026-10-19)

- `~/.codex/sessions`: 942 rollouts; **40** carry `session_meta.payload.creator_account_id`
  (all from the current CLI; March 2026 rollouts have `session_meta` without it). One distinct
  id locally — equal to the app's Codex account id (`JWTDecoder.chatGPTAccountId(idToken:)`,
  `OAuthManager+Codex.swift:107`; Codex accounts never carry `pending-` ids).
- `session_meta` is **line 1 in 943 of 943 rollouts**, but that line carries
  `base_instructions`, so the id sits as far as **23 KB** into the file. Any head read must read
  the whole first line, not a fixed prefix.
- `session_meta.payload` keys seen: `base_instructions, cli_version, cwd, git, id,
  model_provider, originator, source, creator_account_id` (+ `history_mode`, `repository_url` on
  some).
- Nothing on this machine shows what **API-key** mode writes (R4).

### Data model

- `AssistantUsageEntry` gains `let creatorAccountId: String?` — nil for Claude and for rollouts
  without the key.
- `CodexSessionLogParser.applySessionMeta` reads `payload["creator_account_id"] as? String`
  (non-empty) into `creatorAccountId`, carried onto every entry of the file like `cwd`.
- `SessionLogReader.makeUsageEntry` passes nil.

### Aggregation

- `enum Attribution: Hashable, Sendable { case all; case account(String) }` in
  `AIBattery/Services/UsageAggregator.swift` (or its own file if the aggregator file would pass
  800 lines).
- `UsageAggregator.aggregate(...)` gains `attribution: Attribution = .all`.
- **Partition first, then everything downstream sees only the kept entries.** A pure, tested
  helper `UsageAggregator.partition(_ entries: [AssistantUsageEntry], by: Attribution) ->
  (kept: [AssistantUsageEntry], unattributed: Int)` runs right after `readAllUsageEntries()`.
  Under `.all` it returns the input and 0 (no copy). Under `.account(id)` it keeps entries whose
  `creatorAccountId == id`, counts nil-id entries into `unattributed`, and drops foreign ids
  uncounted. The loop, `todayEntries`, `firstSessionDate` (`:392`),
  `TokenHealthMonitor.assessSessions` (`:398`) and `SideEffects.activeUserModel` (`:521`) all
  take `kept` — the review found the spec's first draft filtered inside the loop and silently
  left those four on the unfiltered array.
- `UsageSnapshot` gains `let unattributedTurnCount: Int` (0 under `.all`) **and the hand-written
  `==` at `UsageSnapshot.swift:36-46` compares it.**
- **Cache keyed by attribution.** The redundant-aggregation slot (`cachedSnapshot`,
  `cachedEffects`, `last*` fingerprint fields, `UsageAggregator.swift:104-160`) becomes a
  dictionary `[Attribution: CacheEntry]` where `CacheEntry` bundles the snapshot, effects and
  fingerprint. `invalidate()` clears the whole dictionary. Lookup and store go through the same
  lock. Test: two attributions aggregated alternately both hit the cache on the second round.
- **Where attribution is decided.** `UsageViewModel.aggregateOffMain` gains
  `attribution: Attribution = .all`. The active-account refresh path passes
  `.account(id)` when `provider == .codex` **and** the store holds ≥ 2 ChatGPT-backed Codex
  accounts (`!isAPIKeyAccount`), else `.all`; pure helper
  `AccountStore.attribution(for activeId: String, accounts: [AccountRecord]) -> Attribution`,
  tested next to `billsLocalCodexCosts`. API-key active accounts always get `.all`.
- **Overview stays provider-wide.** `aggregateOtherProviders` (`UsageViewModel+FanOut.swift:70`)
  always passes `.all`. The `snapshot.didSet` mirror at `UsageViewModel.swift:14` only publishes
  into `providerSnapshots` when the snapshot's attribution is `.all` — so `UsageSnapshot` also
  records `let attribution: Attribution` (default `.all`, part of `==`). When the active detail
  pass was attributed, the refresh path additionally runs the `.all` pass for the active provider
  and publishes that one to `providerSnapshots` (cheap: same reader cache, attribution-keyed
  aggregator cache). Cards therefore keep showing tokens-today / live dot for the whole provider,
  as `AccountCard.swift:94-100` reads them today.

### Ledger (namespaced key, no migration)

- `TokenLedger.key(accountId:attribution:) -> String`: `accountId` under `.all`,
  `"\(accountId)#attributed"` under `.account`. `merge(_:accountId:)` becomes
  `merge(_:ledgerKey:)`; the aggregator passes the key for the attribution it is running.
- `pruneAccounts(keeping:)` keeps a record when the key **with any `#…` suffix stripped** is a
  live account id. `migrate(from:to:)` is unaffected (Codex ids never resolve from `pending-`).
- Consequence: the first attributed scan starts a fresh high-water series for that account; the
  old `.all` series stays on disk under the plain key and is read again if the user drops back to
  one Codex account. Nothing is deleted, nothing migrates, no flag.

### Session-log rate-limit fallback

- `CodexSessionRateLimitScanner.creatorAccountId(of file: URL) -> String?`: reads the file's
  **first line** (bounded by a new `sessionMetaMaxLineBytes = 1 MB`; a longer line → nil),
  rejects it if `isResponseItem`, JSON-decodes it, returns `payload.creator_account_id` only when
  `type == "session_meta"`. Keys and that one value only.
- `sessionLogFallback` (`CodexRateLimitFetcher.swift:356`) with ≥ 2 ChatGPT accounts: the **first**
  thing it does is `cachedNewestSessionFile` (60 s TTL, already cached) + `creatorAccountId(of:)`.
  If that id is not this account's, return `cachedOrEmpty` **before** any tail scan — the tail
  scan + tree walk per account per poll is exactly what the existing short-circuit prevents.
  Only the matching account proceeds to `latestRateLimits()`.
- `shouldUseSessionLogFallback(cached:fallbackAsOf:codexAccountCount:rolloutAccountId:accountId:now:)`
  returns true only when: `codexAccountCount <= 1 || rolloutAccountId == accountId`, **and**
  `now - fallbackAsOf <= codexFallbackMaxAge` (**new, TODOS.md item closed**: `7 × 86 400 s` in
  `spec/CONSTANTS.md`), and the existing `fallbackAsOf > cached.fetchedAt` rule.
- **Documented asymmetry:** only the newest rollout on disk is inspected, so with two accounts the
  one whose CLI session is newest gets the fallback and the other serves its cache. That is the
  same as today for the other account and strictly better for one of them; per-account newest-file
  search is out of scope (`TODOS.md` entry, see §7).

### UI

- `InsightsRowsAndHover.allTimeTooltip(for:since:unattributed:)` appends
  `" · N turns from older Codex CLI versions are not attributable"` when `N > 0`.
- The shared Insights caption line (see §2 "One caption line") shows the same count visibly.
- Cards on the overview are unchanged (provider-wide).

### Verification

Fixture-only on this machine (one Codex account, one id). Acceptance = the §5 test list green
plus `swift test` on CI. `CHANGELOG.md` under 3.3.0 states: "With two or more ChatGPT-backed Codex
accounts, each account now shows its own Codex sessions (new Codex CLI versions stamp rollouts
with the account). Verified with fixtures — if you run two accounts, please report what you see."

## 4. Error handling

- Every new JSON field is optional with a safe default; malformed values never fail a record.
- `unattributedTurnCount` is never shown as a percentage; a nil `creatorAccountId` under `.all`
  is an ordinary entry.
- Head-read failures (short file, no `session_meta`, line over the cap, `response_item` first)
  return nil → the account is treated as not matching → fallback refused for it.
- No migration, so no partial-migration state.

## 5. Testing

- Swift Testing, `@testable import AIBatteryCore`; headless-CI rules from the Phase 2 spec.
- Arrow: see §1.
- Attribution:
  - `CodexSessionLogParserTests`: fixture with the key, without the key, with `response_item`
    noise, key present but empty → nil.
  - `UsageAggregatorTests`: `partition` under `.all` (identity, 0) and `.account` (foreign
    dropped uncounted, nil counted, kept order preserved); every accumulator — today / week /
    month / all-time / projects / `tokenHealth.current` / `topSessionHealths` /
    `firstSessionDate` / `activeUserModel` / `dailyTokenTotals` — excludes foreign and nil
    entries; `.all` output identical to today's on the same fixture; cache hit on the second
    round for each of two alternating attributions; `invalidate()` clears both.
  - `UsageSnapshotTests`: `==` differs on `unattributedTurnCount` and on `attribution`.
  - `AccountStoreProviderTests`: `attribution(for:accounts:)` truth table (0/1/2 ChatGPT,
    API-key active, mixed).
  - `UsageViewModel` publishing rule: `providerSnapshots` ignores an attributed snapshot — pinned
    via a pure static `UsageViewModel.shouldMirrorToProviderSnapshots(_:)` (no `UsageViewModel()`
    in tests).
  - `TokenLedgerTests`: key derivation; merge under both keys keeps separate series; prune keeps
    `"id#attributed"` for a live `id` and drops it for a dead one; round-trip of a file holding
    both keys.
  - `CodexSessionRateLimitScannerTests`: head read — id present at 23 KB, first line over the cap,
    `response_item` first, no `session_meta`, wrong `type`.
  - `CodexRateLimitFetcherTests`: `shouldUseSessionLogFallback` truth table incl. the max-age rows
    (exactly at the limit, one second past).
  - `InsightsCharts.sinceCaption` / `allTimeTooltip`: all four presence combinations.
- README "Test Coverage" + `CLAUDE.md` counts in the wrap-up task.

## 6. Research items (resolved before coding against them)

| # | Item | Method | Fallback |
|---|---|---|---|
| R1 | `/api/oauth/usage` per-model weekly windows | Phase 2 Task 0 | Drop Phase 2 §5 |
| R2 | `spend_control` period length | glance during Phase 2 Task 8 | observed-pace method |
| R3 | `reasoning_output_tokens` > `output_tokens`? | numbers-only scan in Task 1 | clamp |
| R4 | What does Codex CLI write for `creator_account_id` in API-key mode? | Kyle runs one API-key turn and reports key presence (value masked); or a public fixture | keep `billsLocalCodexCosts`; API-key accounts stay `.all` |

## 7. Out of scope / NOT in scope

- Per-account Codex data with ≤ 1 ChatGPT account (nothing to split).
- Per-account overview cards (D1: cards are provider-wide; a per-account map would need one
  aggregation per Codex account per cycle).
- Attributing old (pre-id) rollouts by any heuristic (time, cwd, login file).
- Per-account newest-rollout search for the fallback (documented asymmetry; `TODOS.md`).
- Reading `~/.codex/auth.json` outside the explicit import click.
- Always-visible update control; auto-install; a debug override for attribution.
- Cross-provider aggregates; new network requests.
- The remaining `TODOS.md` Codex items (`FileWatcher` gating, `isLoading` reset, callback-server
  hardening) — unrelated to these seams.

## 8. What already exists (reused, not rebuilt)

- `CodexSessionLogParser.applySessionMeta` already decodes the line that carries the id.
- `UsageAggregator` already runs per account id for the ledger; attribution is one partition
  before its loop.
- `TokenLedger.merge` / `pruneAccounts` already key by string; namespacing is a key change.
- `CodexSessionRateLimitScanner.cachedNewestSessionFile` + `isResponseItem` already provide the
  file choice and the privacy gate for the head read.
- `AboutSection.installUpdate`, `ThemeColors.updateAvailable`, `MotionConstants.breathe`,
  `LiveDot`'s reduce-motion pattern — the arrow composes them.
- `billsLocalCodexCosts` stays the cost-framing rule.

## 9. Spec/code sync obligations

`spec/ARCHITECTURE.md` (tree: `UpdateArrowButton.swift`; dispatch seam list gains `Attribution`;
`providerSnapshots` publishing rule), `spec/DATA_LAYER.md` (`AssistantUsageEntry`,
`Attribution`, `partition`, `unattributedTurnCount`, attribution-keyed cache, ledger key
namespacing, scanner head read, fallback max age), `spec/UI_SPEC.md` (header row, overview
footer, banner removed, caption line, tooltip text, context menu), `spec/CONSTANTS.md`
(`sessionMetaMaxLineBytes`, `codexFallbackMaxAge`, Phase 2 constants), `CLAUDE.md` ("Codex local
data … same `AssistantUsageEntry`" bullet gains the attribution rule; "Multi-account overview"
bullet: cards stay provider-wide, the *detail* view is per-account for Codex with ≥ 2 ChatGPT
accounts), `README.md`, `CHANGELOG.md`, `TODOS.md` (close "Per-account attribution" and
"fallback has no maximum age"; add the per-account newest-file search) — all in the same PR.

## Worktree parallelization

| Step | Modules touched | Depends on |
|---|---|---|
| Housekeeping | none (worktrees, website repo) | — |
| Arrow | Views/ (header, overview footer, new button), Tests/Views | — |
| Phase 2 Tasks 0–9 | Models/, Services/ (parsers, aggregator, ledger, fetchers), Views/ (context row, insights, credits) | — |
| Attribution | Services/ (aggregator, ledger, scanner, fetcher), ViewModels/, Models/ (snapshot), Views/ (insights caption) | Phase 2 Task 1 (entry field) |
| Spec sync | spec/, README, CLAUDE.md, CHANGELOG, TODOS | all |

Lane A: Arrow (independent). Lane B: Phase 2 → Attribution (sequential, shared Services/ and
Models/). Launch A and B in parallel worktrees; merge A first (small). Conflict flag: both lanes
touch `Views/` — A only touches header/footer/gear files, B never does; `UsagePopoverView.swift`
is touched by A (pass `availableUpdate`) and by Phase 2 only if Task 6 is IN (per-model rows) —
merge A before starting Task 6.

## GSTACK REVIEW REPORT

| Review | Trigger | Why | Runs | Status | Findings |
|--------|---------|-----|------|--------|----------|
| CEO Review | `/plan-ceo-review` | Scope & strategy | 0 | — | — |
| Codex Review | `/codex review` | Independent 2nd opinion | 1 (Claude subagent; Codex CLI blocked by the worktree shell guard) | issues_found | 16 findings, 15 folded, 1 deferred to TODOS (per-account newest file) |
| Eng Review | `/plan-eng-review` | Architecture & tests (required) | 1 | clean | 9 issues (4 architecture, 2 code quality, 2 test, 1 performance), 0 critical gaps, 6 decisions (D1–D6) all resolved |
| Design Review | `/plan-design-review` | UI/UX gaps | 0 | — | — |
| DX Review | `/plan-devex-review` | Developer experience gaps | 0 | — | — |

- **CROSS-MODEL:** The subagent independently found the overview-card mirror (`UsageViewModel.swift:14`) and the ledger-reset holes; the in-session review had found the in-loop filter, the 4 KB head read and the cache thrash. No disagreement on any folded item; the one tension (per-account newest-file search for the fallback) was deferred with a documented asymmetry.
- **VERDICT:** ENG CLEARED — ready for `writing-plans`. Design review optional (arrow + caption are small UI changes on established patterns).

NO UNRESOLVED DECISIONS

# v3.3.0 Release — Design Spec

**Date:** 2026-10-19
**Status:** Approved in brainstorming (Kyle, 2026-10-19); awaiting written-spec review
**Base:** `main` @ `e768fa6` (v3.2.0). Branch `worktree-v3-3-0`, worktree `.claude/worktrees/v3-3-0`.
**Ships as:** one integration branch, one draft PR, tested locally per task, CI once when ready
(project rule: no CI fan-out). Tag `v3.3.0` after Kyle's manual check.

## Goal

Three pieces of work, in this order, each cuttable from the end without unpicking the earlier ones:

1. **Phase 2 — provider-relevant display.** The already-approved spec
   `2026-10-12-provider-relevance-design.md` and its plan, re-based onto v3.2.0.
2. **Codex per-account attribution.** With two or more ChatGPT-backed Codex accounts, each
   account's Insights / Projects / Context show only its own turns.
3. **Header update arrow.** Replace the update banner + gear badge with one arrow button that
   appears only when a release is available and installs it through Sparkle.

Preceded by **housekeeping on `main`** (no app code): verify and remove the seven stale
worktrees, sync `aibattery-web` to 3.2.0.

## Decisions (settled during brainstorming, 2026-10-19)

| Question | Decision |
|---|---|
| Release structure | One branch, one PR, Phase 2 → attribution → arrow. Attribution last of the data work so it can be cut. |
| Turns without `creator_account_id` when ≥ 2 ChatGPT Codex accounts exist | **Hidden** from every account; the Codex Insights All-Time tooltip appends "N turns from older Codex CLI versions are not attributable". Never over-count. With ≤ 1 ChatGPT Codex account nothing changes. |
| Ledger with ≥ 2 ChatGPT Codex accounts | One-time reset of every Codex account's all-time records, gated on a stored migration flag, performed only when ≥ 2 ChatGPT Codex accounts exist at migration time. Single-account users are untouched. |
| Update arrow visibility | Only when `availableUpdate != nil`. Settings → About keeps the manual "Check for Updates". Banner and gear badge are removed. |
| Phase 2 contents | Unchanged from the 2026-10-12 spec: §1–§5, §7, §8. §6 shipped in v3.1.0, §9 superseded. §5 (per-model weekly windows) stays conditional on Task 0. |
| Billing heuristic (`billsLocalCodexCosts`) | Kept as is. Research item R4 decides whether attribution can replace it (needs an API-key rollout fixture). |

## 0. Housekeeping (before the feature branch starts; on `main`, no app code)

- Worktrees `agent-a75a12ee…`, `agent-a7d1d030…`, `agent-a8399f01…`, `agent-a92e92e3…`,
  `agent-ab144e4d…`, `agent-ab8106f4…` (subagent scratch from the v3.2.0 review-fixes session) and
  `sparkle-2-10` (PR #199, absorbed into #201): for each, `git diff --stat origin/main <branch> -- AIBattery Tests`
  must be empty or contain only changes that are already on `main` in another form. Any non-empty
  diff is reported to Kyle before removal; otherwise `git worktree remove` + `git branch -D`.
  `review-fixes-2026-10` (PR #203, merged) goes the same way. The odd `worktree-/Users/kyle/…`
  entry is merged and is removed too.
- `aibattery-web`: `npm run sync:app` for 3.2.0, update copy for the 1%-as-100% fix if the
  changelog section warrants it, PR with a merge commit (recipe in the website memory).

## 1. Phase 2 — provider-relevant display (re-base notes)

The 2026-10-12 spec is authoritative for behaviour. The plan is re-based, not rewritten:

- Branch / changelog: `worktree-v3-3-0`, `## [3.3.0] — Unreleased`. The plan's "Phase 2 of the
  v3.1.0 release plan" framing is replaced by this spec.
- **Task 0 was never run.** It stays first. Its log line goes in
  `RateLimitFetcher+UsageEndpoint.swift` `interpretUsageEndpoint` (still line 31 on main).
- `RateLimitUsage.swift` was split in v3.2.0: parsing now lives in
  `AIBattery/Models/RateLimitUsage+Parsing.swift`. Conditional Task 6's `modelWindows` parsing
  goes there.
- Line anchors moved (`makeUsageEntry` 557, `TokenHealthMonitor.assess` 119, `LedgerData` 215,
  `ModelTokenRecord` 219). Every task re-locates by symbol, not line.
- `TokenHealthSection`, `SessionLogReader`, `UsageAggregator`, `MultiAccountFanOut`,
  `CodexRateLimitFetcher` all changed in v3.2.0; the implementer re-reads each before editing.
- Task 1 (new entry fields) also adds `creatorAccountId` from §2 below — one touch of
  `AssistantUsageEntry` and both parsers, not two.

## 2. Codex per-account attribution

### Ground truth (this machine, 2026-10-19)

- `~/.codex/sessions`: 942 rollouts; **40** carry `session_meta.payload.creator_account_id`
  (all from the current CLI; March 2026 rollouts have `session_meta` without it). One distinct
  id locally — equal to the app's Codex account id (observed 2026-10-10, Codex CLI 0.160.1).
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

- `UsageAggregator.aggregate(...)` gains `attribution: Attribution = .all` where
  `enum Attribution: Equatable, Sendable { case all; case account(String) }`.
- `UsageViewModel` computes it at the existing call site next to `costIsBilled`:
  `.account(id)` when `provider == .codex` **and** the store holds ≥ 2 ChatGPT-backed Codex
  accounts (`!isAPIKeyAccount`), else `.all`. API-key active accounts always get `.all`
  (their rollouts carry no ChatGPT id; R4 may refine this).
- Under `.account(id)`, the single entry loop in `aggregate` skips any entry whose
  `creatorAccountId != id` **before** every accumulation (today / week / month / all-time /
  projects / session context / activity chart). Entries with a nil id are counted into
  `unattributedTurnCount` and skipped.
- `UsageSnapshot` gains `let unattributedTurnCount: Int` (0 under `.all`).
- The aggregator cache fingerprint already keys on `accountId`; `attribution` is added to it so
  switching between two Codex accounts never serves the other's snapshot.
- `TokenHealthMonitor` receives the already-filtered entries — no change.

### Ledger

- `TokenLedger.resetCodexRecords(accountIds:)` removes the records for the given accounts
  (`firstScan` entries too, once Phase 2 §8 adds them) and saves.
- `OAuthManagerMigrations` (same pattern as `aibattery_keychainThisDeviceOnlyMigrated`): key
  `aibattery_codexLedgerAttributionReset_v1`. On first launch with the flag unset: if the store
  holds ≥ 2 ChatGPT-backed Codex accounts, reset every Codex account's ledger records; set the
  flag either way. A user who adds a second ChatGPT account later gets no reset — their first
  account's ledger was correct (single-account = `.all` = exact), and the second starts empty.

### Session-log rate-limit fallback

- `CodexSessionRateLimitScanner` gains `creatorAccountId(of file:)`: reads the first 4 KB of the
  newest rollout, finds the `session_meta` line, returns `creator_account_id` (keys-only JSON
  decode of that one line; `response_item` rejection applies as everywhere).
- `shouldUseSessionLogFallback(cached:fallbackAsOf:codexAccountCount:)` gains
  `rolloutAccountId: String?` and `accountId: String`: with `codexAccountCount >= 2` it now
  returns true only when `rolloutAccountId == accountId`. `sessionLogFallback` drops its
  "≥ 2 → return cached" short-circuit in favour of this check (the head read is 4 KB, cheap).

### UI

- `InsightsRowsAndHover.allTimeTooltip(for:unattributed:)` appends
  `" · N turns from older Codex CLI versions are not attributable"` when `N > 0`. Nothing else
  changes visually; cards on the overview stay quota-only.

## 3. Header update arrow

- New view `UpdateArrowButton(update: VersionChecker.UpdateInfo, action: () -> Void)`:
  `Image(systemName: "arrow.up.circle")`, `Typography.headerGear`, frame
  `Layout.accountChipHeight` square, `ThemeColors.updateAvailable`, glow
  `.shadow(color: updateAvailable.opacity(ThemeColors.chevronGlowOpacity), radius: Layout.glowRadius)`,
  opacity pulse between 1 and `ThemeColors.liveDotDimOpacity` on a repeating
  `MotionConstants.standard`-length ease, disabled under `accessibilityReduceMotion` (same
  pattern as `LiveDot`). `.help("Update to v\(version)")`, accessibility label
  "Update available, version \(version)", hint "Downloads and installs the update".
- Placement: immediately left of the gear in `PopoverHeaderView` (detail header) and in
  `OverviewContentView`'s footer, both via a shared `gearWithUpdate` helper so the two rows stay
  identical. Appears/disappears with `MotionConstants.expandTransition`.
- Action: `AboutSection.installUpdate(update)` (Sparkle when available, release page otherwise).
- Removed: `PopoverHeaderView.updateBanner`, `updateBannerDismissed`, `gearShowsUpdateBadge`
  (both views), `SettingsGearButton.showsUpdateBadge` and its overlay/help/accessibility
  variants. `ThemeColors.updateAvailable` stays (Settings → About still uses it).
- Settings → About: unchanged (manual check, install button, error copy).

## 4. Error handling

- Every new JSON field is optional with a safe default; malformed values never fail a record.
- `unattributedTurnCount` is never shown as a percentage; a nil `creatorAccountId` under `.all`
  is an ordinary entry.
- The ledger reset runs once; the flag is written after the reset. A crash between reset and
  flag re-runs the reset on the next launch, which is harmless because the records are being
  rebuilt from the same scan.
- Fallback head read failures (short file, no `session_meta`) return nil → treated as "unknown"
  → fallback refused when ≥ 2 accounts (today's behaviour).

## 5. Testing

- Swift Testing, `@testable import AIBatteryCore`; headless-CI rules from the Phase 2 spec.
- Attribution: parser fixture with/without the key (and with `response_item` noise); aggregator
  `.account` filter — every accumulator excludes foreign and nil entries, `unattributedTurnCount`
  exact; `.all` identical to today's output on the same fixture; cache fingerprint differs by
  attribution; ledger reset only with ≥ 2 ChatGPT accounts, flag set either way, API-key accounts
  don't count; scanner head read; `shouldUseSessionLogFallback` truth table.
- Arrow: `PopoverHeaderView`/`OverviewContentView` text/accessibility tests where the existing
  header tests live; removal of the badge paths pinned by the updated `SettingsGearButton` tests.
- README "Test Coverage" + `CLAUDE.md` counts in the wrap-up task.

## 6. Research items (resolved before coding against them)

| # | Item | Method | Fallback |
|---|---|---|---|
| R1 | `/api/oauth/usage` per-model weekly windows | Phase 2 Task 0 | Drop Phase 2 §5 |
| R2 | `spend_control` period length | glance during Phase 2 Task 8 | observed-pace method |
| R3 | `reasoning_output_tokens` > `output_tokens`? | numbers-only scan in Task 1 | clamp |
| R4 | What does Codex CLI write for `creator_account_id` in API-key mode? | Kyle runs one API-key turn and reports the key presence (value masked); or a public fixture | keep `billsLocalCodexCosts` heuristic; API-key accounts stay `.all` |

## 7. Out of scope

- Per-account Codex data with ≤ 1 ChatGPT account (nothing to split).
- Attributing old (pre-id) rollouts by any heuristic (time, cwd, login file).
- Reading `~/.codex/auth.json` outside the explicit import click.
- Always-visible update control; auto-install.
- Cross-provider aggregates; new network requests.

## 8. Spec/code sync obligations

`spec/ARCHITECTURE.md` (tree: `UpdateArrowButton.swift`; dispatch seam list gains
`Attribution`), `spec/DATA_LAYER.md` (`AssistantUsageEntry`, `Attribution`,
`unattributedTurnCount`, ledger reset migration, scanner head read), `spec/UI_SPEC.md` (header
row, overview footer, banner removed, tooltip text), `spec/CONSTANTS.md`
(`aibattery_codexLedgerAttributionReset_v1`, 4 KB head read, Phase 2 constants), `CLAUDE.md`
("Codex local data … same `AssistantUsageEntry`" bullet gains the attribution rule; "Multi-account
overview" bullet's "never per-account Insights" sentence is amended), `README.md`, `CHANGELOG.md`
— all in the same PR.

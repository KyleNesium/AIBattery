# Provider-Relevant Display — Design Spec

**Date:** 2026-10-12
**Status:** Approved for planning (user asked for a plan covering all nine items)
**Ships as:** part of the v3.1.0 integration branch (one PR with the multi-account overview and the #196 fix) — see `docs/superpowers/plans/2026-10-12-v3-1-0-release-plan.md`. Item 6 is implemented by the overview plan's Task 1; item 9 is superseded by the overview.

## Goal

Make what the popover and menu bar show *true to the active provider*: read the provider-specific
fields that are already on disk or in the API payloads (context window, reasoning tokens, effort,
limit names, model-specific weekly windows), stop dropping Codex API-key accounts from the menu bar,
give credit budgets the same runway estimate windows have, make the Codex All-Time / 12M split
self-explanatory, and add the one cross-provider element worth having — a strip of the other
accounts' headroom.

Nine items, found by survey on 2026-10-12 (see "Verified ground truth"). Numbering below is used
by the plan.

## Decisions (settled during brainstorming)

| Question | Decision |
|---|---|
| One PR or nine? | One integration branch, one PR, tested locally per task; CI once when ready (project rule: no CI fan-out). |
| Reasoning tokens: Codex-only? | No — Claude's JSONL also splits them (`output_tokens_details.thinking_tokens`). One field, two sources, provider vocabulary "Thinking" (Claude) / "Reasoning" (Codex). |
| Effort indicator: Codex-only? | The field is one `effortLabel: String?` on the entry. Codex fills it from `turn_context.effort`; Claude fills it from `usage.speed` only when it is not `"standard"` (i.e. `"fast"`). Nothing shown when nil. |
| Context window source | Codex: per-record `info.model_context_window` (authoritative). Claude: unchanged (`TokenHealthConfig` table). Upward tier bump stays as the safety net for both. |
| Claude per-model weekly windows | Parse them **only if** the live `/api/oauth/usage` payload carries them (Task 0 verifies, keys only). If absent, the item is dropped from this PR and the spec records the observed key set. |
| Codex API-key accounts in the menu bar | Included. Their number is `StandardRateLimits.peakPercent` (worst of requests/tokens per minute). The fan-out returns a second map for them; nothing is coerced into `RateLimitUsage`. |
| Credit runway | "~N d left" from the **observed pace within the current period**: the fetcher persists the first `(fetchedAt, used)` it saw for the period (reset by `resetsAt` change); rate = Δused / Δt. Shown after ≥ 1 h of observation and Δused > 0; suppressed if the projection lands after `resetsAt`. No assumption about period length. |
| All-Time vs 12M | The ledger records the first-scan date per account. Codex All-Time tooltip and the 12M chart caption both say "since <date>". No data reconciliation attempted. |
| Cross-provider strip | One row under the header, visible only when ≥ 2 eligible accounts **and** the "All accounts in menu bar" toggle is on (that toggle is what funds the fan-out; no new network). Each chip = provider mark + worst percent; click switches account. Design spec "Out of scope" amended accordingly. |
| Privacy | Unchanged: token-count-only JSONL reads; `response_item` never decoded; no message content; `~/.codex` read-only. |
| Cost framing | Unchanged: API-equivalent cost for subscriptions, real bill only for API keys. Reasoning tokens do not change cost (billed as output already). |

## Verified ground truth (inspected on this machine, 2026-10-12)

Codex rollout `~/.codex/sessions/.../rollout-2026-10-11T20-49-34-*.jsonl` (Codex CLI, model `gpt-6-astra`):

- `turn_context.payload` keys: `approval_policy, approvals_reviewer, collaboration_mode, comp_hash, cwd, disabled_plugin_ids, effort, model, multi_agent_version, permission_profile, realtime_active, root_turn_id, sandbox_policy, summary, turn_id`. Observed `effort` values: `xhigh` (10 turns). The app reads only `model`.
- `event_msg` / `token_count.payload.info` keys: `last_token_usage, model_context_window, total_token_usage`. `model_context_window` = **258400** (numeric, every record). The app ignores it and uses `TokenHealthConfig.openAIDefaultContextWindow = 258_400` — equal today, by coincidence.
- `last_token_usage` keys: `cache_write_input_tokens, cached_input_tokens, input_tokens, output_tokens, reasoning_output_tokens, total_tokens`. Session total: output 125 278 of which reasoning **36 226 (29 %)**. The app folds reasoning into output.
- `token_count.payload.rate_limits` keys: `credits, individual_limit, limit_id, limit_name, plan_type, primary, rate_limit_reached_type, secondary, spend_control_reached`. The parser reads `plan_type`, never `limit_name` / `limit_id`.
- `session_meta.payload.context_window` is `{ "window_id": "…" }` — an identifier, **not** a size. Do not read it.

Claude JSONL `~/.claude/projects/.../*.jsonl` (`message.usage` on an assistant line):

- keys: `cache_creation, cache_creation_input_tokens, cache_read_input_tokens, fallback_credit, inference_geo, input_tokens, iterations, output_tokens, output_tokens_details, server_tool_use, service_tier, speed`.
- `output_tokens_details` = `{ "thinking_tokens": 139 }` against `output_tokens` 226 on the sampled line. `speed` = `"standard"`; `service_tier` = `"standard"`. The app decodes `service_tier` and drops the rest.

Claude `/api/oauth/usage` (captured 2026-10-20, live Claude Team account): top-level keys `amber_cistern, amber_gauge, amber_ladder, brass_thimble, cedar_ember, cinder_cove, copper_kite, extra_usage, five_hour, granite_teacup, harbor_lantern, iguana_necktie, juniper_tide, limits, member_dashboard_available, nimbus_quill, omelette_promotional, seven_day, seven_day_breakdown, seven_day_cowork, seven_day_oauth_apps, seven_day_omelette, seven_day_opus, seven_day_sonnet, spend, starry_waterfall, tangelo, wattle_ember, weekly_scoped_shares`; nested object keys captured for `extra_usage{credits_ever_enabled, currency, daily, decimal_places, disabled_reason, is_enabled, monthly_limit, spend_limit_reached, used_credits, user_disabled, utilization, weekly}`, `five_hour{limit_dollars, locked_reason, remaining_dollars, resets_at, used_dollars, utilization}`, `seven_day{limit_dollars, locked_reason, remaining_dollars, resets_at, used_dollars, utilization}`, `spend{auto_reload, balance, can_purchase_credits, can_toggle, cap, disabled_reason, disclaimer, enabled, limit, percent, severity, used}`. The `seven_day_<model>`-shaped top-level keys (`seven_day_breakdown`, `seven_day_cowork`, `seven_day_oauth_apps`, `seven_day_omelette`, `seven_day_opus`, `seven_day_sonnet`) exist in the schema but were **null** on this account/plan — the capture's nested-object dump (which only descends into keys whose value actually decodes as an object) produced no entry for any of them, so their internal shape (`utilization` / `resets_at` or otherwise) is unconfirmed. `RateLimitUsage.parse(clientDataJSON:)` searches only `five_hour` / `seven_day` (+ `5h` / `7d`) key paths.

App state (code anchors, verified):

- `AssistantUsageEntry` (`AIBattery/Models/SessionEntry.swift:41-53`) has no reasoning, effort or context-window field.
- `TokenHealthMonitor.assess` (`AIBattery/Services/TokenHealthMonitor.swift:113`) is the only caller of `TokenHealthConfig.contextWindow(for:)`.
- `AccountStore.multiAccountDisplayIDs` (`AIBattery/ViewModels/MultiAccountFanOut.swift:63-74`) filters `isAPIKeyAccount` out; `MultiAccountFanOut.resolve` returns `[String: RateLimitUsage]?` only.
- `RateLimitUsage.estimatedTimeToLimit(for:)` (`AIBattery/Models/RateLimitUsage.swift:335-360`) is the windows' burn-rate estimate; `CreditBudgetSection` has no equivalent.
- `TokenLedger.LedgerData` (`AIBattery/Services/TokenLedger.swift:214-225`) stores per-(account, model) high-water token counts and nothing dated.
- `UsagePopoverView.mainContent` (`AIBattery/Views/UsagePopoverView.swift:128-156`): header → settings | metric toggle → bars. Insertion point for the strip: between the header and `MetricToggleView`.

## 1. Context window from Codex records (item 1)

- `AssistantUsageEntry` gains `let contextWindow: Int?` (nil for Claude; Codex: `info.model_context_window` when it is a positive integer).
- `TokenHealthMonitor.assess` uses `latestEntry.contextWindow ?? TokenHealthConfig.contextWindow(for: model)`. The upward tier bump (`[200K, 500K, 1M, 2M, 5M]`) still applies after that, so a record claiming a smaller window than the observed tokens never produces > 100 %.
- `TokenHealthConfig.openAIDefaultContextWindow` stays as the fallback and its doc comment says so.
- `spec/DATA_LAYER.md` CodexSessionLogParser mapping table gains the row; `spec/CONSTANTS.md` "Context Windows" notes the fallback role.

## 2. Reasoning / thinking tokens (item 2)

- `AssistantUsageEntry` gains `let reasoningTokens: Int` — a **subset** of `outputTokens`, never added to totals.
  - Claude: `SessionEntry.TokenUsage` decodes `output_tokens_details.thinking_tokens` (nested `OutputTokensDetails: Codable { thinkingTokens: Int? }`, key `thinking_tokens`). Missing → 0.
  - Codex: `last_token_usage.reasoning_output_tokens`. Missing → 0. Clamped to `min(reasoning, output)`.
- `UsageAggregator.TokenMap` value gains `reasoning: Int`; both `accumulate` overloads add it; `buildModelTokens` passes it; `ModelTokenSummary` gains `let reasoningTokens: Int` and `var reasoningShare: Double?` (= reasoning / output, nil when output == 0).
- `TokenLedger.ModelTokenRecord` gains `reasoning: Int` (`decodeIfPresent`, default 0) merged by max like the others, so All-Time and the Insights rows agree.
- `TokenHealthStatus` gains `let reasoningTokens: Int` (session sum) and `var reasoningShare: Double?`.
- UI:
  - Context detail row: when `reasoningShare != nil && reasoningTokens > 0`, the trailing text becomes `"\(turnCount) turns · \(modelDisplay) · \(Int(share*100))% \(vocab)"` where vocab is `"thinking"` for `claude-` models and `"reasoning"` for `gpt-` models (`ReasoningVocabulary.label(forModel:)`, pure, tested). Help text: "Share of this session's output tokens spent on <vocab>".
  - Insights model rows: the copy text and accessibility label gain `· 29% reasoning` when the share is non-nil; the visible row does not change width (tooltip only), to keep the 275 pt layout.
- No cost change. `spec/DATA_LAYER.md` (`AssistantUsageEntry`, `ModelTokenSummary`, `TokenHealthStatus`, `TokenLedger`), `spec/UI_SPEC.md` (Context row, Insights rows).

## 3. Effort / speed label (item 3)

- `AssistantUsageEntry` gains `let effortLabel: String?`.
  - Codex: `turn_context.effort` (lower-cased, trimmed, max 8 chars), carried on every entry after it like `currentModel`.
  - Claude: `usage.speed` when present and ≠ `"standard"` (→ `"fast"`). `SessionEntry.TokenUsage` decodes `speed`.
- `TokenHealthStatus` gains `let effortLabel: String?` from the latest entry.
- Context detail row: model display becomes `"\(modelDisplay) · \(effortLabel)"` when non-nil (so a Codex row reads `GPT-6 Astra · xhigh`, a Claude fast-mode row `Opus 5 · fast`). Help: "Reasoning effort configured for this session" (Codex) / "Fast mode" (Claude). Pure formatter `TokenHealthSection.modelEffortText(model:effort:)`, tested.
  - Implementation note: this formatter was folded into the single trailing-text builder for the detail row (item 2's reasoning-share text and item 3's effort label share one surface), so the shipped code names it `TokenHealthSection.detailTrailingText(turnCount:model:effort:reasoningShare:reasoningTokens:)` rather than a standalone `modelEffortText(model:effort:)`.

## 4. Limit name on the Codex credits bar (item 4)

- `CodexCreditBudget` gains `var limitName: String? = nil` (optional so persisted blobs decode).
- `CodexUsageParser.parseCreditBudget` reads `dict["limit_name"] as? String` (top-level of the `rate_limits` / usage dict, as observed) and sets it.
- `CreditBudgetSection.headerTooltip` prefers `"Plan: \(limitName)"` over `planType`, falling back to `planType`.

## 5. Claude model-specific weekly windows (item 5) — conditional

- **Task 0 (verification, before any code):** capture the top-level key set of a live `/api/oauth/usage` response. Method: temporary `AppLogger.network.notice("usage endpoint keys: …")` of `Array(dict.keys).sorted()` in `RateLimitFetcher+UsageEndpoint.interpretUsageEndpoint` (keys only, no values), run the local build once, read with `log show --last 10m --predicate 'subsystem == "com.KyleNesium.AIBattery"'`, then revert the log line. Record the key set in this spec under "Verified ground truth". **Result: absent** — the schema has `seven_day_opus` / `seven_day_sonnet` (and four sibling `seven_day_<something>` keys) at the top level, but all of them were `null` in the captured live payload, so no nested object with `utilization` and `resets_at` was observed for any of them. Task 6 is DROPPED; per-model weekly windows cannot be verified from this account's data. Re-run Task 0's capture against an account where these fields are populated if this is revisited later.
- **If** keys like `seven_day_opus` / `seven_day_sonnet` (any `seven_day_<model>` object with `utilization` and `resets_at`) are present:
  - `RateLimitUsage` gains `let modelWindows: [ModelWindow]` (`struct ModelWindow: Codable, Equatable, Sendable { let model: String; let utilization: Double; let reset: Date?; let status: String }`), `decodeIfPresent` default `[]`, parsed from every top-level key matching `^seven_day_(.+)$`.
  - Popover: under the 7-Day bar (windows kind, Claude only), one compact row per model window: `"\(ModelNameMapper.displayName(for: model)) weekly  \(percent)%  · resets \(compact)"`, `Typography.tinyLabel`, no bar. Rendered by `ModelWindowRows(windows:now:)`, hidden when empty.
  - Menu bar / notifications / spike filter: untouched (the 7-Day bar stays the headline number).
- **If absent:** no code; the spec's ground-truth section records the observed keys and the item closes.

## 6. Codex API-key accounts in the menu bar (item 6)

> **Implemented by the multi-account overview** (`2026-10-12-multi-account-overview-design.md` §2.2 / §7, plan Task 1): the fan-out returns `AccountReading` (windows | apiLimits), API-key accounts become eligible, and the menu bar renders per-minute slots. The text below is kept as the original requirement; the overview's data model supersedes `FanOutResult`.

- `MultiAccountFanOut.resolve` returns `FanOutResult { windows: [String: RateLimitUsage]; apiLimits: [String: StandardRateLimits] }?`. For an account whose `APIFetchResult.standardLimits` is non-nil and `rateLimits` is nil, the entry goes to `apiLimits`.
- `AccountStore.multiAccountDisplayIDs` stops filtering `isAPIKeyAccount`.
- `UsageViewModel` gains `@Published var perAccountAPILimits: [String: StandardRateLimits]`, filled next to `perAccountRateLimits`.
- `MenuBarMultiAccountText.build(order:providers:limits:apiLimits:metricMode:)` — for an id present in `apiLimits` the percent is `peakPercent` (0–100) regardless of `metricMode`; exhausted when `isRequestsExhausted || isTokensExhausted`; star/broken-star logic sees the same number. Tooltip text for that slot: "per-minute API limit".
- `spec/UI_SPEC.md` menu bar section: remove the exclusion sentence, document the per-minute slot.

## 7. Credit runway (item 7)

- `CodexCreditBudget` gains `var periodAnchor: PeriodAnchor? = nil` (`struct PeriodAnchor: Codable, Equatable, Sendable { let at: Date; let used: Double; let resetsAt: Date? }`).
- `CodexRateLimitFetcher`, on a fresh reading, carries the anchor forward from the cached budget when `cached.periodAnchor?.resetsAt == fresh.resetsAt`; otherwise sets `PeriodAnchor(at: now, used: fresh.used, resetsAt: fresh.resetsAt)`. `rolledOver()` clears it.
- `CodexCreditBudget.estimatedTimeToExhaustion(now:)` (pure): requires `anchor`, `now - anchor.at >= 3600`, `used > anchor.used`, `remaining > 0`; `rate = (used - anchor.used) / (now - anchor.at)`; `eta = remaining / rate`; nil if `resetsAt` exists and `now + eta >= resetsAt`.
- `CreditBudgetSection` footer: `"~\(DurationFormatter.compact(eta)) to limit"` in `ThemeColors.caution` (same gate as windows: `confirmed`), else the existing text. `CreditBalanceRow` unchanged (no period).
- `spec/CONSTANTS.md` "Predictive Rate Limit" gains `creditRunwayMinObservation = 3600 s`.

## 8. All-Time "since" date (item 8)

- `TokenLedger.LedgerData` gains `var firstScan: [String: Date] = [:]` (`decodeIfPresent`); `merge` sets `firstScan[accountId]` on first write for that account. `TokenLedger.firstScanDate(accountId:) -> Date?`.
- `UsageSnapshot` gains `let ledgerSince: Date?` (Codex only; nil for Claude), set by the aggregator from the ledger after merge.
- `InsightsView.allTimeTooltip(for:since:)` appends `" (since \(dateString))"` for Codex when present; the 12M chart gets a caption `"since \(dateString)"` (`Typography.monoTiny`, tertiary) under the chart in `.monthly` mode for Codex snapshots with `ledgerSince` later than 12 months ago.

## 9. Other-accounts strip (item 9) — SUPERSEDED

> Replaced by the multi-account overview (`2026-10-12-multi-account-overview-design.md`): with 2+ accounts the popover opens on one card per account, which is the real version of this strip. Nothing from this section is built. Kept for the record.

- New view `OtherAccountsStrip` inserted in `UsagePopoverView.mainContent` between the header and `MetricToggleView` (not shown with Settings open, not shown for the add-account overlay).
- Pure model `OtherAccountsStrip.rows(accounts:activeId:windows:apiLimits:maskEmail:) -> [Row]` (`struct Row: Identifiable, Equatable { let id: String; let provider: AIProvider; let identity: String; let percent: Double?; let exhausted: Bool }`): every eligible account except the active one, in `displayOrdered` order; percent = `max(fiveHourPercent, sevenDayPercent)` for windows, `budget.usedPercent` for credits, `peakPercent` for API limits, nil when no reading.
- Rendering: `ProviderBadge` (12 pt) + identity (`Typography.tinyLabel`, middle-truncated, max 110 pt) + percent (`Typography.monoTiny`, colour `ThemeColors.barColor(percent:)`; `"—"` when nil). Each chip is a `Button(.plain)` calling `viewModel.switchAccount(to:)`. Help: full identity + "worst window N%". Hidden when fewer than one row or when `showAllAccountsInMenuBar` is off.
- Spec amendments: `docs/superpowers/specs/2026-09-02-codex-support-design.md` "Out of scope" line 2 becomes "Cross-provider **aggregate numbers** (sums across providers). The other-accounts strip (2026-10-12 spec §9) is a navigation aid, not an aggregate."; `spec/UI_SPEC.md` popover hierarchy and ASCII mockup updated.

## 10. Error handling

- Every new JSON field is optional with a safe default; a malformed value never fails the record (same policy as `CodexSessionLogParser` today).
- Persisted blobs (`TokenLedger`, `PersistedCodexRateLimits`, `aibattery_rateLimits_*`) all decode pre-change data: new fields are `decodeIfPresent` with defaults. A round-trip test per model pins it.
- Runway and share computations return nil rather than extreme values on bad input (zero/negative deltas, output == 0).

## 11. Testing

- Swift Testing, `@testable import AIBatteryCore`, pure functions first. Headless-CI rules: `@MainActor` for anything touching AppKit colours; no `UsageViewModel()` in tests; no dynamic `NSColor` equality off-main.
- Per item: parser tests (Claude + Codex fixtures as inline JSON), aggregator tests (reasoning summed, context window carried), monitor tests (per-record window wins, tier bump still applies), ledger round-trip, fan-out tests (API-key account lands in `apiLimits`), menu-bar text tests (per-minute slot), credit-runway tests (anchor carry/reset, gating), strip row-model tests, All-Time tooltip tests.
- README "Test Coverage" table and `CLAUDE.md` counts updated in the wrap-up task.

## Open research items (resolved during implementation, before coding against them)

| # | Item | Resolution method | Fallback if unavailable |
|---|---|---|---|
| R1 | Does `/api/oauth/usage` carry per-model weekly windows? | Task 0 key capture | Drop §5; record keys |
| R2 | Does `spend_control.individual_limit` carry a period length (`limit_window_seconds` / similar)? | Inspect a live `wham/usage` reading (keys only) during Task 7 | §7 as specified (observed-pace method, no period length needed) |
| R3 | Is `reasoning_output_tokens` ever > `output_tokens` in rollouts? | Scan local rollouts (numbers only) during Task 2 | Clamp (already specified) |

## Out of scope

- Aggregate cross-provider numbers (sums of tokens or cost across providers).
- Any new network request; the strip and the menu bar reuse the existing fan-out.
- Reasoning tokens in cost (already billed as output by both providers).
- Writing to `~/.codex` or `~/.claude`.

## Spec/code sync obligations

`spec/ARCHITECTURE.md`, `spec/DATA_LAYER.md`, `spec/UI_SPEC.md`, `spec/CONSTANTS.md`, `README.md` and `CLAUDE.md` are updated in the same PR. No merge with stale docs.

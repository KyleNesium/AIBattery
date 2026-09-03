# Codex (OpenAI) Account Support — Design Spec

**Date:** 2026-09-02
**Status:** Approved design, pre-implementation
**Ships as:** one integration branch → one PR → one release (full parity, no phased releases)

## Goal

AIBattery becomes a two-provider "AI battery": up to 3 Claude (Anthropic) accounts **and** up to 3
Codex (OpenAI/ChatGPT-plan) accounts, side by side, with full feature parity for Codex — menu-bar
percentages, popover rate-limit bars, throttle alerts, and Insights (local session analytics,
per-model tokens, API-equivalent cost).

## Decisions (settled during brainstorming)

| Question | Decision |
|---|---|
| Scope depth | Full parity with Claude (rate limits + local analytics + Insights) |
| Codex auth | In-app OAuth flow (mirror of the Anthropic flow), plus one-click import of `~/.codex/auth.json` as a first-account convenience |
| Mixed-provider UI | Provider glyphs, one flat account list (`✦ 42% | 23%  ⬡ 57%` in the menu bar) |
| Account cap | 3 per provider (3 Claude + 3 Codex max) |
| Release shape | One big release; single integration branch and PR, tested locally before merge |
| Architecture | Approach A: provider seams on the existing architecture — one `AccountStore`, one `UsageViewModel`, one snapshot/UI pipeline; provider dispatch at service boundaries |

## Verified ground truth (inspected on this machine, Codex CLI 0.152.0)

- `~/.codex/auth.json`: `auth_mode`, `OPENAI_API_KEY` (null in ChatGPT mode),
  `tokens.{id_token, access_token, refresh_token, account_id}`, `last_refresh`.
- `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl` line types: `session_meta` (session_id, timestamp,
  cwd, cli_version, context_window, git), `turn_context` (model, e.g. `gpt-5.5`, cwd),
  `event_msg` with `payload.type == "token_count"` carrying:
  - `info.total_token_usage` and `info.last_token_usage` — each with `input_tokens`,
    `cached_input_tokens`, `cache_write_input_tokens`, `output_tokens`, `reasoning_output_tokens`,
    `total_tokens`
  - `rate_limits`: `primary {used_percent, window_minutes: 300, resets_at}` and
    `secondary {used_percent, window_minutes: 10080, resets_at}` (unix seconds), plus `credits`,
    `plan_type`, `rate_limit_reached_type`
- Codex windows are literally 5 hours (300 min) and 7 days (10080 min) — structurally isomorphic to
  Anthropic's unified 5h/7d windows.
- Local volume: 2.5 GB across 106 JSONL files → FileHandle streaming is mandatory, same as
  `SessionLogReader` (never load a full file into memory).

## 1. Provider model & accounts

- New `AIProvider: String, Codable` enum: `.claude`, `.codex`.
- `AccountRecord` gains `var provider: AIProvider` with a **decode default of `.claude`**
  (custom `init(from:)` using `decodeIfPresent`) — existing persisted accounts load unchanged; no
  migration step.
- Account IDs remain strings: Anthropic org ID for Claude; `auth.json`-style `account_id` for
  Codex. The `"pending-<UUID>"` → real-ID resolution flow applies to both providers.
- `AccountStore` stays single. Cap becomes per-provider:
  `maxAccountsPerProvider = 3`, `canAddAccount(provider:)`.
- Display order: store order, with the account picker and menu-bar grouping sorting Claude accounts
  before Codex accounts so glyph groups stay contiguous.

## 2. Auth

- Codex auth is implemented as `CodexAuthSession` + `CodexCallbackServer` (flow), `CodexTokenClient` (exchange/refresh HTTP), and provider routing inside `OAuthManager` (storage keys, refresh dispatch, account registration) — same observable contract: PKCE S256, state validation, Keychain `refreshToken_codex_<accountId>`, identical token-lifecycle policies.
  - PKCE S256 + state validation (CSRF), `Result<Void, AuthError>` from code exchange.
  - Refresh token in Keychain via `OAuthTokenStorage` with provider-scoped keys
    (`refreshToken_codex_<accountId>`); access token memory-only; expiry in UserDefaults.
  - Token lifecycle identical to Anthropic: refresh 5 min before expiry, transient-vs-auth error
    split (network/5xx keep `isAuthenticated`; only auth errors sign out), token-endpoint 5xx
    retried ×2 with backoff, concurrent refreshes serialized via a shared task.
- Flow replicates Codex CLI's login: browser auth against OpenAI's auth server with a localhost
  callback on the CLI's fixed port. Exact client-id, port, scopes, and token endpoint are lifted
  verbatim from the open-source `codex-rs` login code during implementation (Research item R1) —
  never guessed.
- Shared scaffolding (PKCE generation, base64url, token POST plumbing) is extracted from
  `OAuthManager` into a shared helper used by both clients — no duplication.
- Convenience: **"Import current Codex CLI login"** reads `~/.codex/auth.json` to seed the first
  Codex account. Import is one-time seeding: AIBattery refreshes independently afterwards; if the
  CLI's own rotation invalidates the imported token, the standard auth-failure → re-login path
  fires.

## 3. Rate limits

- `RateLimitUsage` is generalized **minimally, not renamed**: keeps `fiveHour*` / `sevenDay*`
  storage fields (accurate for both providers today) and gains:
  - optional per-window `windowMinutes` (data-driven from Codex payloads; defaulted to 300/10080
    when absent),
  - a provider tag so labels render "5-hour / 7-day" for Claude and "5h / Weekly" for Codex.
- All existing hardening carries over untouched: `markedThrottled` 429 normalization,
  rollover-artifact guard (0.95 / 600 s), and the v2.6.1 time-based spike confirmation.
- `RateLimitFetching` (the protocol seam `MultiAccountFanOut` already uses) becomes the dispatch
  point. A provider-dispatching implementation routes Claude accounts to `RateLimitFetcher` and
  Codex accounts to the new `CodexRateLimitFetcher`.
- `CodexRateLimitFetcher` sources, in order:
  1. **Network**: the ChatGPT backend usage endpoint (Bearer access token + account-id header) —
     exact route and headers verified against `codex-rs` / CodexBar source (Research item R2).
     Required for polling accounts the CLI isn't actively using.
  2. **Session-log fallback**: freshest `token_count.rate_limits` snapshot streamed from
     `~/.codex/sessions`, surfaced with the `isCached` semantics so the freshness gate suppresses
     alarms exactly as for stale Anthropic data.
  Codex `rate_limit_reached_type` / HTTP 429 map onto the existing `markedThrottled` path.
- `MultiAccountFanOut.resolve` is already provider-agnostic (IDs + injected fetcher); it receives
  the dispatching fetcher and needs no structural change.
- Menu bar: `MenuBarMultiAccountText` gains provider grouping — glyph-prefixed groups
  (`✦ 42% | 23%  ⬡ 57%`), non-breaking-space rules preserved; worst-account-drives-icon logic
  unchanged across both providers.

## 4. Local data layer (Insights parity)

- New `CodexSessionLogReader`, sibling of `SessionLogReader`, same discipline: FileHandle
  streaming, fingerprint-only per-file cache (modDate + fileSize) with raw arrays released after
  merge, trailing-partial-line skip, 1 MB leftover-buffer cap, dirty-cycle reparse of changed files
  only.
- Parsing model: `session_meta` → session identity, cwd (project attribution), timestamp;
  `turn_context` → current model for subsequent turns; `token_count` → **`last_token_usage` per
  turn** (never cumulative `total_token_usage`, avoiding the double-counting hazard class solved
  for stats-cache).
- Output: the existing `AssistantUsageEntry` — no new entry type — so **`UsageAggregator` runs
  unchanged** on either provider's entries. Field mapping (verified against a live sample where
  `total = input + output`, cached ⊂ input, reasoning ⊂ output):

  | `AssistantUsageEntry` | Codex source |
  |---|---|
  | `inputTokens` | `last_token_usage.input_tokens − cached_input_tokens` (fresh input only) |
  | `cacheReadTokens` | `last_token_usage.cached_input_tokens` |
  | `cacheWriteTokens` | `last_token_usage.cache_write_input_tokens` |
  | `outputTokens` | `last_token_usage.output_tokens` (reasoning tokens are a subset, already included) |
  | `model` | most recent `turn_context.model` |
  | `sessionId` / `cwd` / `gitBranch` | `session_meta` payload |
  | `timestamp` | the `token_count` line's timestamp |
  | `messageId` | synthesized `<session_id>-<event index>` (uniqueness only; no Codex stats-cache dedup needed) |
  | `toolCallCount` | `0` in v1 — tool-call counting would require parsing `response_item` lines, which are skipped for privacy; tool-call stats hide for Codex |
- `CodexPaths` sibling of `ClaudePaths` (`~/.codex/sessions`). `FileWatcher` gains a second
  FSEvents root; local-only refresh triggers work identically for Codex activity.
- No Codex stats-cache exists → Codex all-time/12-month insights derive purely from session JSONL
  and are bounded by session-file retention. The UI states this honestly (mirrors the documented
  Claude Insights data-source split caveat).
- Cost: new OpenAI pricing table in `ModelPricing` (`gpt-*` models); presentation keeps the
  **"API-equivalent cost"** framing — subscription value delivered, never a bill.
  `ModelNameMapper` learns `gpt-*` display names.
- Claude-only stats with no Codex source (stats-cache-derived lifetime aggregates) hide gracefully
  when the active provider is Codex.
- The popover reflects the **active account's provider** end-to-end: switching to a Codex account
  swaps bars, insights, charts, and costs to Codex-sourced data. Local logs are machine-wide per
  provider (same semantics as today's Claude behavior with multiple accounts).

## 5. UI

- Account picker rows show a provider glyph (✦ Claude, ⬡ Codex); "Add Account…" splits into
  "Claude account…" / "Codex account…" respecting per-provider caps.
- `AuthView` parameterized by provider (title, glyph, start-flow callback); Codex adds the
  "Import current CLI login" affordance when `~/.codex/auth.json` exists.
- Menu bar per §3. Settings unchanged except cap wording ("up to 3 accounts per provider").
- Status feed: Codex accounts use OpenAI's status feed as the `status.claude` equivalent **if** a
  clean public JSON exists (Research item R3); otherwise v1 keeps the status section Claude-only —
  non-blocking either way.

## 6. Error handling

- Existing per-account policies extend by provider, never cross it: an auth failure signs out that
  account only; provider outages don't interact.
- Codex fetch degradation chain: network endpoint → session-log snapshot → held stale cache with
  alarm suppression (`rateLimitsFresh == false` semantics).
- StatusChecker-style exponential backoff applies to the Codex endpoint (60 s → 120 s → 240 s, cap
  5 min, jitter) — no immediate retries.
- Token values never logged, for either provider; JSONL reads remain token-count-only (no message
  content parsed, stored, or displayed — `response_item` lines are skipped entirely).

## 7. Testing

- Pure interpreters unit-tested directly, mirroring `interpretUsageEndpoint`:
  `CodexRateLimitFetcher.interpret*` (status codes, 429 normalization, payload parsing),
  Codex JSONL line parsing + the `AssistantUsageEntry` field mapping against fixture lines lifted
  from real session files (redacted),
  `RateLimitUsage` window-labeling and `windowMinutes` handling.
- `MultiAccountFanOut` mixed-provider fan-out via the existing protocol mocks.
- `AccountStore`: per-provider cap, decode-default migration, provider-grouped ordering.
- `MenuBarMultiAccountText`: glyph grouping, worst-percent across providers, throttle detection.
- README Test Coverage section updated in the same commit as every test change.
- Headless-CI rules respected: no dynamic NSColor equality off-main; no
  `SparkleUpdateService.shared` touch from new tests.

## 8. Open research items (resolved during implementation, before coding against them)

| # | Item | Resolution method | Fallback if unavailable |
|---|---|---|---|
| R1 | OpenAI OAuth parameters (client-id, localhost port, scopes, token endpoint) | Read `codex-rs` login source | None needed — flow is known to exist (CLI uses it) |
| R2 | ChatGPT backend usage endpoint route + headers | Read `codex-rs` / CodexBar source | Session-log `rate_limits` snapshots ship regardless |
| R3 | OpenAI public status JSON | Check status.openai.com API | Status section stays Claude-only in v1 |

## Out of scope

- Providers beyond Claude and Codex (no plugin registry — exactly two providers, dispatched by enum).
- Codex "credits" balance display (`credits` field parsed but not surfaced in v1).
- Cross-provider combined/aggregate views (each account renders its own provider's data).
- Writing to any `~/.codex` file (read-only, same as `~/.claude`).

## Spec/code sync obligations

Per the project workflow: `spec/ARCHITECTURE.md`, `spec/DATA_LAYER.md`, `spec/UI_SPEC.md`,
`spec/CONSTANTS.md`, and `README.md` are updated to reflect all of the above **in the same
integration PR** — no merge with stale docs.

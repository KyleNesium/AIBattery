# TODOs

## Rate limit & depletion display

- [x] ~~**`LocalUsageEstimate.calibrate()` is too sensitive at the band edges.**~~
  Fixed: calibration band narrowed from `0.05–0.95` to `0.20–0.80`
  (`LocalUsageEstimate.calibrationBand`), so dividing by a tiny utilization can no
  longer magnify measurement error into a false ≥100% local reading.

- [x] ~~**`UsageAggregator.sevenDaysAgo` uses calendar-day arithmetic** for the 7d
  rate-limit count.~~ Fixed: split into `sevenDayRateLimitCutoff` (rolling
  7×86400, used for `sevenDayTokens`) and `sevenDaysAgo` (calendar-day, retained
  for `weekTokenMap` UI breakdown where calendar semantics are correct).

- [x] ~~**Menu-bar exhaustion glyph is identical for 5h and 7d.**~~ Fixed via text
  rather than a glyph: the throttled menu-bar countdown is prefixed with the binding
  window code (`5H` / `7D`), e.g. `5H 2h 5m`, so users can tell whether to wait hours
  or a day+ without opening the popover.

- [x] ~~**No telemetry / structured log when `isExhausted` flips on or off.**~~
  Fixed: `UsageViewModel.recordThrottleEvent(_:source:)` emits one
  `AppLogger.network` line on each throttle on/off transition (binding window,
  reset timestamp, source: `api-fresh` / `stale-cache`).

- [x] ~~**`RateLimitUsage.withClearedExpiredWindows` is a no-op when reset dates are
  nil.**~~ Fixed: a window with status `"throttled"` and no reset is now treated as
  an unbounded throttle and its flag is dropped (utilization kept) on the
  cache / stale-fallback path, so a reset-less throttle can no longer stick.

## Codex (deferred from the v3.0.0 pre-release review, 2026-10-10)

- [ ] **Per-account attribution of Codex local data.** Every Codex account shows
  the same Insights / Projects / Context Health because `~/.codex/sessions` is
  scanned provider-wide. Real rollouts carry `session_meta.payload.creator_account_id`
  (observed live, Codex CLI 0.160.1) — the same ChatGPT account id used as the
  app's Codex account id. Plan: parse it in `CodexSessionLogParser`, stamp it on
  `AssistantUsageEntry` (new optional field, nil for Claude), and let
  `UsageAggregator` filter by the active account when ≥ 2 Codex accounts exist.
  Would also make `costIsBilled` exact (today: `AccountStore.billsLocalCodexCosts`
  heuristic) and let the session-log rate-limit fallback work with 2+ ChatGPT
  accounts. Needs an API-key rollout fixture to confirm what that mode writes.
- [ ] **`CodexCallbackServer`: accumulate the request line across TCP segments.**
  A single `receive` is parsed as the whole head; a fragmented localhost redirect
  (not observed) would 404 and leave sign-in waiting until the 180 s timeout.
  Accumulate until the first CRLF under the existing 16 KB cap.
- [ ] **`startCodexAuthFlow` should await the listener's `.ready` / `.failed`**
  before returning the authorize URL. `NWListener` reports `EADDRINUSE`
  asynchronously, so today the browser opens and the "port 1455 busy" copy is
  never shown — the flow fails fast through the one-shot failure path with the
  generic "listener failed" message instead.

## Deferred from the third pre-release review (2026-10-10)

Verified against the source and judged not worth changing on the release branch.
Each says why, so a future session doesn't re-litigate it.

- [ ] **`CodexUsageParser` can infer "uncapped" from a partial payload.** A 200
  body carrying `plan_type` but no `rate_limit` at all (schema change, account
  mid-migration, truncated-but-valid JSON) parses to `uncapped: true,
  usedPercent: 0`, is accepted as `.success`, cached and persisted — flipping a
  Plus/Pro popover from 5h/Weekly bars to a single "Credits — no cap" bar at 0%.
  There is no "did this plan previously report windows?" sanity check. Needs a
  product call on whether an uncapped budget should ever be inferred without an
  explicit `spend_control`, so it is not a mechanical fix.
- [ ] **`used_percent` as a JSON string silently reads as 0%.** The window path
  accepts only `Int`/`Double`; a string-encoded value returns nil and `assemble`
  maps that to `utilization 0, status "allowed"`. The credit path two functions
  away already tolerates string-encoded numbers. Not observed from OpenAI — the
  fix is to reuse the credit path's `number(_:)` helper for `used_percent` and
  the reset fields.
- [ ] **CLI import derives the account id from `tokens.account_id`, the OAuth
  flow from the `chatgpt_account_id` id_token claim.** If those ever diverge
  (workspace-scoped logins are the obvious candidate) the same real account
  lands twice — burning a cap slot, duplicating Keychain items, and sending a
  header the endpoint may reject. `isPlausibleAccountId` now validates the
  shape, not the source. Prefer deriving from the imported `id_token` with the
  file's field as fallback.
- [ ] **`CodexCallbackServer` has no per-connection timeout.** `receive` has no
  deadline, so a local process that connects to 127.0.0.1:1455 and sends
  nothing holds an `NWConnection` until the 180 s session timeout. Loopback-only
  and time-bounded; arm a `queue.asyncAfter` cancel per connection. Related to
  the already-deferred request-line accumulation item above.
- [ ] **The session-log fallback has no maximum age.** Its windows are cleared
  once their own reset passes, but the same stale line is re-read and re-served
  every cycle, so a week-old reading can be the displayed value for a whole
  endpoint outage. It is marked `isCached: true`, so alarms stay suppressed.
  Consider refusing the fallback past a maximum `asOf` age.
- [ ] **A persisted `7d` metric mode orders the Credits / API-Limits bar second
  on a Codex credit account.** `UsagePopoverView` renders `EmptyView()` for
  `.sevenDay` when the kind collapses while `MetricToggleView` keeps the stored
  selection highlighted. All sections still render (only the order shifts).
  Normalise `metricModeRaw` to `.fiveHour` when the active account's kind
  collapses.
- [ ] **No test coverage of the Codex OAuth completion flow.** Nothing exercises
  `completeCodexAuthFlow` (including the CSRF state-mismatch guard), the
  `registerCodexAccount` cap guard, or `registerCodexAPIKey`'s malformed-key and
  cap guards — only the pure helpers extracted from that file are tested. Needs
  a stubbable `AccountStore`/`storeTokens` seam, which is a refactor rather than
  a test addition.
- [ ] **Small cleanups:** `PopoverHeaderView.planLabel` is a forwarder with no
  production caller (only a test); `CodexAccessMode.chatgpt` is never
  constructed (nil means ChatGPT on persisted records); `CodexUsageParser`'s
  `parseUsageResponse`/`planType` are now test-only wrappers around the one-pass
  `parseUsage`; the 1-hour fallback token expiry (`3_600`) is duplicated between
  the Claude and Codex refresh paths and absent from `spec/CONSTANTS.md`.

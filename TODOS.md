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

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

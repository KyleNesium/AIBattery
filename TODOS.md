# TODOs

## Rate limit & depletion display

- [ ] **`LocalUsageEstimate.calibrate()` is too sensitive at the band edges.**
  `derived = localTokens / utilization` with the gate `0.05 ≤ utilization ≤ 0.95`.
  At the 5% edge, a 1% measurement error → ~20% error in the calibrated limit.
  Result: when the API drops unified headers and we fall back to local estimation,
  `sevenDayPercent` can read ≥100% when the API would say well under 100%. Options:
  weighted moving average across recent calibrations, narrow the gate to 0.20–0.80,
  or require N samples before treating the derived limit as authoritative.

- [x] ~~**`UsageAggregator.sevenDaysAgo` uses calendar-day arithmetic** for the 7d
  rate-limit count.~~ Fixed: split into `sevenDayRateLimitCutoff` (rolling
  7×86400, used for `sevenDayTokens`) and `sevenDaysAgo` (calendar-day, retained
  for `weekTokenMap` UI breakdown where calendar semantics are correct).

- [ ] **Menu-bar exhaustion glyph is identical for 5h and 7d.**
  No way to tell from the menu bar alone whether to wait hours (5h) or a day+ (7d).
  Distinct tint or a small annotation glyph (e.g. clock vs. calendar) on the broken
  star would let users plan without opening the popover.

- [ ] **No telemetry / structured log when `isExhausted` flips on or off.**
  Post-hoc investigation of "the bar was stuck depleted" needs grepping multiple
  unrelated `AppLogger` lines. Single info-level event with the binding window,
  reset timestamp, and whether the source was API-fresh / API-stale / local
  estimate would make these reports trivially diagnosable.

- [ ] **`RateLimitUsage.withClearedExpiredWindows` is a no-op when reset dates are
  nil** (returns `self` for `fiveHourReset == nil && sevenDayReset == nil`).
  If a fetch ever lands "throttled" + 100% utilization with no parseable reset
  timestamp, the in-memory cache will hold that throttle indefinitely. Either
  treat throttle-without-reset as expired after the longer of the two window
  durations, or refuse to cache it in the first place.

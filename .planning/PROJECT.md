# AIBattery

## What This Is

macOS menu bar app that shows Claude API usage at a glance — rate limits, token consumption, cost estimates, session activity, and context health. Built with Swift/SwiftUI, distributed via Homebrew and direct download with Sparkle auto-update. For Claude API users who want visibility into their usage without leaving the menu bar.

## Core Value

Show Claude API usage clearly and instantly from the menu bar — the user glances, gets the answer, and moves on.

## Requirements

### Validated

<!-- Shipped and confirmed valuable. -->

- ✓ AUTH-01: OAuth authentication with PKCE — v1.0
- ✓ AUTH-02: Multi-account support (up to 3) — v1.8
- ✓ AUTH-03: Secure token storage (Keychain refresh, memory-only access) — v1.5.3
- ✓ AUTH-04: Token refresh with transient error resilience — v1.5
- ✓ USAGE-01: Real-time rate limit display (5h + 7d windows) — v1.0
- ✓ USAGE-02: Token consumption from JSONL session logs — v1.2
- ✓ USAGE-03: API-equivalent cost calculation — v1.3
- ✓ USAGE-04: Context health monitoring with auto-detect tiers — v1.4
- ✓ USAGE-05: Activity section (messages, sessions, tool calls) — v1.9
- ✓ USAGE-06: Burn rate and time-to-limit projections — v1.9
- ✓ USAGE-07: Subagent JSONL discovery — v1.9.2
- ✓ UI-01: Menu bar icon with usage band coloring — v1.0
- ✓ UI-02: Popover panel with sections (rate limits, tokens, health, activity) — v1.0
- ✓ UI-03: Adaptive polling (extends interval during idle) — v1.6
- ✓ UI-04: Inline error display with retry — v1.9.2
- ✓ NOTIF-01: System notifications for API outages — v1.4
- ✓ NOTIF-02: Throttle countdown and breathing animation — v1.9
- ✓ UPDATE-01: Sparkle auto-update with EdDSA signing — v1.5
- ✓ UPDATE-02: Version badge from GitHub API — v1.3
- ✓ PERF-01: Fingerprint-based aggregation skip — v1.5.5
- ✓ PERF-02: Byte-search + LRU cache in SessionLogReader — v1.5.5
- ✓ PERF-03: Cached rate limits for instant launch — v1.9.2
- ✓ PERF-04: Recursive JSONL enumerator (469→215 syscalls) — v1.9.2

- ✓ BUG-01: Dynamic probe model list — v1.10
- ✓ BUG-02: Bidirectional context window detect — v1.10
- ✓ BUG-03: Sub-50% time-to-limit projections — v1.10
- ✓ BUG-04: JSONL-based tool call counts — v1.10
- ✓ BUG-05: Spec drift fixes — v1.10
- ✓ PERF-05: Batched TokenLedger disk writes — v1.10 (verified + tests)
- ✓ PERF-06: Efficient buildProjectTokens iteration — v1.10 (verified + tests)
- ✓ PERF-07: Smarter rate limit probe fallback — v1.10
- ✓ PERF-08: Resilient adaptive polling — v1.10
- ✓ PERF-09: Robust JSONL file discovery — v1.10
- ✓ DS-01: Typography constants — v1.11
- ✓ DS-02: Spacing constants — v1.11
- ✓ DS-03: Consistent outer padding — v1.11
- ✓ UI-05: Minimum font size audit — v1.11
- ✓ UI-06: Section visual consistency — v1.11
- ✓ UI-07: Subtle transition animations (performance-gated) — v1.11
- ✓ CQ-01: Extract large view files (<400 lines each) — v1.11
- ✓ CQ-02: Spec sync for structural changes — v1.11
- ✓ PG-01: No animation when panel closed — v1.11
- ✓ PERF-10: Popover opens/closes instantly — v1.12
- ✓ PERF-11: Periodic updates gated on panel visibility — v1.12
- ✓ PERF-12: Reduced GeometryReader layout passes — v1.12
- ✓ CQ-03: Dead code removed (sectionPadding, PopoverLoadingView) — v1.12
- ✓ CQ-04: Spec sync for performance changes — v1.12
- ✓ CQ-05: README test coverage updated — v1.12
- ✓ RESP-01: Popover opens/closes in under 50ms — v1.13
- ✓ RESP-02: No UI freeze or hang during normal usage — v1.13
- ✓ RESP-03: Panel toggle never desyncs — v1.13
- ✓ RESP-04: Lazy-load heavy sections on open — v1.13

- ✓ DATA-01: 24H chart shows data on cold start (dailyActivity loading signal) — v1.14
- ✓ CHART-02: 24H axis labels evenly spaced in HH:00 format — v1.14
- ✓ CHART-01: 12M axis labels use quarterly stride (no overlap) — v1.14
- ✓ LAYOUT-01: Rate limit sections have equal vertical padding — v1.14

### Active

<!-- Current scope. Building toward these. -->

- ✓ PERF-13: Breath timer gated on panel visibility — v1.15
- ✓ PERF-14: Idle/lock detection suspends all timers — v1.15
- ✓ PERF-15: Breath animation removed entirely (zero CPU wakeups for icon) — v1.9.9
- ✓ CRASH-01: Use-after-free from concurrent aggregation (NSLock + task serialization) — v1.9.9

- [ ] SCAN-01: Aggregation <100ms — Phase 17 ✓
- [ ] SCAN-02: Only changed files re-parsed — Phase 17 ✓
- [ ] SCAN-03: Directory mod-date skip — Phase 17 ✓
- [ ] MEM-01: RSS under 100 MB — Phase 18 ✓
- [ ] MEM-02: Inactive session entries evicted — Phase 18 ✓
- [ ] CPU-01: CPU <2% at idle — Phase 19 ✓ (measured 0.0%)
- [ ] CPU-02: CPU <5% during polling — Phase 19 ✓ (measured 0.0-0.1%)

### Out of Scope

- App Store distribution — sandbox, entitlements, Apple Developer cert ($99/yr) all blockers
- Message content parsing — security/privacy boundary; JSONL reads are token-count-only
- iOS/watchOS companion — macOS menu bar is the core form factor

## Context

- **Version:** v1.9.9 (2026-03-25) — v1.15 shipped, v1.16 starting
- **Tests:** 756 across 52 files
- **CI:** GitHub Actions on macos-15 (build → test → bundle)
- **Distribution:** Homebrew cask + GitHub Releases + Sparkle appcast
- **Spec-driven:** `spec/` folder is source of truth (ARCHITECTURE, DATA_LAYER, UI_SPEC, CONSTANTS)
- **Critical bug:** 83% CPU at idle — SessionLogReader scanning 3,103 JSONL files (2 GB) on every polling cycle; aggregation takes entire CPU core continuously

## Constraints

- **Platform:** macOS 13+ only, SwiftUI + AppKit hybrid (menu bar)
- **Signing:** Ad-hoc codesign (no Apple Developer cert) — 1 Keychain prompt per account on Sparkle update
- **API:** Only `/v1/messages` returns rate limit headers — `count_tokens` does not
- **JSONL:** Must stream via FileHandle (never load full file into memory)
- **Dependencies:** Sparkle 2 (SPM) + Apple frameworks only — minimal dependency surface

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Spec-driven workflow | Single source of truth prevents drift | ✓ Good |
| Ad-hoc codesign | Avoids $99/yr Apple cert, accepts Keychain prompt tradeoff | ✓ Good |
| Memory-only access token | Reduces Keychain surface, refresh token is sufficient | ✓ Good |
| Unified rate limit headers | Anthropic uses `anthropic-ratelimit-unified-*` format | ✓ Good |
| All-time token mode only | Windowed mode removed — simpler, always accurate | ✓ Good |
| UNUserNotificationCenter | Native notifications with app icon, no shell escaping risk | ✓ Good |
| Dynamic probe model list | Self-heals from JSONL-observed models instead of hardcoded list | ✓ Good |
| max() merge for tool calls | JSONL supplements stale stats-cache; neither source is authoritative alone | ✓ Good |
| 60s discovery TTL | Catches new JSONL files even when dir mtime unchanged; low cost fallback | ✓ Good |
| Design token system | Typography/Spacing/Layout enums centralize all UI constants — single source of truth | ✓ Good |
| Extension-based extraction | ActivityChartView uses extensions to share @State without Binding plumbing | ✓ Good |
| StyledDivider component | Unified divider styling across all sections (opacity 0.3, tight padding) | ✓ Good |
| MotionConstants enum | Animation durations centralized (standard 0.2s, snappy 0.15s) | ✓ Good |
| PanelToggleState value type | Testable state machine prevents toggle desync structurally | ✓ Good |
| orderOut override with onDismiss | Single dismiss sync point catches all 5 paths | ✓ Good |
| Deferred rendering via async hop | DispatchQueue.main.async defers heavy sections one run-loop | ✓ Good |
| dailyActivity as loading signal | isEmpty checks daily records before declaring hourly empty — prevents false "No activity" on cold start | ✓ Good |
| stride(by: .month, count: 3) for 12M | Let Swift Charts handle quarterly label placement — simpler than manual quarterlyLabelDates | ✓ Good |
| "Context" not "Context Health" | Shorter header fits one line with session toggle + refresh + badge | ✓ Good |

---
## Milestone History

- **v1.16 JSONL Performance** — started 2026-03-25
- **v1.15 Performance** — shipped 2026-03-25 (Phases 15-16)
- **v1.14 Visual Polish** — shipped 2026-03-24 (Phases 13-14)
- **v1.13 Responsiveness** — shipped 2026-03-20 (Phase 12)
- **v1.12 Performance & Cleanup** — shipped 2026-03-19 (Phases 10-11)
- **v1.11 Polish & Consistency** — shipped 2026-03-19 (Phases 6-9)
- **v1.10 Bugs & Performance** — shipped 2026-03-19 (Phases 1-5)
- **v1.0–v1.9.2** — pre-GSD

---
## Current Milestone: v1.16 JSONL Performance

**Goal:** Reduce CPU usage from 83% to <2% at idle — SessionLogReader scans 3,103 files (2 GB) on every polling cycle, consuming an entire CPU core continuously.

**Root cause (profiled):**
- `UsageAggregator.aggregate()` → `SessionLogReader.readAllUsageEntries()` → `cachedRead()` → `readSessionFile()` accounts for 100% of background CPU
- 3,103 JSONL files totaling 2 GB are enumerated and scanned every 10-60s
- `Collection.firstIndex(of:)` byte scanning dominates (854/2371 samples)
- LRU cache (200 entries) is too small for 3,103 files — constant eviction and re-parse
- Memory footprint: 409 MB RSS, 2 GB physical

---
*Last updated: 2026-03-25 after v1.16 JSONL Performance milestone start*

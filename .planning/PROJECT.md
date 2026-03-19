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

### Active

<!-- Current scope. Building toward these. -->

#### Design System
- [x] DS-01: Typography constants — v1.11 Phase 6
- [x] DS-02: Spacing constants — v1.11 Phase 6
- [x] DS-03: Consistent outer padding — v1.11 Phase 6

#### UI Polish
- [x] UI-05: Minimum font size audit — v1.11 Phase 6
- [ ] UI-06: Section visual consistency
- [ ] UI-07: Subtle transition animations (performance-gated)

#### Code Quality
- [ ] CQ-01: Extract large view files (<400 lines each)
- [ ] CQ-02: Spec sync for structural changes

#### Performance Guard
- [ ] PG-01: No animation when panel closed

## Current Milestone: v1.11 Polish & Consistency

**Goal:** Unify typography, spacing, and visual consistency across the popover UI while extracting large files and guarding performance.

### Out of Scope

- App Store distribution — sandbox, entitlements, Apple Developer cert ($99/yr) all blockers
- Message content parsing — security/privacy boundary; JSONL reads are token-count-only
- iOS/watchOS companion — macOS menu bar is the core form factor

## Context

- **Version:** 1.10 (2026-03-19) — bugs & performance milestone shipped
- **Tests:** ~450+ across 34+ files (6 perf regression tests added in v1.10)
- **CI:** GitHub Actions on macos-15 (build → test → bundle)
- **Distribution:** Homebrew cask + GitHub Releases + Sparkle appcast
- **Spec-driven:** `spec/` folder is source of truth (ARCHITECTURE, DATA_LAYER, UI_SPEC, CONSTANTS)
- **Zero TODOs/FIXMEs** in codebase — clean slate
- **Recent focus:** v1.10 shipped all known bugs and performance improvements; specs fully synced

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

---
*Last updated: 2026-03-19 — Phase 6 Design System complete*

# Milestones

## v1.11 Polish & Consistency (Shipped: 2026-03-19)

**Phases completed:** 4 phases, 7 plans, 0 tasks

**Key accomplishments:**

- (none recorded)

---

## v1.10 Bugs & Performance (Shipped: 2026-03-19)

**Phases completed:** 5 phases, 7 plans | **18 files changed, +1076 -43 lines** | **41 commits**

**Key accomplishments:**

- Bidirectional context window tier detection (adjusts down, not just up)
- Dynamic probe model list from JSONL-observed models (self-heals on deprecation)
- JSONL-derived tool call counts with max() merge strategy
- Performance regression tests codifying write batching and aggregation skip
- Probe model persistence on all success paths, adaptive polling no longer thrashes
- 60s TTL discovery fallback for robust JSONL file detection
- Full spec sync across all 4 spec files

---

## v1.0–v1.9.2 (Pre-GSD)

AIBattery developed from v1.0 through v1.9.2 before GSD adoption. Key capabilities shipped:

- OAuth authentication with PKCE + multi-account (up to 3)
- Rate limit monitoring (5h + 7d unified windows)
- Token consumption from JSONL session logs + subagent discovery
- API-equivalent cost calculation with model-specific pricing
- Context health monitoring with auto-detect tiers (200K–5M)
- Activity metrics (messages, sessions, tool calls, burn rate)
- System notifications for outages + throttle countdown
- Sparkle auto-update with EdDSA signing
- Performance: fingerprint skip, LRU cache, byte-search, cached rate limits

**Last phase:** 0 (pre-GSD, no phase numbering)
**Tests:** 434 across 34 files

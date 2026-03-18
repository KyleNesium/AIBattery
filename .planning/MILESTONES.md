# Milestones

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

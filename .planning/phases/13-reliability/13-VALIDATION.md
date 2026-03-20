---
phase: 13
slug: reliability
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-20
---

# Phase 13 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Swift Testing (@testable import AIBatteryCore) |
| **Config file** | Package.swift (AIBatteryCoreTests target) |
| **Quick run command** | `swift test --filter AIBatteryCoreTests` |
| **Full suite command** | `swift test` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `swift test --filter AIBatteryCoreTests`
- **After every plan wave:** Run `swift test`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 13-01-01 | 01 | 1 | REL-01 | unit | `swift test --filter StatusBarToggleTests` | ✅ | ⬜ pending |
| 13-01-02 | 01 | 1 | REL-02 | unit | `swift test --filter StatusBarToggleTests` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

Existing infrastructure covers all phase requirements. StatusBarToggleTests.swift already exists with PanelToggleState tests.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Panel opens on every click | REL-01 | Requires AppKit runtime + menu bar | Click status item 20 times rapidly, verify panel opens/closes each time |
| No UI freeze during interaction | REL-02 | Requires visual observation | Open panel, scroll, collapse/expand sections, verify no hang |
| Rapid toggle stress test | REL-01, REL-02 | Timing-dependent AppKit behavior | Open/close panel 50 times in quick succession, verify no stuck state |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending

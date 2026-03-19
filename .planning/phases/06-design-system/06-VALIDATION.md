---
phase: 6
slug: design-system
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-19
---

# Phase 6 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Swift Testing (@Test, #expect) |
| **Config file** | Package.swift (AIBatteryCoreTests target) |
| **Quick run command** | `swift test --filter AIBatteryCoreTests` |
| **Full suite command** | `swift test` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `swift build` (compile check)
- **After every plan wave:** Run `swift test`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 06-01-01 | 01 | 0 | DS-01 | unit | `swift test --filter TypographyTests` | ❌ W0 | ⬜ pending |
| 06-01-02 | 01 | 0 | DS-02 | unit | `swift test --filter SpacingTests` | ❌ W0 | ⬜ pending |
| 06-01-03 | 01 | 1 | DS-01 | compile | `swift build` | ✅ | ⬜ pending |
| 06-01-04 | 01 | 1 | DS-02 | compile | `swift build` | ✅ | ⬜ pending |
| 06-01-05 | 01 | 2 | DS-03 | grep | `grep -r "padding(.horizontal, 16)" --include="*.swift"` | ✅ | ⬜ pending |
| 06-01-06 | 01 | 2 | UI-05 | grep | `grep -rn "size: 6" --include="*.swift"` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `Tests/AIBatteryCoreTests/Utilities/TypographyTests.swift` — snapshot tests for typography constant values
- [ ] `Tests/AIBatteryCoreTests/Utilities/SpacingTests.swift` — snapshot tests for spacing constant values

*Existing test infrastructure covers compilation and runtime.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Visual font consistency | DS-01 | Font rendering is visual | Launch app, verify all text uses consistent styles |
| Spacing visual alignment | DS-03 | Padding alignment is visual | Launch app, verify sections have uniform outer margins |
| No text below 8pt | UI-05 | Rendered size depends on display | Launch app, inspect all text for readability |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending

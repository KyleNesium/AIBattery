<div align="center">

# ✦ AI Battery

**A battery meter for Claude Code.**

Rate limits, context health, and token usage — always visible in your macOS menu bar.

[![Swift](https://img.shields.io/badge/Swift-5.9-orange?logo=swift&logoColor=white)](https://swift.org)
[![macOS](https://img.shields.io/badge/macOS-13%2B-blue?logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![CI](https://github.com/KyleNesium/AIBattery/actions/workflows/ci.yml/badge.svg)](https://github.com/KyleNesium/AIBattery/actions/workflows/ci.yml)
[![GitHub stars](https://img.shields.io/github/stars/KyleNesium/AIBattery?style=social)](https://github.com/KyleNesium/AIBattery/stargazers)
[![Downloads](https://img.shields.io/github/downloads/KyleNesium/AIBattery/total?logo=github&label=Downloads)](https://github.com/KyleNesium/AIBattery/releases)

<br/>

<img src="screenshots/dashboard.png" width="240" alt="AI Battery dashboard" />

<br/>

<img src="screenshots/demo.gif" width="480" alt="AI Battery demo" />

</div>

---

<details>
<summary><strong>Table of Contents</strong></summary>

- [Install](#-install)
- [Update](#-update)
- [Authentication](#-authentication)
- [How It Works](#-how-it-works)
- [Metrics](#-metrics)
- [Context Health](#-context-health)
- [Settings](#%EF%B8%8F-settings)
- [API Cost](#-api-cost)
- [FAQ](#-faq)
- [Privacy](#-privacy)
- [Architecture](#-architecture)
- [Accessibility](#-accessibility)
- [Uninstall](#-uninstall)
- [Contributing](#-contributing)
- [License](#-license)

</details>

---

## 📦 Install

<table>
<tr>
<td width="30"><img src="https://brew.sh/assets/img/homebrew.svg" width="18" /></td>
<td><strong>Homebrew</strong> (recommended)</td>
</tr>
</table>

```bash
brew tap KyleNesium/tap
brew install --cask aibattery
```

<details>
<summary>⚡ <strong>Quick install</strong> — paste in Terminal</summary>

```bash
curl -sL https://github.com/KyleNesium/AIBattery/releases/latest/download/AIBattery.zip -o /tmp/AIBattery.zip && ditto -x -k /tmp/AIBattery.zip /Applications && xattr -cr /Applications/AIBattery.app && open /Applications/AIBattery.app
```

</details>

<details>
<summary>💿 <strong>DMG download</strong></summary>

Download from [Releases](https://github.com/KyleNesium/AIBattery/releases/latest):

1. Open `AIBattery.dmg` and drag **AI Battery** to **Applications**
2. Launch from Applications — macOS will block it on first run
3. Open **System Settings → Privacy & Security** → scroll down → click **Open Anyway**

> [!TIP]
> If macOS says the app is damaged, run `xattr -cr /Applications/AIBattery.app` then relaunch.

</details>

<details>
<summary>🛠 <strong>Build from source</strong></summary>

```bash
git clone https://github.com/KyleNesium/AIBattery.git && cd AIBattery
./scripts/build-app.sh
open .build/AIBattery.app
```

</details>

Requires **macOS 13+** and [Claude Code](https://docs.anthropic.com/en/docs/claude-code).

---

## 🔄 Update

**Homebrew:**

```bash
brew upgrade --cask aibattery
```

**Or** re-run the quick install command — it overwrites the old version in place.

**Or** download the latest DMG from [Releases](https://github.com/KyleNesium/AIBattery/releases/latest), open it, and drag to Applications — replace when prompted.

> [!NOTE]
> Your settings and OAuth session carry over automatically.

---

## 🔐 Authentication

OAuth 2.0 with PKCE — same protocol as Claude Code. Supports up to **2 accounts** (separate Claude orgs).

| Step | Action |
|:---:|---|
| **1** | Launch AI Battery — the auth screen appears on first run |
| **2** | Click **Authenticate** → browser opens to Anthropic's sign-in |
| **3** | Sign in → copy the authorization code |
| **4** | Paste into AI Battery → done |

To add a second account: click the account dropdown in the header → **Add Account**, or open Settings → **Add Account**.

Switch between accounts by clicking the account dropdown in the header. Each account has its own rate limits, tokens, and identity.

<details>
<summary>🔑 <strong>Session details</strong></summary>

- Sessions auto-refresh with a 5-minute buffer to avoid clock-skew issues
- Temporary server errors retry automatically
- Tokens stored in macOS Keychain per account (separate from Claude Code credentials)
- Error messages are specific — expired codes, invalid codes, server errors, and network errors each get a clear description

</details>

<details>
<summary>🛡 <strong>Why does macOS block the app or ask about Keychain access?</strong></summary>

AI Battery isn't notarized — there's no Apple Developer license behind this project, so macOS treats it as unidentified. Two prompts may appear on first launch:

- **Gatekeeper block** — macOS prevents the app from opening. Fix: **System Settings → Privacy & Security → Open Anyway** (see [Install](#-install))
- **Keychain access** — the app stores OAuth tokens in macOS Keychain (one set per account), Apple's encrypted credential store. This is the safest option — the same place Claude Code, browsers, and every other macOS app stores secrets. Click **Always Allow**.

Both are one-time prompts. Neither will appear again after the first launch.

</details>

---

## 🔋 How It Works

AI Battery makes a minimal API call each refresh cycle to read your rate limit headers. It also reads local JSONL session logs for token counts and context health — **never your message content**.

```
✦ 71%                 ← menu bar: selected metric
```

Click the ✦ icon to open the dashboard:

| Section | What you see |
|---|---|
| 📊 **Rate Limits** | 5-hour burst + 7-day sustained — utilization %, reset countdown, binding indicator, predictive time-to-limit |
| 🧠 **Context Health** | 5 most recent sessions with `< 1/5 >` chevron + swipe navigation |
| 🔤 **Tokens** | Per-model breakdown with input/output/cache read/cache write · optional API cost |
| 📈 **Insights** | Today's stats with trend arrow + projection, all-time stats with busiest day |
| 📉 **Activity** | Sparkline chart — 24H · 7D · 12M toggle |

---

## 📐 Metrics

The segmented toggle picks which metric drives the ✦ icon color:

| Mode | Tracks | Best for |
|---|---|---|
| ⏱ **5-Hour** | Burst rate limit | Knowing when you'll get throttled |
| 📅 **7-Day** | Sustained rate limit | Pacing usage across the week |
| 🧠 **Context** | Session context fullness | Knowing when to start fresh |

Selected metric moves to the top. The other two stay visible below.

---

## 🧠 Context Health

<table>
<tr>
<td width="55%">

Shows your **5 most recent sessions** with context health. Browse with `< 1/5 >` chevrons or swipe left/right. Stale sessions (idle > 30 min) show an amber "Idle" badge.

Each session displays: **project name** · **git branch** · **duration** · **last active time**.

Percentages are relative to the **usable window** — 80% of the model's raw context window. At 100%, Claude Code auto-compacts.

| Color | Range | Meaning |
|---|---|---|
| 🟢 Green | < 60% | Plenty of room |
| 🟠 Orange | 60–80% | Quality may degrade |
| 🔴 Red | > 80% | Start a fresh session |

</td>
<td width="45%" align="center">
<img src="screenshots/context.png" width="280" alt="Context Health view" />
</td>
</tr>
</table>

<details>
<summary>⚠️ <strong>Understanding context warnings</strong></summary>

**Long conversation (15+ turns)** — Nothing is discarded between turns. Your messages, Claude's responses, tool calls, and results all accumulate. After ~15 turns the window is full of old history that Claude still reads every turn — slowing responses, reducing quality, and burning through your token budget on stale context.

**High input:output ratio (20:1+)** — More tokens are going in (file reads, error logs, tool results) than coming out. For example, reading 5 large files dumps thousands of tokens into context that Claude may only reference once. That data stays in the window for the rest of the session, consuming tokens on every subsequent turn and leaving less room for useful work.

**Zero-output session** — Session has multiple turns but no output tokens. May indicate an error loop or stalled conversation.

**Rapid token consumption** — Very short session with high token usage. Large files or long pastes may be filling the context window quickly.

</details>

> [!TIP]
> **When you hit orange or red:**
> 1. Run `/compact` to save a summary to project memory
> 2. Keep key decisions in `CLAUDE.md` — loaded automatically every session
> 3. Start a new terminal in the same directory and pick up where you left off

---

## ⚙️ Settings

<table>
<tr>
<td width="55%">

Click ⚙️ in the header to configure:

| Setting | What it does |
|---|---|
| ➕ **Add Account** | Connect a second Claude account (up to 2) |
| ✏️ **Account names** | Custom label per account (shown in picker + menu bar) |
| 🔄 **Refresh** | Poll interval: 10–60s · ~3 tokens per refresh |
| 🤖 **Models** | Only show models used within period: 1–7 days or All |
| 🎨 **Colorblind** | Blue/cyan/amber/purple palette |
| 💲 **Cost*** | Show equivalent API token rates |
| 🔔 **Alerts** | Notify on Claude.ai / Claude Code outages |
| ⚡ **Rate Limit** | Notify when usage crosses threshold (50–95%) |
| 🚀 **Launch at Login** | Start automatically when you log in |
| 💾 **Export / Import** | Copy/paste settings as JSON via clipboard |

</td>
<td width="45%" align="center">
<img src="screenshots/settings.png" width="280" alt="Settings view" />
</td>
</tr>
</table>

The footer shows a **staleness indicator** and an **update banner** when a new version is available.

> [!TIP]
> Click any stat value (percentages, token counts, costs) to copy it to the clipboard.

---

## 💰 API Cost

Enable in **Settings → Display → Cost*** to see dollar amounts in the Tokens section.

This shows what your token usage **would cost at Anthropic's published API per-token rates** — it's not your actual bill. Pro, Max, and Teams subscribers pay a flat monthly fee, not per-token. The estimate is useful for understanding the value of your usage and comparing the economics of subscription vs. API billing.

Pricing uses Anthropic's published rates for input, output, cache read, and cache write tokens per model.

---

## ❓ FAQ

<details>
<summary><strong>Only rate limits show — tokens, models, and activity are all empty?</strong></summary>

Token usage, context health, and activity stats come from Claude Code's local session logs (`~/.claude/`). These populate after you've used Claude Code for a bit. To kickstart it:

1. Run a few Claude Code sessions from the terminal
2. Run `/stats` inside Claude Code — this generates the stats cache
3. AI Battery refreshes automatically every polling cycle

Rate limits (5-hour / 7-day) always work immediately since they come from the API.

</details>

<details>
<summary><strong>Green ✦ at 0%?</strong></summary>

Credits just reset, or no usage yet — this is normal.

</details>

<details>
<summary><strong>What's "binding"?</strong></summary>

Whichever rate limit window is currently the active constraint. The binding window determines the percentage shown in the menu bar.

</details>

<details>
<summary><strong>What's ⚠️ "throttled"?</strong></summary>

Anthropic is actively limiting your requests. Wait for the reset timer.

</details>

---

## 🔒 Privacy

| | |
|---|---|
| 📂 **Local data** | Reads JSONL for token counts only — **never your message content** |
| 🌐 **Network calls** | `api.anthropic.com` (rate limits) · `console.anthropic.com` (OAuth) · `status.claude.com` (status) · `api.github.com` (update check, once/24h) |
| 🔄 **Backoff** | Status checks use exponential backoff on failures (60s → 5 min cap) |
| ⏳ **Adaptive polling** | Interval doubles after 3 idle cycles, resets when data changes |
| 🚫 **No tracking** | No analytics. No telemetry. No tracking. |

---

## 🏗 Architecture

```
AIBattery/
  Models/       — Data structs (UsageSnapshot, RateLimitUsage, TokenHealthStatus, ...)
  Services/     — OAuthManager, RateLimitFetcher, SessionLogReader, TokenHealthMonitor, ...
  ViewModels/   — Single UsageViewModel (@MainActor, ObservableObject)
  Views/        — SwiftUI views (popover sections, menu bar label, auth screen)
  Utilities/    — TokenFormatter, ModelNameMapper, ThemeColors, SettingsManager, AppLogger
```

**Zero dependencies** — Apple frameworks only (SwiftUI, Charts, Security, Foundation, AppKit).

<details>
<summary>📋 <strong>Detailed specs</strong></summary>

| File | Covers |
|---|---|
| [`ARCHITECTURE.md`](spec/ARCHITECTURE.md) | Data flow, project tree, build config, network & file access |
| [`DATA_LAYER.md`](spec/DATA_LAYER.md) | Every model, service, and algorithm |
| [`UI_SPEC.md`](spec/UI_SPEC.md) | View hierarchy, layout rules, section specs |
| [`CONSTANTS.md`](spec/CONSTANTS.md) | Every hardcoded value — thresholds, URLs, pricing, sizes |

</details>

---

## ♿ Accessibility

- **VoiceOver** — all interactive elements include accessibility labels and hints
- **Keyboard navigation** — fully navigable without a mouse
- **Colorblind mode** — Settings → Display → Colorblind switches to a blue/cyan/amber/purple palette
- **First-launch tutorial** — 3-step walkthrough on first use

---

## 🗑 Uninstall

**Homebrew:**

```bash
brew uninstall --cask aibattery
```

<details>
<summary>🧹 <strong>Manual uninstall</strong></summary>

1. Right-click **AI Battery** in the menu bar → **Quit**
2. Open **Applications** in Finder → drag **AI Battery** to the Trash

To also remove stored settings:

```bash
security delete-generic-password -s "AIBattery" 2>/dev/null   # OAuth tokens (all accounts)
defaults delete com.KyleNesium.AIBattery 2>/dev/null           # Preferences
```

AI Battery doesn't write any other files. Your Claude Code data (`~/.claude/`) is untouched.

</details>

---

## 🤝 Contributing

Contributions welcome! Please read the [contributing guide](CONTRIBUTING.md) first. See [CHANGELOG.md](CHANGELOG.md) for version history.

## 🧪 Test Coverage

**358 tests** across 26 test files.

| Area | Tests | What's covered |
|------|-------|----------------|
| Models | 140 | Token summaries, rate limit parsing, plan tiers, health status, metric modes, API profiles, session entries, account records, stats cache, usage snapshots (projections, trends, busiest day) |
| Services | 142 | Version checker (semver comparison, tag stripping, cache behavior, force check, skip version), notification manager (alert thresholds, AppleScript quoting), token health monitor (band classification, warnings, anomalies, velocity), status checker (severity ordering, incident escalation, component IDs, status string parsing), session log reader (entry decoding, makeUsageEntry), account store (multi-account CRUD, persistence) |
| Utilities | 76 | Token formatter (K/M suffixes, boundaries), model name mapper (display names, versions, date stripping), Claude paths (suffixes, URLs), theme colors (standard + colorblind palettes, NSColor, semantic colors, danger), settings manager (export/import round-trip, defaults completeness, type preservation), UserDefaults keys (prefix, uniqueness), model pricing (cost calculation, formatting) |

## 📄 License

[MIT](LICENSE)

<div align="center">

# ✦ AI Battery

**A battery meter for Claude Code.**

Rate limits, context health, and token usage — always visible in your macOS menu bar.

[![Swift](https://img.shields.io/badge/Swift-5.9-orange?logo=swift&logoColor=white)](https://swift.org)
[![macOS](https://img.shields.io/badge/macOS-13%2B-blue?logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![CI](https://github.com/KyleNesium/AIBattery/actions/workflows/ci.yml/badge.svg)](https://github.com/KyleNesium/AIBattery/actions/workflows/ci.yml)

<br/>

<img src="screenshots/dashboard.png" width="240" alt="AI Battery dashboard" />

</div>

---

## Install

**Quick install** — paste in Terminal:

```bash
curl -sL https://github.com/KyleNesium/AIBattery/releases/latest/download/AIBattery.zip -o /tmp/AIBattery.zip && ditto -x -k /tmp/AIBattery.zip /Applications && xattr -cr /Applications/AIBattery.app && open /Applications/AIBattery.app
```

**Or download the DMG** from [Releases](https://github.com/KyleNesium/AIBattery/releases/latest):

1. Open `AIBattery.dmg` and drag **AI Battery** to **Applications**
2. Launch from Applications — macOS will block it on first run
3. Open **System Settings → Privacy & Security** → scroll down → click **Open Anyway**

> **Terminal alternative:** If macOS says the app is damaged, run `xattr -cr /Applications/AIBattery.app` then relaunch.

**Or build from source:**

```bash
git clone https://github.com/KyleNesium/AIBattery.git && cd AIBattery
./scripts/build-app.sh
open .build/AIBattery.app
```

Requires **macOS 13+** and [Claude Code](https://docs.anthropic.com/en/docs/claude-code).

## Authentication

OAuth 2.0 with PKCE — same protocol as Claude Code.

1. Launch AI Battery — the auth screen appears on first run
2. Click **Authenticate** → browser opens to Anthropic's sign-in page
3. Sign in → copy the authorization code
4. Paste into AI Battery → done

Sessions auto-refresh. Tokens stored in macOS Keychain (separate from Claude Code credentials). Error messages are specific — expired codes, invalid codes, and network errors each get a clear description.

## How It Works

AI Battery makes a minimal API call each refresh cycle to read your rate limit headers. It also reads local JSONL session logs for token counts and context health — **never your message content**.

```
✦ 71% · ACME          ← menu bar: selected metric + org
```

Click the ✦ icon to open the dashboard:

| Section | What you see |
|---|---|
| **Rate Limits** | 5-hour burst + 7-day sustained — utilization %, reset countdown, binding indicator |
| **Context Health** | 5 most recent sessions with `< 1/5 >` navigation |
| **Tokens** | Per-model breakdown with input/output/cache read/cache write |
| **Insights** | Today's messages/sessions/tools, all-time stats |
| **Activity** | Sparkline chart — 24H · 7D · 12M toggle |

## Metrics

The segmented toggle picks which metric drives the ✦ icon color:

| Mode | Tracks | Best for |
|---|---|---|
| **5-Hour** | Burst rate limit | Knowing when you'll get throttled |
| **7-Day** | Sustained rate limit | Pacing usage across the week |
| **Context** | Session context fullness | Knowing when to start fresh |

Selected metric moves to the top. The other two stay visible below.

## Context Health

<table>
<tr>
<td width="55%">

Shows your **5 most recent sessions** with context health. Browse with `< 1/5 >` chevrons.

Each session displays: **project name** · **git branch** · **duration** · **last active time**.

Percentages are relative to the **usable window** — 80% of the model's raw context window. At 100%, Claude Code auto-compacts.

| Color | Range | Meaning |
|---|---|---|
| 🟢 Green | < 60% | Plenty of room |
| 🟠 Orange | 60–80% | Quality may degrade |
| 🔴 Red | > 80% | Start a fresh session |

Additional warnings for long conversations (15+ turns) and high input-to-output ratios (20:1+).

</td>
<td width="45%" align="center">
<img src="screenshots/context.png" width="280" alt="Context Health view" />
</td>
</tr>
</table>

**When you hit orange or red:**
1. Run `/compact` to save a summary to project memory
2. Keep key decisions in `CLAUDE.md` — loaded automatically every session
3. Start a new terminal in the same directory and pick up where you left off

## Settings

<table>
<tr>
<td width="55%">

Click ⚙️ in the header to configure:

| Setting | What it does |
|---|---|
| **Name** | Display name shown in the header |
| **Org** | Organization name (the API only returns a UUID) |
| **Refresh** | Poll interval: 10–60s · ~3 tokens per refresh |
| **Models** | Only show models used within period: 1–7 days or All |
| **Alerts** | Notify when Claude.ai or Claude Code goes down (separate toggles) |

The footer shows a **staleness indicator** — "Updated just now" when fresh, or "Updated Xm ago" in orange when using cached data.

</td>
<td width="45%" align="center">
<img src="screenshots/settings.png" width="280" alt="Settings view" />
</td>
</tr>
</table>

## FAQ

**Only rate limits show — tokens, models, and activity are all empty?**

Token usage, context health, and activity stats come from Claude Code's local session logs (`~/.claude/`). These populate after you've used Claude Code for a bit. To kickstart it:

1. Run a few Claude Code sessions from the terminal
2. Run `/stats` inside Claude Code — this generates the stats cache
3. Click the refresh button in AI Battery

Rate limits (5-hour / 7-day) always work immediately since they come from the API.

**Green ✦ at 0%?** Credits just reset, or no usage yet — this is normal.

**Wrong org?** Click ⚙️ → set it manually (the API only returns a UUID).

**What's "binding"?** Whichever rate limit window is currently the active constraint.

**What's ⚠️ "throttled"?** Anthropic is actively limiting your requests. Wait for the reset timer.

**Why does macOS block the app or ask about Keychain access?**

AI Battery isn't notarized — there's no Apple Developer license behind this project, so macOS treats it as unidentified. Two prompts may appear on first launch:

- **Gatekeeper block** — macOS prevents the app from opening. Fix: **System Settings → Privacy & Security → Open Anyway** (see [Install](#install))
- **Keychain access** — the app stores a single OAuth token in macOS Keychain, Apple's encrypted credential store. This is the safest option — the same place Claude Code, browsers, and every other macOS app stores secrets. Click **Always Allow**.

Both are one-time prompts. Neither will appear again after the first launch.

## Privacy

- Reads local JSONL for token counts only — **never your message content**
- Network calls: `api.anthropic.com` (rate limits) · `console.anthropic.com` (OAuth) · `status.claude.com` (status)
- Status checks back off for 5 minutes after failures — no hammering downed services
- No analytics. No telemetry. No tracking.

## Architecture

```
AIBattery/
  Models/       — Data structs (UsageSnapshot, RateLimitUsage, TokenHealthStatus, ...)
  Services/     — OAuthManager, RateLimitFetcher, SessionLogReader, TokenHealthMonitor, ...
  ViewModels/   — Single UsageViewModel (@MainActor, ObservableObject)
  Views/        — SwiftUI views (popover sections, menu bar label, auth screen)
  Utilities/    — TokenFormatter, ModelNameMapper, AppLogger, UserDefaultsKeys
```

Zero dependencies — Apple frameworks only (SwiftUI, Charts, Security, Foundation, AppKit).

Detailed specs in [`spec/`](spec/):

| File | Covers |
|---|---|
| [`ARCHITECTURE.md`](spec/ARCHITECTURE.md) | Data flow, project tree, build config, network & file access |
| [`DATA_LAYER.md`](spec/DATA_LAYER.md) | Every model, service, and algorithm |
| [`UI_SPEC.md`](spec/UI_SPEC.md) | View hierarchy, layout rules, section specs |
| [`CONSTANTS.md`](spec/CONSTANTS.md) | Every hardcoded value — thresholds, URLs, pricing, sizes |

## Uninstall

```bash
# Quit the app
osascript -e 'quit app "AI Battery"'

# Remove the app
rm -rf /Applications/AIBattery.app

# Remove stored OAuth tokens from Keychain
security delete-generic-password -s "AIBattery" 2>/dev/null

# Remove preferences
defaults delete com.KyleNesium.AIBattery 2>/dev/null
```

AI Battery doesn't write any other files. Your Claude Code data (`~/.claude/`) is untouched.

## Accessibility

All interactive UI elements include VoiceOver labels. The app is navigable with keyboard and screen readers.

## Contributing

Contributions welcome! Please read the [contributing guide](CONTRIBUTING.md) first. See [CHANGELOG.md](CHANGELOG.md) for version history.

## License

[MIT](LICENSE)

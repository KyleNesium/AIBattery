# FAQ and troubleshooting

Answers that used to live in the README. Each entry is self-contained: the symptom, the cause, the exact fix.

## Install and first launch

### macOS blocks the app, or says it is "damaged and can't be opened"

AI Battery is not notarized (no Apple Developer licence behind the project), so Gatekeeper treats it as unidentified. Remove the quarantine flag and relaunch:

```bash
xattr -cr /Applications/AIBattery.app
open /Applications/AIBattery.app
```

Alternatively: **System Settings → Privacy & Security → Open Anyway**. Either fix is one-time per install.

### The app appears in the menu bar, then disappears

- **On first launch**: Gatekeeper silently killed it. Run the `xattr` command above.
- **After running for a while**: update to the latest release. Versions before v2.0.3 had concurrency bugs that could crash during background refresh or sleep/wake.
- **Still happening**: open **Console.app**, filter for `AIBattery`, and [open an issue](https://github.com/KyleNesium/AIBattery/issues) with the crash log and your macOS version. macOS 13.0–13.2 had `MenuBarExtra` bugs that 13.3 fixed.

### macOS asks about Keychain access

AI Battery stores each account's OAuth refresh token in the macOS Keychain (one item per account). Click **Always Allow**. The prompt appears once on first launch and once after each in-app update, because the updated binary carries a new ad-hoc signature.

## Accounts and sessions

### How sessions are kept alive

- Access tokens refresh automatically, 5 minutes before expiry, to avoid clock-skew failures.
- Temporary server errors retry automatically; only a genuine auth error signs the account out.
- The refresh token lives in the Keychain, separate from Claude Code's and the Codex CLI's own credentials. The access token is held in memory only.
- Error messages are specific: expired code, invalid code, server error and network error each have their own text.

### Only rate limits show. Tokens, models and activity are empty

Token usage, context health and activity come from local session logs: `~/.claude/projects/` for Claude Code and `~/.codex/sessions/` for the Codex CLI. They fill in after you have used the tool for a while.

1. Run a few Claude Code or Codex sessions from the terminal.
2. Claude only: run `/stats` inside Claude Code once to generate `~/.claude/stats-cache.json`.
3. AI Battery picks the data up on its next polling cycle.

Rate-limit windows come from Anthropic account metadata (Claude) or the ChatGPT usage endpoint (Codex). If the endpoint is unreachable or changes shape, the footer says **Cached** (hover it for the reason) and the last known values stay on screen.

### Why does AI Battery differ from Claude Code `/usage`?

AI Battery reads 5-hour and 7-day usage from Claude Code account metadata, falling back to legacy Anthropic headers or cached values when a window is temporarily unavailable. Claude Code's `/usage` uses different plan-usage semantics and reset timings, so the two can disagree during API transitions or while AI Battery is serving stale data.

## Reading the meter

### Green star at 0%

Credits just reset, or there is no usage yet. This is normal.

### What is the "binding" window?

Whichever rate-limit window is currently the active constraint. Its percentage is what the menu bar shows.

### What does "throttled" mean?

Your provider is actively limiting requests. Wait for the reset timer shown beside the bar.

## Context health

Think of context as the model's short-term memory. Every message, file read, tool call and response accumulates in one window, and nothing is discarded between turns. When the window fills, Claude Code auto-compacts: it summarises the session into a few paragraphs and clears the rest. That summary is lossy. File contents, specific instructions and nuanced decisions get compressed, and the model keeps working from a recap instead of the real conversation.

Percentages in AI Battery are relative to the model's full context window: 1M tokens for current Claude models, about 258K for GPT-5-family models via Codex. Anthropic documents auto-compaction once context exceeds 95%.

| Colour | Range | Meaning |
|---|---|---|
| Green | below 60% | Plenty of room |
| Orange | 60–80% | Quality may degrade |
| Red | above 80% | Start a fresh session |

Patterns worth noticing:

- **Long conversation (15+ turns).** Old history is re-read on every turn, slowing responses and spending budget on stale context.
- **High input-to-output ratio (20:1 or more).** File reads, logs and tool results are flooding the window with data the model may reference once but pays for on every later turn.
- **Zero-output session.** Multiple turns with no output tokens usually means an error loop or a stalled conversation.
- **Rapid consumption.** A very short session with high token usage points to large files or long pastes.

When you reach orange or red:

1. Run `/compact` to save a summary to project memory.
2. Keep key decisions in `CLAUDE.md`, which is loaded automatically every session.
3. Start a new terminal in the same directory and carry on.

## Uninstall completely

```bash
brew uninstall --cask aibattery        # or drag AI Battery from Applications to the Trash
security delete-generic-password -s "AIBattery" 2>/dev/null   # OAuth tokens, all accounts
defaults delete com.KyleNesium.AIBattery 2>/dev/null           # preferences
rm -rf ~/Library/Application\ Support/AIBattery                 # token ledger + instance lock
```

That folder holds the persistent token ledger (`token-ledger.json`) and the single-instance lock. AI Battery writes nothing else. Your Claude Code data in `~/.claude/` and Codex CLI data in `~/.codex/` are untouched.

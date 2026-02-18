# Changelog

## [1.0.1] — 2026-02-18

### Fixed
- Ad-hoc codesign the app bundle so macOS Keychain can identify the app — eliminates repeated Keychain access prompts on launch

### Removed
- Dead `KeychainReader.swift` (unused Claude Code API key reader)

## [1.0.0] — 2026-02-18

Initial public release.

- OAuth 2.0 authentication with PKCE (same protocol as Claude Code)
- Real-time rate limit monitoring (5-hour burst + 7-day sustained windows)
- Context health tracking across your 5 most recent sessions
- Per-model token breakdown (input, output, cache read, cache write)
- Activity charts (24H hourly, 7D daily, 12M monthly)
- Today's stats: messages, sessions, tool calls
- System status integration via status.claude.com
- Outage notifications for Claude.ai and Claude Code (via osascript)
- VoiceOver accessibility labels on all interactive elements
- Structured logging via os.Logger
- Unit test suite with ~130 test cases
- GitHub Actions CI (build → test → bundle)

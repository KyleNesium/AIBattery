# Security Policy

## Supported Versions

| Version | Supported |
|---------|-----------|
| Latest release | Yes |
| Older releases | No |

## Reporting a Vulnerability

If you discover a security vulnerability, please report it responsibly:

1. **Do not** open a public issue
2. Use [private vulnerability reporting](https://github.com/KyleNesium/AIBattery/security/advisories/new) on GitHub
3. Include steps to reproduce, if possible
4. Allow reasonable time for a fix before public disclosure

## Scope

AI Battery stores OAuth refresh tokens (Claude and ChatGPT/Codex) and OpenAI API keys in the macOS Keychain, reads local Claude Code (`~/.claude/projects`) and Codex CLI (`~/.codex/sessions`) session logs for token counts only, reads `~/.codex/auth.json` once on an explicit import, and runs a loopback-only (127.0.0.1:1455) listener during Codex sign-in. Security concerns related to token or API-key handling, credential storage, the OAuth callback, or unintended data exposure (including account identities such as sign-in emails) are in scope.

## Response

Critical issues will be patched and released as soon as possible.

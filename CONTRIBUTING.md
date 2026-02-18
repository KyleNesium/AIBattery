# Contributing to AI Battery

Thanks for your interest in contributing! Here's how to get started.

## Requirements

- **macOS 13+** (Ventura or later)
- **Xcode 16+** (for Swift Testing framework) or Xcode Command Line Tools for builds
- A [Claude Code](https://docs.anthropic.com/en/docs/claude-code) account (to test with real data)

## Development Setup

```bash
git clone https://github.com/KyleNesium/AIBattery.git
cd AIBattery
swift build
```

## Project Structure

```
AIBattery/
  Models/       — Data structs
  Services/     — Business logic (singletons)
  ViewModels/   — UsageViewModel (single source of truth)
  Views/        — SwiftUI views
  Utilities/    — Formatters and mappers
spec/           — Authoritative specs (architecture, data layer, UI, constants)
scripts/        — Build and packaging scripts
Tests/          — Unit tests (Swift Testing framework)
```

## Spec-Driven Development

The `spec/` directory is the source of truth. When making changes:

1. **Read the relevant spec** to understand the current design
2. **Update the spec first** if your change alters behavior
3. **Then update the code** to match

This keeps documentation accurate and makes it easy for others to understand the codebase.

## Code Style

- Zero external dependencies — Apple frameworks only
- One primary type per file, filename matches type name
- Services use `static let shared` singleton pattern
- Models are plain `Codable` structs
- Views take data via init parameters (not `@EnvironmentObject`)
- `UsageViewModel` is the only `ObservableObject`
- Use `TokenFormatter` for all numeric display
- Use `ModelNameMapper` for model ID → display name
- 4-space indentation (see `.editorconfig`)
- Structured logging via `AppLogger` — no bare `print()` calls

## Building & Testing

```bash
# Debug build
swift build

# Run tests (requires Xcode for Swift Testing framework)
swift test

# Release build + .app bundle + zip + dmg
./scripts/build-app.sh

# Launch
open .build/AIBattery.app
```

All tests must pass before opening a PR. CI runs on every push and PR — see `.github/workflows/ci.yml`.

## Pull Requests

1. Fork the repo and create a feature branch (`feat/...`, `fix/...`, `chore/...`)
2. Make your changes (code + spec updates + tests)
3. Run `swift test` and ensure all tests pass
4. Run `swift build -c release` to verify the release build
5. Test locally with a real Claude Code session
6. Open a PR using the template — describe what changed and why

## Reporting Issues

Use the [issue templates](https://github.com/KyleNesium/AIBattery/issues/new/choose) — they'll guide you through providing the right information.

## Security

Found a vulnerability? Please report it privately — see [SECURITY.md](SECURITY.md).

## License

By contributing, you agree that your contributions will be licensed under the [MIT License](LICENSE).

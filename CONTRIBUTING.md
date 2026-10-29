# Contributing to LingoPop

Thanks for your interest in LingoPop! Project architecture and conventions live in [AGENTS.md](AGENTS.md); read it before making non-trivial changes.

## Development setup

Requirements: macOS 13+, Xcode 16+, and XcodeGen.

```bash
brew install xcodegen
./scripts/setup-cert.sh   # optional: stable self-signed cert so the TCC grants survive rebuilds
./build.sh run            # build, install to ~/Applications/LingoPop.app and launch
```

The Xcode project is generated from `project.yml`; never edit `LingoPop.xcodeproj` directly.

## Before opening a pull request

```bash
./scripts/test.sh
python3 scripts/check-localizations.py
```

- Open pull requests against `main` only. Direct pushes to `main` are blocked.
- CI (`build-and-test`) must be green before a PR can be merged.
- Pull requests are reviewed by CodeRabbit (config in `.coderabbit.yaml`). Merging requires its approval plus green `build-and-test`: resolve or answer its comments, and re-trigger with `@coderabbitai review` after pushing fixes.
- Update `AGENTS.md` if you change the architecture or conventions.
- Include screenshots for UI changes.

## Localization rules

- Keys in `App/Localizable.xcstrings` are the English strings themselves.
- SwiftUI literals localize automatically; use `String(localized: "...")` for AppKit and other non-View strings.
- Never localize persisted identifiers (`rawValue`s, UserDefaults keys), language names in `Languages.all`, AI prompt texts, log messages, or HTTP/JSON fields.
- Keep format specifiers (`%@`, `%lld`, `%1$@`, `%%`) and special tokens (such as `{{targetLanguage}}`) identical in every translation.

See the Localization section in `AGENTS.md` for details.

## Security and secrets

Never paste API keys, tokens, or other secrets into issues, pull requests, or logs. Report vulnerabilities privately as described in [SECURITY.md](SECURITY.md).

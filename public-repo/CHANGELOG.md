# Changelog

All notable changes to LingoPop are documented here. Each release also has auto-generated notes on the [Releases page](https://github.com/slucheninov/lingopop/releases).

The format is loosely based on [Keep a Changelog](https://keepachangelog.com/) and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

## v0.2.8 - 2026-05-24 Enhance error handling in PopupState and PopupView; improve TranslationError structure for better user feedback.

## v0.2.7 - 2026-05-19 Added DeepL and Microsoft Translator providers

## v0.2.6 - 2026-05-18 Fix: add unique identifier to ProviderDetailView for improved state management.

## v0.2.3 — 2026-05-17 Implement retranslation feature in PopupView and PopupState, allowing users to select a target language for translations; enhance AppDelegate to handle retranslation logic.

## v0.2.2 — 2026-05-17 Update project versioning to 0.2.2; refactor use dynamic versioning.

## [0.1.0] — Initial public release

### Added
- Three AI operations: **Translate**, **Fix grammar**, **Rewrite**, each with its own configurable global hotkey
- Five providers: Claude, OpenAI, Gemini, Google (Free), Google Translate (Cloud)
- Per-provider fallback that triggers on rate-limit / server / network errors
- Auto-detect input language with configurable language pairs (e.g. Russian → Ukrainian, English → Ukrainian)
- Popup actions: Copy, Replace (paste back into the source app), Retry with another provider
- Translation history with configurable size limit (0–100 entries)
- Settings + history sync via iCloud Drive between Macs (opt-in by default when iCloud Drive is available)
- API keys stored locally in an AES-GCM encrypted file, machine-bound, never synced
- Universal binary (Apple Silicon + Intel)

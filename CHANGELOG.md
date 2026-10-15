# Changelog

All notable changes to LingoPop are documented here. Each release also has auto-generated notes on the [Releases page](https://github.com/slucheninov/lingopop/releases).

The format is loosely based on [Keep a Changelog](https://keepachangelog.com/) and the project uses [Semantic Versioning](https://semver.org/).

## v0.3.16 — 2026-10-15

**Technical release (refactoring).** Mostly internal restructuring with no new features.

- Internal refactoring of the popup actions, the shared error model and the Providers settings tab
- The popup window now resizes itself together with its content

- Google Cloud Translation API key is now sent in the `X-goog-api-key` header instead of the URL

## v0.3.15 — 2026-10-15

- **Retry** button is now available on error popups
- Truncated provider responses are flagged with a banner instead of appending a warning to the text (which could end up pasted into your document)
- Fixed the popup occasionally appearing invisible when re-triggered quickly
- Fixed **Retry** after Rewrite / Explain re-running the original operation instead of the follow-up one
- Fixed the Screen Recording permission prompt not appearing on macOS 13 / 14
- Fixed DeepL free / pro key detection
- **Replace** now verifies the target app is frontmost before pasting, and only restores your clipboard if it was not changed in the meantime
- Gemini API key is now sent in a header instead of the URL
- Provider requests no longer follow redirects to a different host
- Removed deprecated model presets: gpt-4.1, gpt-4.1-mini, gpt-5.4-nano, claude-haiku-4-5, gemini-3.5-flash
- Migration for API keys stored by versions before the HKDF change (keys no longer appear saved but unusable)
- Fixed Norwegian and Chinese language codes for DeepL / Microsoft Translator
- Removed the unused Apple Events entitlement
- CI moved to macOS 15 runners with pinned GitHub Actions

## v0.3.14 — 2026-10-15

- New **Grok** (xAI) provider: all operations including Screen Translate vision retry; models grok-4.7 / 4.6 / 4.5 / 4.3 and more
- Refreshed model presets: Claude Fable 5.1 / Opus 5.5 / Sonnet 5.5 / Haiku 5.5, OpenAI GPT-6 Astra / 6.1 Sol / 6 Luna, Gemini 4 Argon / 3.8 Flash
- Usage cost estimates for the new models
- New installs default to Claude Haiku 5.5 / GPT-6 Luna / Gemini 3.8 Flash

## v0.3.12 — 2026-08-17

- Enhance output sanitization in PromptBuilder

## v0.3.7 — 2026-07-25 Menu history Display setting

- New **Display** setting in **Settings → Main → Limits** — controls how many entries appear in the status-bar menu, independent of **History size**
- Previously the status menu was hard-capped at 10 recent entries regardless of History size; now it shows `min(Display, History size)` entries
- `⌘1`–`⌘0` shortcuts remain limited to the first 10 visible rows

## v0.3.5 — 2026-06-19 Magic operation and update checker

### Magic operation

- New **Magic** operation: one hotkey that fixes grammar, improves style, and translates in a single AI call — all at once. Requires Claude, OpenAI, or Gemini
- Fully customisable system prompt in **Settings → Magic**. Use `{{targetLanguage}}` as a placeholder for your configured target language
- Custom prompt is sanitised (2 000 character limit) and syncs via iCloud Drive alongside other settings
- Default prompt combines grammar fix + style improvement + translation into one step

### Update checker

- LingoPop now checks for new versions every 3 hours in the background
- **Settings → About** shows a banner when a new version is available, with a direct Download link to the release page
- "Check for updates" button in About tab for on-demand checks

## v0.3.3 — 2026-06-12 Security hardening and code quality

- Applied security hardening and code quality improvements from internal audit
- Removed outdated statistics layout files; streamlined project structure

## v0.3.2 — 2026-06-09 Usage Statistics

- New **Usage Statistics** tab in Settings — shows translation counts by operation and by provider
- Native screenshot pipeline for README documentation

## v0.3.1 — 2026-06-07 Screen Translate

- New **Screen Translate** operation: press the hotkey, drag a selection over any part of the screen, and LingoPop extracts the text using Apple's Vision OCR
- Popup first shows the **recognized text** with Copy and Translate buttons — use it as a quick OCR tool without translating, or press Translate to run the full AI translation
- Recognized text is automatically copied to the clipboard the moment it's recognized
- Translation result is also auto-copied — no extra click needed
- **Retry** button lets you skip local OCR and send the captured image directly to a vision-capable provider (Claude, OpenAI, Gemini) for combined OCR + translation in one step
- Works reliably across multiple monitors, including mixed Retina/non-Retina setups
- Requires **Screen Recording** permission (TCC prompt shown on first use; Settings → Main shows permission status)

## v0.2.14 — 2026-05-30 Explain operation

- New **Explain** action in the popup: tap it to get a concise explanation of any translated or rewritten text, right in the same popup window
- Explanation is generated in the configured target language and covers meaning, context, and key nuances
- The Explain button only appears on non-explain results, so it never chains recursively

## v0.2.12 - 2026-05-30 Privacy Policy and clipboard transparency

- Added a **Privacy Policy** link in the About tab of Settings — opens the policy directly from the app
- Enhanced in-app privacy notes clarifying that clipboard data is processed temporarily and never stored or sent outside the selected AI provider

## v0.2.11 - 2026-05-30 Improved recent translations menu

- Recent translations in the menu bar are now easier to read — more text visible before it's cut off
- Each item shows a keyboard shortcut (⌘1–⌘0) so you can quickly copy a recent translation without touching the mouse
- The menu looks more polished and consistent with the rest of macOS

## v0.2.10 - 2026-05-27 Refine PopupView layout with improved padding and background handling; enable shadow for PopupWindow for enhanced visual depth.

## v0.2.9 - 2026-05-25 Simplify PopupView background handling and improve shape clipping for better visual consistency.

## v0.2.8 - 2026-05-24 Enhance error handling in PopupState and PopupView; improve TranslationError structure for better user feedback.

## v0.2.7 - 2026-05-19 Added DeepL and Microsoft Translator providers

## v0.2.6 - 2026-05-18 Fix: add unique identifier to ProviderDetailView for improved state management.

## v0.2.5 — 2026-05-17 Improved popup layout and menu hotkeys

- Enhanced menu item handling for hotkeys — access recent translations more reliably from the menu bar
- Improved PopupView layout and button styles for better usability

## v0.2.4 — 2026-05-17 Dynamic font sizes and refined prompts

- Popup now supports **dynamic font sizes** — text adapts to system accessibility settings
- Improved layout in PopupView for longer content
- Refined AI operation prompts for greater clarity and specificity

## v0.2.3 — 2026-05-17 Implement retranslation feature in PopupView and PopupState, allowing users to select a target language for translations; enhance AppDelegate to handle retranslation logic.

## v0.2.2 — 2026-05-17 Update project versioning to 0.2.2; refactor use dynamic versioning.

## v0.2.1 — 2026-05-17 Recent translations in menu bar

- Recent translations now appear directly in the menu bar popup — access previous results at a glance
- README updated to highlight the new feature

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

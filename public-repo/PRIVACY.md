# Privacy Policy

LingoPop is a macOS menu-bar app. This document describes what data the app handles and where it goes.

## Data the app stores locally

- **API keys** for AI providers (Claude, OpenAI, Gemini, Google Translate) are stored in `~/Library/Application Support/LingoPop/secrets.dat`. The file is encrypted with AES-GCM using a symmetric key derived from your machine's hardware UUID (`IOPlatformUUID`) plus a static salt. Decryption requires running LingoPop on the same Mac. File permissions are 0600 (owner read/write only).
- **Settings** (preferred provider, target language, hotkeys, history size limit, etc.) and **translation history** (last N entries) are stored in `UserDefaults` plus, if iCloud Drive sync is enabled in Settings → Main, in `~/Library/Mobile Documents/com~apple~CloudDocs/LingoPop/settings.json` and `history.json`. The history includes the original text, the translated text, and metadata (timestamp, provider, target language).

## Data sent to third parties

When you trigger an operation (translate, fix grammar, rewrite), LingoPop sends the selected text and a system prompt to the AI provider you have configured as active. The endpoint depends on the provider:

- Claude → `api.anthropic.com` (or a custom base URL you configure)
- OpenAI → `api.openai.com` (or a custom base URL — useful with LiteLLM proxies)
- Gemini → `generativelanguage.googleapis.com`
- Google (Free) → `translate.googleapis.com/translate_a/single`
- Google Translate → `translation.googleapis.com/language/translate/v2`

Each provider has its own privacy policy and data-retention practices. LingoPop is not affiliated with any of them; refer to their documentation for how they handle your data.

LingoPop does **not** send any data to the maintainer or to any server other than the AI provider endpoint you choose.

## What's synced via iCloud Drive

If iCloud Drive sync is enabled (it's on by default when iCloud Drive is available on your Mac), the app writes plain JSON files to your iCloud Drive folder. These files contain:

- Settings (provider preference, hotkeys, language pairs, etc.)
- Translation history entries

These files sync between Macs signed into the same Apple ID, just like any other iCloud Drive file. They do **not** include API keys — keys stay local on each Mac.

You can disable iCloud sync in Settings → Main.

## Clipboard data

When you trigger an operation, LingoPop temporarily reads the system clipboard to capture your selected text. This works as follows:

1. The current clipboard contents are saved in memory.
2. A `⌘C` keystroke is simulated to copy your selection.
3. The selected text is read from the clipboard and sent to your chosen AI provider to perform the operation.
4. The original clipboard contents are restored immediately afterward.

**The clipboard snapshot is never written to disk and is never sent anywhere except the AI provider you have chosen.** The AI provider receives only the text needed for the operation — no clipboard metadata, no surrounding context, no other clipboard entries.

If translation history is enabled, the source text and result are saved to:

- `~/Library/Application Support/LingoPop/` (local, always)
- `~/Library/Mobile Documents/com~apple~CloudDocs/LingoPop/history.json` (only if iCloud sync is on in Settings → Main)

You can limit or clear history in Settings → Main, and disable iCloud sync at any time.

### Privacy summary for clipboard data

- Clipboard data is only read in memory for the duration of the operation.
- No clipboard data is stored by LingoPop beyond the optional translation history entries.
- No clipboard data is transmitted to LingoPop or any third party other than the AI provider you select.
- No analytics are collected on your clipboard content.
- Your clipboard history (outside of LingoPop's own translation history) remains entirely private and under your control.

## Telemetry and analytics

There is no telemetry, no analytics, no crash reporting service. The app makes outbound network requests only to the AI provider you choose, and only when you trigger an operation.

## Permissions the app requests

- **Accessibility** (mandatory for the hotkey workflow) — used to read what text you have selected. The app simulates a `⌘C` keystroke and reads the system clipboard, then restores the previous clipboard contents.
- **App Sandbox** — explicitly disabled. The app needs unsandboxed access to post CGEvents and read another app's clipboard. As a result it can read arbitrary user files in principle, though it doesn't do so by design.

## Where your data goes when you uninstall

Delete `/Applications/LingoPop.app`, then optionally remove:
- `~/Library/Application Support/LingoPop/`
- `~/Library/Mobile Documents/com~apple~CloudDocs/LingoPop/`
- `~/Library/Preferences/com.lingopop.app.plist`

## Contact

Open an issue in this repository for privacy questions.

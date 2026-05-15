# LingoPop

> Native macOS menu-bar app: select text anywhere, press a hotkey, get an AI translation, grammar fix, or rewrite in a popup near your cursor.

**This repo contains only releases. The source lives in a private repo.**

## Features

- **Translate** to any target language, with optional auto-detect that routes between configured language pairs (e.g. Russian ↔ Ukrainian).
- **Fix grammar / spelling** in place — same language, just cleaned up.
- **Rewrite** to improve clarity and style while preserving meaning.
- Per-operation global hotkeys, plus menu-bar shortcuts.
- Popup actions: **Copy**, **Replace** (pastes the result back into the source app), **Retry with another provider**.
- Providers: **Claude**, **OpenAI**, **Gemini**, **Google Translate** (free public endpoint or official Cloud Translation v2). Each provider has its own optional **fallback** that fires on rate-limit / server / network errors.
- Translation history (last N entries, configurable).
- Settings sync between Macs via iCloud Drive. API keys stay local in an encrypted file.

## Install

1. Download the latest `LingoPop-X.Y.Z-mac-universal.dmg` from [Releases](../../releases/latest).
2. Open the dmg, drag **LingoPop** into the **Applications** folder.
3. **First launch:** Finder will refuse to open it directly (Gatekeeper warning — the app is ad-hoc signed and not notarized). Right-click `LingoPop.app` in Applications → **Open** → click **Open** in the dialog. macOS remembers this decision.
4. When prompted, grant **Accessibility** access:
   - System Settings → Privacy & Security → Accessibility
   - Enable the toggle next to LingoPop
   - **Fully quit** LingoPop (menu-bar icon → Quit) and relaunch — macOS only reads the new permission on app start.

### Alternative install (zip)

If you prefer the zip:

```bash
cd ~/Downloads
unzip LingoPop-X.Y.Z-mac-universal.zip
mv LingoPop.app /Applications/
xattr -dr com.apple.quarantine /Applications/LingoPop.app   # bypass Gatekeeper without right-click
open /Applications/LingoPop.app
```

### Apple Silicon / Intel

- **`-universal.dmg` / `-universal.zip`** — works on both Apple Silicon (M1/M2/M3/M4) and Intel Macs.
- **`-arm64.zip`** — smaller, Apple Silicon only.
- **`-x86_64.zip`** — smaller, Intel only.

When in doubt, use universal.

## Setup

After first launch, click the LingoPop icon in the menu bar → **Settings**.

- **Main** — pick target language (or enable Auto-detect with language pairs), tune limits, toggle Launch at login.
- **Providers** — pick at least one provider and paste an API key. You can keep keys for multiple providers and switch between them.
- **Shortcuts** — assign global hotkeys to Translate / Fix grammar / Rewrite.

To translate: select text in any app → press your Translate hotkey (default ⌥T) → the popup appears near your cursor.

## Getting API keys

| Provider | Where to get a key |
|---|---|
| Claude | [console.anthropic.com](https://console.anthropic.com/) |
| OpenAI | [platform.openai.com/api-keys](https://platform.openai.com/api-keys) |
| Gemini | [aistudio.google.com/apikey](https://aistudio.google.com/apikey) |
| Google Translate | [console.cloud.google.com](https://console.cloud.google.com/apis/credentials) (enable Cloud Translation API) |
| Google (Free) | No key needed — uses the public translate endpoint. |

## Why is it "ad-hoc signed"?

The app is signed with a local self-signed certificate, not an Apple Developer ID, because the maintainer doesn't have a paid Apple Developer Program subscription ($99/yr). Functionally this only affects the first launch — once you allow Gatekeeper, subsequent launches are normal. The app is open about this; if you want to inspect what's running, check the source repo (request access from the maintainer if it's private).

## Requirements

- macOS 13 (Ventura) or later.
- An API key for the AI provider you want to use (except for "Google Free").

## Privacy

- API keys are stored in `~/Library/Application Support/LingoPop/secrets.dat` (AES-GCM, key bound to your machine UUID).
- Translation history and settings are stored in `~/Library/Mobile Documents/com~apple~CloudDocs/LingoPop/` if iCloud Drive sync is on; otherwise in UserDefaults.
- The app makes outbound HTTPS calls only to the AI provider you choose. No telemetry.

## Reporting issues

Open an issue in this repo with macOS version, LingoPop version, and steps to reproduce.

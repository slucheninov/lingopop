<p align="center">
  <img src="docs/icon.png" alt="LingoPop" width="128" height="128"/>
</p>

<h1 align="center">LingoPop</h1>

<p align="center">
  Native macOS menu-bar app: select text anywhere, press a hotkey, get an AI translation, grammar fix, or rewrite in a popup near your cursor.
</p>

<p align="center">
  <a href="https://github.com/slucheninov/lingopop/releases/latest">
    <img src="https://img.shields.io/github/v/release/slucheninov/lingopop?label=Download&style=for-the-badge&color=blue" alt="Latest release"/>
  </a>
  <img src="https://img.shields.io/badge/macOS-13.0%2B-blue?style=for-the-badge" alt="macOS 13+"/>
  <img src="https://img.shields.io/badge/arch-Apple%20Silicon%20%2B%20Intel-lightgrey?style=for-the-badge" alt="Universal"/>
</p>

## Screenshots

<p align="center">
  <img src="docs/screenshots/popup.png" alt="Translation popup" width="800"/>
</p>

<p align="center">
  <img src="docs/screenshots/menu.png" alt="Menu-bar dropdown" width="500"/>
</p>

<p align="center">
  <img src="docs/screenshots/settings-main.png" alt="Settings – Main tab" width="600"/>
  &nbsp;
  <img src="docs/screenshots/settings-providers.png" alt="Settings – Providers tab" width="600"/>
</p>

<p align="center">
  <img src="docs/screenshots/settings-shortcuts.png" alt="Settings – Shortcuts tab" width="800"/>
</p>

<p align="center">
  <img src="docs/screenshots/history.png" alt="Translation history" width="600"/>
</p>

## Features

- 🌐 **Translate** to any target language. Optional auto-detect routes between configured language pairs (Russian ↔ Ukrainian, English → Ukrainian, etc.)
- ✓ **Fix grammar** — clean spelling, punctuation, and grammar without changing the meaning or style
- ✨ **Rewrite** — improve clarity and flow while keeping the original intent
- ⌨️ Three separate global hotkeys (one per operation), fully customizable
- 📋 Popup actions: **Copy**, **Replace** (pastes back into the source app), **Retry with another provider**
- 🤖 Providers: **Claude**, **OpenAI**, **Gemini**, **Google Translate** (free public endpoint or official Cloud Translation v2)
- 🔁 Per-provider fallback chains — falls back automatically on rate-limits, server errors, or network issues
- 📜 Translation history (last N entries, configurable) — recent translations also appear at the top of the menu for quick access
- ☁️ Settings sync between Macs via iCloud Drive. API keys stay local, encrypted with AES-GCM

## Install

1. Download the latest **`LingoPop-X.Y.Z-mac-universal.dmg`** from [Releases](https://github.com/slucheninov/lingopop/releases/latest).
2. Open the dmg and drag **LingoPop** into the **Applications** folder.
3. **First launch:** the app is ad-hoc signed (not notarized), so macOS Gatekeeper will warn. Right-click `LingoPop.app` in Applications → **Open** → click **Open** in the dialog. You'll only see this once.
4. Grant **Accessibility** access when prompted:
   - System Settings → Privacy & Security → Accessibility
   - Enable the toggle next to LingoPop
   - **Fully quit** LingoPop (menu-bar icon → Quit) and relaunch — macOS only reads the new permission on app start.

### Install via zip

```bash
cd ~/Downloads
unzip LingoPop-X.Y.Z-mac-universal.zip
mv LingoPop.app /Applications/
xattr -dr com.apple.quarantine /Applications/LingoPop.app   # bypass Gatekeeper without right-click
open /Applications/LingoPop.app
```

### Architecture-specific builds

| Asset | Size | Runs on |
|---|---|---|
| `LingoPop-X.Y.Z-mac-universal.dmg` / `.zip` | ~1.2 MB | Apple Silicon **and** Intel |
| `LingoPop-X.Y.Z-mac-arm64.zip` | ~800 KB | Apple Silicon only |
| `LingoPop-X.Y.Z-mac-x86_64.zip` | ~830 KB | Intel only |

When in doubt, take the universal build.

## Setup

After first launch, click the LingoPop icon in the menu bar → **Settings**.

- **Main** — pick target language (or enable Auto-detect with language pairs), tune the character limit and history size, toggle Launch at login.
- **Providers** — pick at least one provider and paste an API key. You can store keys for multiple providers and switch between them. Each provider has its own fallback.
- **Shortcuts** — assign global hotkeys to Translate, Fix grammar, and Rewrite.

The menu-bar dropdown shows the 3 most recent translations at the top — click one to copy the result to the clipboard.

To use: select text in any app → press your hotkey → popup appears near your cursor.

## Getting API keys

| Provider | Where to get a key |
|---|---|
| Claude | [console.anthropic.com](https://console.anthropic.com/) |
| OpenAI | [platform.openai.com/api-keys](https://platform.openai.com/api-keys) |
| Gemini | [aistudio.google.com/apikey](https://aistudio.google.com/apikey) |
| Google Translate | [console.cloud.google.com](https://console.cloud.google.com/apis/credentials) — enable Cloud Translation API |
| Google (Free) | No key needed — uses the public translate endpoint |

## Why does macOS warn me about an unidentified developer?

The maintainer doesn't pay for an Apple Developer Program subscription ($99/yr), so the app is **ad-hoc signed** instead of notarized. The signature still proves the binary hasn't been tampered with after build, but Gatekeeper can't verify the publisher. You only see the warning on first launch.

If you'd rather not bypass Gatekeeper at all, build LingoPop from source (request access to the private source repo from the maintainer).

## Requirements

- macOS 13 (Ventura) or later
- An API key for the AI provider you want to use (or use Google Free, which doesn't need one)

## Privacy

See [PRIVACY.md](PRIVACY.md). Short version:

- API keys live in `~/Library/Application Support/LingoPop/secrets.dat` — AES-GCM encrypted, key bound to your machine's hardware UUID.
- Settings and translation history sync via your iCloud Drive folder (you can disable this in Settings → Main).
- The app makes outbound HTTPS calls only to the AI provider you choose. No telemetry, no analytics.

## Changelog

See [CHANGELOG.md](CHANGELOG.md) or browse [Releases](https://github.com/slucheninov/lingopop/releases).

## Issues & feedback

Open an [issue](https://github.com/slucheninov/lingopop/issues/new/choose) with your macOS version, LingoPop version, and steps to reproduce.

## License

See [LICENSE](LICENSE).

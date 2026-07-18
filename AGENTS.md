# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## What this is

LingoPop is a native macOS menu-bar app (Swift / AppKit + SwiftUI). User selects text anywhere on the system, presses a global hotkey, and a floating popup near the cursor shows the result of an AI operation:

- **Translate** — translate to a configurable target language (with optional auto-detect + per-source-language target via `languagePairs`)
- **Fix grammar** — only grammar / spelling / punctuation, preserving language and style
- **Rewrite** — improve clarity and style while preserving meaning
- **Explain** — concise explanation of the text (meaning, context, key nuances) in the target language
- **Screen Translate** — drag a selection over any screen region; Apple Vision OCR extracts the text first (shown as `.ocr` popup phase with Copy + Translate + Retry buttons); pressing Translate runs the AI translation. OCR text is auto-copied to clipboard on recognition; translation result is also auto-copied. Retry sends the captured image directly to a vision-capable provider (Codex, OpenAI, Gemini) for combined OCR + translation in one step.

Each operation has its own configurable global hotkey and its own menu-bar item. The popup offers Copy, Replace (paste back into the source app via simulated `Cmd+V`), and Retry-with-other-provider. Replace is hidden for Screen Translate results (can't paste back into an image).

Supported providers: **Codex** (`/v1/messages`), **OpenAI** (`/v1/chat/completions`), **Gemini** (`generateContent`), **Google Free** (unofficial `translate.googleapis.com/translate_a/single` — no API key, translate-only), **Google Translate** (Cloud Translation v2 — translate-only), **DeepL**, **Microsoft Translator**. The Google/DeepL/Microsoft providers explicitly declare `supportedOperations = [.translate]`; Codex/OpenAI/Gemini handle all operations. Codex/OpenAI/Gemini also declare `supportsVision = true` and are the only providers eligible for vision-based Screen Translate retry. Each primary provider has a per-provider fallback that fires on retry-able errors (429, 5xx, network).

Requirements: macOS 13.0+, Xcode 15+. The app uses `.accessory` activation policy (no Dock icon, `LSUIElement = YES`), is not sandboxed (needs to post CGEvents and read another app's clipboard via Accessibility, and capture screen content via Screen Recording TCC), and is signed with a self-signed cert.

## Build / run

The project is generated with **XcodeGen** from `project.yml`; never edit `LingoPop.xcodeproj` directly — it's regenerated on every build.

```bash
./build.sh              # xcodegen + xcodebuild + install to ~/Applications/LingoPop.app
./build.sh run          # build, kill existing instance, open the new one
```

Why `build.sh` and not raw `xcodebuild`:
- The project lives under `~/Documents/...` which has Apple File Provider sync — extended attributes leak into the build dir and break `codesign` ("resource fork, Finder information, or similar detritus not allowed"). `build.sh` builds into `/tmp/lingo-pop-build`, then copies the `.app` to `~/Applications/LingoPop.app` (a stable, non-synced, Finder-visible path), strips xattrs, and re-signs.
- TCC (Accessibility permission) is bound to the path + code requirement. Always installing to `~/Applications/LingoPop.app` keeps the grant alive across rebuilds.

One-time machine setup (only when starting on a new Mac, or after a cert refresh):

```bash
./scripts/setup-cert.sh   # creates a self-signed "LingoPop Dev" code-signing cert in the login keychain
```

Why a real cert (not `--sign -`): ad-hoc signing produces a fresh CDHash per build, which invalidates the TCC entry on every rebuild. A stable cert ties the TCC grant to the cert identity, so the Accessibility prompt only happens once. `build.sh` detects the cert and falls back to ad-hoc with a warning if it's missing.

Regenerating the app icon (rarely):

```bash
swift scripts/generate-icon.swift /tmp/icon.png
# then re-slice through sips and replace files in App/Assets.xcassets/AppIcon.appiconset/
```

No test target. No linter.

### Release builds (distribution)

`scripts/release.sh` produces signed artifacts in `dist/` for shipping. It's separate from `build.sh` (which is dev-only: Debug, host arch only).

```bash
./scripts/release.sh                       # universal (arm64 + x86_64), version from project.yml
./scripts/release.sh 0.2.0                 # bump version inline (passes MARKETING_VERSION / CURRENT_PROJECT_VERSION to xcodebuild)
./scripts/release.sh 0.2.0 --arch arm64    # Apple Silicon only
./scripts/release.sh 0.2.0 --arch x86_64   # Intel only
./scripts/release.sh 0.2.0 --no-dmg        # skip the .dmg, keep only .zip
./scripts/release.sh 0.2.0 --no-zip        # skip the .zip, keep only .dmg
```

Outputs `dist/LingoPop-<version>-mac-<arch>.{zip,dmg}` where `<arch>` is `universal`, `arm64`, or `x86_64`. The dmg uses a `/Applications` symlink so the user can drag-install.

Build config in `project.yml`:
- Base settings declare `ARCHS = arm64 x86_64` and `VALID_ARCHS = arm64 x86_64`.
- `Debug` has `ONLY_ACTIVE_ARCH = YES` so dev iteration stays fast (host arch only).
- `Release` has `ONLY_ACTIVE_ARCH = NO` so the universal slices are actually built.
- `release.sh` re-asserts `ARCHS` / `ONLY_ACTIVE_ARCH` on the command line to support arch overrides.

After packaging, `release.sh` verifies the slice list with `lipo -archs` and prints it — sanity-check this output if a download report claims missing arch support.

The minimum macOS is set in two places (must match): `MACOSX_DEPLOYMENT_TARGET` under `settings.base` and `deploymentTarget.macOS` under `options`. Currently both 13.0. Lowering it requires removing SwiftUI 13.0+ APIs (`.formStyle(.grouped)`, `LabeledContent`, `SMAppService.mainApp`).

### Public releases via GitHub Actions

Source lives in a **private** repo (`slucheninov/lingo-pop`); built `.app` artifacts and product docs ship from a separate **public** repo (`slucheninov/lingopop`).

Two flows:
- **Tag push** (`v0.2.0`) in private → `.github/workflows/release.yml` builds on `macos-14`, runs `scripts/release.sh`, then uses a fine-grained PAT to `gh release create` in the public repo. CI signs ad-hoc (no Apple Developer Program), so end users get a one-time Gatekeeper warning.
- **Doc sync** (manual) — `./scripts/sync-public-repo.sh` clones the public repo, rsyncs `public-repo/` into it (preserving any screenshot binaries already committed there), commits, and pushes. Run this whenever README / CHANGELOG / issue templates change.

The public repo's content (README, LICENSE, PRIVACY, CHANGELOG, issue templates, screenshots placeholder) lives under `public-repo/` here — that's the source of truth, the public repo is downstream.

Configuration:
- Private repo secret `PUBLIC_REPO_TOKEN` — fine-grained PAT with `Contents: Read and write` on the public repo only.
- Private repo variable `PUBLIC_REPO` — `owner/repo` of the public repo.

End-to-end setup is in `RELEASING.md`.

## Architecture

### Hotkey → result lifecycle

1. **HotkeyManager** (`Core/HotkeyManager.swift`) registers global hotkeys via the [HotKey](https://github.com/soffes/HotKey) SPM package (Carbon `RegisterEventHotKey` under the hood). It holds a `[AIOperation: HotKey]` so each operation can have its own shortcut.
2. **AppDelegate.handleHotkey(operation:)** captures selected text via **TextCapture** (`Core/TextCapture.swift`): save pasteboard → post `Cmd+C` as a `CGEvent` → poll pasteboard changeCount until it ticks or 300 ms timeout → restore original pasteboard. This is the reason Accessibility permission is required.
3. **resolveTargetLanguage** runs `LanguageDetector` (`NLLanguageRecognizer`) on the captured text if `useAutoDetect` is on, then looks the detected source up in `settingsStore.languagePairs` to pick a target; falls back to `targetLanguage` otherwise. Only `.translate` triggers auto-detect.
4. **runOperation** picks the active provider, builds a `ProviderConfig`, calls `TranslationService.execute(text:operation:config:)`. If the call throws an error that `shouldRetryWithFallback` deems retry-able (429, 5xx, network), it retries once with `settingsStore.fallback(for: primary)` and marks the result `viaFallback = true`.
5. The result is shown in **PopupWindow** (a borderless `NSPanel` floating above all apps) hosting **PopupView** (SwiftUI). Copy / Replace / Retry-with-other-provider live on `PopupState`. Replace puts the text on the pasteboard and posts `Cmd+V` to the previously focused app.

**Screen Translate lifecycle** (`AppDelegate.handleScreenTranslateHotkey()`):
1. Record `previousApp` (frontmost app before overlay), then call `CaptureOverlayWindow.runSelection()` — creates one `NSPanel` per screen (handles mixed Retina/non-Retina setups), tracks mouse via `NSEvent.addLocalMonitorForEvents` in global AppKit coordinates. Returns the selection rect in global screen coords or throws `CaptureOverlayError.cancelled`.
2. Restore `previousApp` focus and wait 150 ms so any subsequent `simulateCommandC()` goes to the right app (not LingoPop).
3. `ScreenCapture.capture(rect:)` converts from AppKit coordinates (Y-up, origin at bottom-left) to CG coordinates (Y-down) using `NSScreen.main?.frame.height`, then calls `CGWindowListCreateImage`. Requires Screen Recording TCC permission.
4. `ScreenOCR.recognize(image:)` runs Apple Vision `VNRecognizeTextRequest` and returns the joined string. If it yields no text, retry providers (vision-capable ones) are offered instead.
5. Popup shows the `.ocr(text:)` phase: recognized text + Copy / Translate / Retry buttons. OCR text is auto-copied to clipboard. `availableRetryProviders` is set to `visionCapableProviders()` so Retry sends the image directly to Codex/OpenAI/Gemini.
6. When user taps Translate, `translateScreenOCR(_:)` calls `runOperation(.screenTranslate, ...)`. The translation result is auto-copied to clipboard via `present(result:source:viaFallback:)`.

### Providers

Seven `AIProvider` implementations under `Providers/`, each conforming to:

```swift
protocol AIProvider {
    var type: ProviderType { get }
    var defaultBaseURL: String { get }
    var availableModels: [String] { get }
    var requiresApiKey: Bool { get }                  // default true
    var supportedOperations: Set<AIOperation> { get } // default: all ops
    var supportsVision: Bool { get }                  // default false; true for Codex/OpenAI/Gemini
    func execute(text:operation:config:) async throws -> String
}
```

- **ClaudeProvider** (`/v1/messages`), **OpenAIProvider** (`/v1/chat/completions`), **GeminiProvider** (`/v1beta/models/{model}:generateContent`) handle all operations including `.screenTranslate`, and declare `supportsVision = true` — they can receive the captured image directly and do combined OCR + translation in one step.
- **GoogleFreeProvider** uses the unofficial `translate.googleapis.com/translate_a/single` endpoint — no API key, only supports `.translate`.
- **GoogleCloudProvider** uses the official Cloud Translation v2 API (`?key=...`) — only `.translate`. Supports an optional `Referer` header for keys with HTTP-referrer restriction.
- **DeepLProvider** and **MicrosoftTranslatorProvider** — translate-only.

`TranslationService` (`Core/TranslationService.swift`) just holds the dict `[ProviderType: AIProvider]` and forwards calls. It also exposes the dict to the UI so the Provider tab can render model presets and supportedOperations badges per provider.

When adding a new provider: add a case to `ProviderType` (`Models/ProviderConfig.swift`), implement `AIProvider`, register it in `TranslationService.providers`, and add a default entry in `SettingsStore.makeDefault()` so it has a baseURL/model on first launch.

### Persistence layout

Three distinct stores, each with a specific reason:

- **`SettingsStore`** (`Core/SettingsStore.swift`) — `@Published` fields for everything except API keys. Persisted both to `UserDefaults` (local fallback) and to `~/Library/Mobile Documents/com~apple~CloudDocs/LingoPop/settings.json` (iCloud Drive folder) when `iCloudSync` is on. `installAutoSave()` debounces `@Published` changes 200 ms before writing. `installCloudPolling()` re-reads the cloud file every 30 s; if `mtime` advanced (another Mac wrote it), it calls `apply(_:)` with `suppressAutoSave = true` so the reload doesn't trigger a save loop.
- **`TranslationHistoryStore`** (`Core/TranslationHistoryStore.swift`) — last N entries, same dual UserDefaults + iCloud layout.
- **`KeychainService` / `SecretStorage`** (`Core/`) — `KeychainService` is just a thin facade over `SecretStorage`, which stores API keys in `~/Library/Application Support/LingoPop/secrets.dat` (AES-GCM via CryptoKit, key derived from `SHA256(IOPlatformUUID + salt)`). **Do not put keys in iCloud-synced settings.json.** macOS Keychain is intentionally not used: with self-signed builds it would re-prompt for password on every rebuild. The `secrets.dat` file is machine-bound and 0600.

`hasApiKey` reads a UserDefaults flag (`LingoPop.secretHas.*`) without touching the encrypted file, so provider switching in the UI doesn't trigger decryption.

### iCloud sync — what NOT to use

The user has no Apple Developer Program membership, so we can't use `NSUbiquitousKeyValueStore` or CloudKit (they require entitlements + provisioning). Anything synced must go through plain file writes to the iCloud Drive folder. Reading `CloudStorage.rootURL == nil` means iCloud Drive is off on this Mac; everything degrades to UserDefaults-only.

### UI

- `App/LingoPop.swift` is the `@main` entry: creates `AppDelegate`, sets `.accessory` activation policy.
- `AppDelegate` is `@MainActor`, holds all the singletons (settingsStore, historyStore, popup, statusController, hotkeyManager, translationService), subscribes via Combine to `settingsStore.$hotkeys`, `$launchAtLogin`, `$iCloudSync`, `$maxHistoryCount` to keep dependent systems in sync.
- `installMainMenu()` builds a fake `NSApp.mainMenu` with App + Edit menus. Even though the app has no windows by default, this is required so `Cmd+V` etc. work in TextField inside Settings (LSUIElement apps don't get a main menu by default → no responder chain → no Cmd+V).
- **PopupWindow** uses an `NSPanel` with `.borderless + .nonactivatingPanel` so it floats over the user's current app without stealing focus. Click-outside / Esc closes it via `NSEvent.addGlobalMonitorForEvents` + a local key monitor.
- **StatusItemController** swaps the menu-bar icon between idle (globe), translating (spinning arrows), and error (red triangle, auto-resets after 3 s).
- **HotkeyRecorderField** (`UI/HotkeyRecorderField.swift`) is an `NSViewRepresentable` wrapping a custom `NSButton` that intercepts `keyDown` while recording, builds a `HotkeyConfig` from the `event.keyCode` and modifier flags.

### Screen Translate components

- **`UI/CaptureOverlayWindow.swift`** — one `NSPanel` per `NSScreen.screens`. Uses `NSEvent.addLocalMonitorForEvents` (requires `NSApp.activate`) to track mouse in global AppKit coords via `NSEvent.mouseLocation`. `OverlayDrawingView` converts global → local coords using `screenOrigin` (the screen's `frame.origin`). After selection, `previousApp?.activate(options: .activateIgnoringOtherApps)` + 150 ms sleep restores focus so subsequent `simulateCommandC()` isn't misdirected to LingoPop.
- **`Core/ScreenCapture.swift`** — `CGWindowListCreateImage` with AppKit↔CG Y-flip (`NSScreen.main?.frame.height - rect.maxY`). Returns `CGImage`; throws `ScreenCaptureError.tooSmall` for areas under 10×10 px. Requires Screen Recording TCC.
- **`Core/ScreenOCR.swift`** — `VNRecognizeTextRequest` via Vision framework. Joins recognized strings with spaces; throws if result is empty.
- **`Core/PermissionsManager.swift`** — `isScreenRecordingGranted()` = `CGPreflightScreenCaptureAccess()`; `requestScreenCaptureAccess()` = `CGRequestScreenCaptureAccess()` on macOS 15+ (auto-prompts on first `CGWindowListCreateImage` call on earlier versions).
- **`UI/SettingsView.swift`** — `MainSettingsTab` has a Screen Recording permission section mirroring the Accessibility section: shows green checkmark when granted, or "Request" + "Open Settings" buttons when denied.

### Settings UI structure

`SettingsView` is a `TabView` with four tabs: Main, Providers, Shortcuts, About. The Providers tab is an `HStack` with a sidebar `List(selection:)` on the left and a per-provider detail form on the right (System Settings → Internet Accounts pattern). The "Active" provider is set with a dedicated button, distinct from "selected for editing in the sidebar" — these are intentionally separate concepts.

## Things to be careful about

- After editing `project.yml`, `build.sh` always regens the xcodeproj — don't be surprised if Xcode complains about a project-file change.
- The Apple File Provider sync on this repo will silently re-attach `com.apple.FinderInfo` xattrs to source files. Don't build the `.app` in-place — `build.sh` puts it in `/tmp` for a reason.
- `@Published` auto-save uses `.dropFirst()` on each publisher (not `dropFirst(N)` on a merge) so the initial emit doesn't trigger a save. When you add a new `@Published` to `SettingsStore`, also add it to `installAutoSave()` and to `Persisted` / `apply(_:)` / `save()` — easy to forget one.
- Settings persistence is **per-provider** for `fallbacks`, `providers[ProviderType]`, and `apiKey.*` — when the active provider changes, those keep their own values. Don't reintroduce a global `fallbackProvider`.
- Stable code-signing cert is load-bearing for TCC. If users are getting Accessibility prompts on every rebuild, `LingoPop Dev` is probably missing from their keychain.
- Screen Recording TCC is also bound to the cert identity. Same logic applies: ad-hoc re-signing invalidates the grant; keep the `LingoPop Dev` cert stable.
- `CaptureOverlayWindow` requires `NSApp.activate(ignoringOtherApps: true)` for `addLocalMonitorForEvents` to receive mouse events. This leaves LingoPop as the active app — always restore `previousApp` focus (+ 150 ms yield) before any subsequent `simulateCommandC()` call, otherwise Cmd+C fires in LingoPop rather than the user's app.
- `PopupState.Phase` has an `.ocr(text:)` case used only by Screen Translate. The Replace button is hidden when `result.operation == .screenTranslate` (can't paste into an image). The Rewrite/Explain buttons remain — they work on the translated text.

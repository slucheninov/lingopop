# Screenshots

All screenshots are generated via native SwiftUI/AppKit rendering:

```bash
./scripts/generate-screenshots.sh
```

This compiles `scripts/render-screenshots.swift` (with `UI/HistoryMenuItemView.swift` for the menu) and writes PNGs using real `.regularMaterial`, `.formStyle(.grouped)`, `.bordered` buttons, and `NSVisualEffectView(material: .menu)`.

## Screenshot inventory

| Filename | Description |
|---|---|
| `popup.png` | Translation result popup over gradient desktop |
| `menu.png` | Menu-bar dropdown showing operations and recent history |
| `popup-screen.png` | Screen Translate OCR phase popup (Copy / Translate / Retry) |
| `settings-main.png` | Settings → Main tab (language, popup, limits, startup, iCloud, permissions) |
| `settings-providers.png` | Settings → Providers tab (sidebar + Claude detail) |
| `settings-shortcuts.png` | Settings → Shortcuts tab (5 operations with hotkey pills) |
| `settings-about.png` | Settings → About tab (app icon, version, Privacy Policy link) |
| `history.png` | History window with search bar and fixture translation entries |

## Old workflow (replaced)

`scripts/capture-screenshots.sh` previously used `screencapture` with a timer delay.
It has been replaced by the programmatic approach above.

# Screenshots

Drop PNGs here and reference them from `../../README.md`. Recommended sizes:

| Filename | What to capture | Approx. width |
|---|---|---|
| `popup.png` | The translation popup over some sample text | 1040–1240 px (will render at ~520) |
| `popup-screen.png` | Screen Translate OCR popup showing recognized text with Copy / Translate / Retry buttons | 800–1000 px |
| `settings.png` | Settings window, ideally the Providers tab | 1440 px (renders at ~720) |
| `menu.png` | Menu-bar drop-down showing the operations | 600 px |

To take a clean screenshot:

```bash
# capture a window with a small drop shadow, save as PNG
screencapture -W -o ~/Desktop/popup.png
```

Use the `-x` flag to suppress the camera-shutter sound:

```bash
screencapture -W -o -x ~/Desktop/popup.png
```

#!/usr/bin/env bash
# Generates all public README screenshots via native SwiftUI/AppKit rendering.
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$PROJECT_DIR/docs/screenshots"
BUILD="/tmp/lingopop-screenshot-gen"
mkdir -p "$OUT_DIR"
swiftc -O -o "$BUILD" \
  "$PROJECT_DIR/UI/HistoryMenuItemView.swift" \
  "$PROJECT_DIR/scripts/render-screenshots.swift" \
  -framework AppKit -framework SwiftUI
"$BUILD" "$OUT_DIR"
echo "Done. Screenshots written to $OUT_DIR"
ls -la "$OUT_DIR"/*.png

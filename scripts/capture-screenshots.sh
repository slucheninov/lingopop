#!/usr/bin/env bash
# Helper to capture screenshots for the public repo README.
#
# Uses timed full-screen capture: screencapture waits N seconds, then grabs
# the whole screen — no clicks involved, so the popup won't auto-dismiss.
# Crop each result in Preview afterwards.
#
# Usage:
#   ./scripts/capture-screenshots.sh              # 5s delay between prompts
#   ./scripts/capture-screenshots.sh --delay 8    # change the delay

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$PROJECT_DIR/public-repo/docs/screenshots"
mkdir -p "$OUT_DIR"

DELAY=5
while [[ $# -gt 0 ]]; do
    case "$1" in
        --delay) DELAY="$2"; shift 2 ;;
        -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) shift ;;
    esac
done

capture() {
    local name="$1"
    local prompt="$2"
    local target="$OUT_DIR/${name}.png"
    cat <<EOF

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
▶  ${name}.png
   $prompt
   When you press Enter, you have ${DELAY}s before the screen is captured.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF
    read -rp "Press Enter to start the ${DELAY}s timer..."
    /usr/sbin/screencapture -T "$DELAY" -o -x "$target"
    if [[ -s "$target" ]]; then
        echo "✓ saved $target  (crop it in Preview before committing)"
    else
        echo "✗ no file written"
    fi
}

cat <<EOF
Capturing screenshots for the public repo README.

Delay between prompts: ${DELAY}s

Before starting, make sure LingoPop is running and Accessibility is granted.
EOF

capture popup    "Bring up a translation popup (select text in any app → press your Translate hotkey)."
capture settings "Open LingoPop Settings → Providers tab."
capture menu     "Click the LingoPop menu-bar icon to open the dropdown."

cat <<EOF

Done.

Next steps:
  1. Open each PNG in Preview, crop (Tools → Show Markup Toolbar → Crop).
  2. Save back into public-repo/docs/screenshots/.
  3. ./scripts/sync-public-repo.sh "Add screenshots"
EOF

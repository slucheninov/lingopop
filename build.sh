#!/usr/bin/env bash
# LingoPop build wrapper.
# We build into /tmp because the project lives in a sync'd Documents folder
# (Apple File Provider attaches xattrs that break codesign).

set -euo pipefail

BUILD_DIR=$(mktemp -d)
trap 'rm -rf "$BUILD_DIR"' EXIT
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"

cd "$PROJECT_DIR"

xcodegen generate

xcodebuild \
    -project LingoPop.xcodeproj \
    -scheme LingoPop \
    -configuration Debug \
    -derivedDataPath "$BUILD_DIR" \
    build

SRC_APP="$BUILD_DIR/Build/Products/Debug/LingoPop.app"
DEST_APP="$HOME/Applications/LingoPop.app"

mkdir -p "$HOME/Applications"
pkill -x LingoPop || true
sleep 0.3
rm -rf "$DEST_APP"
cp -R "$SRC_APP" "$DEST_APP"
xattr -cr "$DEST_APP"
if security find-certificate -c "LingoPop Dev" >/dev/null 2>&1; then
    SIGN_IDENTITY="LingoPop Dev"
    SIGN_OPTS=()   # NOTE: no --options runtime: hardened-runtime library validation rejects the Xcode debug dylib / non-matching Team ID with a self-signed cert
else
    echo "Warning: 'LingoPop Dev' cert missing — falling back to ad-hoc. Run ./scripts/setup-cert.sh to fix Accessibility persistence."
    SIGN_IDENTITY="-"
    SIGN_OPTS=()
fi
FRAMEWORKS_DIR="$DEST_APP/Contents/Frameworks"
if [ -d "$FRAMEWORKS_DIR" ]; then
    find "$FRAMEWORKS_DIR" -name "*.framework" -o -name "*.dylib" | while read component; do
        codesign --force --sign "$SIGN_IDENTITY" --timestamp=none "$component"
    done
fi
codesign --force --sign "$SIGN_IDENTITY" ${SIGN_OPTS[@]+"${SIGN_OPTS[@]}"} --entitlements "$PROJECT_DIR/App/LingoPop.entitlements" "$DEST_APP" 2>&1 | tail -3

case "${1:-}" in
    run)
        open "$DEST_APP"
        ;;
    "")
        echo "Installed: $DEST_APP"
        ;;
    *)
        echo "Usage: $0 [run]"
        exit 1
        ;;
esac

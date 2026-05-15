#!/usr/bin/env bash
# Build a Release LingoPop.app and package it for distribution.
#
# Usage:
#   ./scripts/release.sh                       # universal (arm64 + x86_64), version from project.yml
#   ./scripts/release.sh 0.2.0                 # universal, version override
#   ./scripts/release.sh 0.2.0 --arch arm64    # arm64 only
#   ./scripts/release.sh 0.2.0 --arch x86_64   # x86_64 only (Intel)
#   ./scripts/release.sh 0.2.0 --no-dmg        # skip .dmg, only .zip
#   ./scripts/release.sh 0.2.0 --no-zip        # skip .zip, only .dmg

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

VERSION=""
ARCHS_FLAG="arm64 x86_64"
ARCH_LABEL="universal"
MAKE_DMG=1
MAKE_ZIP=1

while [[ $# -gt 0 ]]; do
    case "$1" in
        --arch)
            ARCHS_FLAG="$2"
            ARCH_LABEL="$2"
            shift 2 ;;
        --no-dmg) MAKE_DMG=0; shift ;;
        --no-zip) MAKE_ZIP=0; shift ;;
        -h|--help)
            grep '^#' "$0" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        *)
            if [[ -z "$VERSION" ]]; then VERSION="$1"; else
                echo "Unknown argument: $1" >&2; exit 1
            fi
            shift ;;
    esac
done

if [[ -z "$VERSION" ]]; then
    VERSION=$(awk '/CFBundleShortVersionString:/ { gsub(/"/,"",$2); print $2 }' project.yml)
    if [[ -z "$VERSION" ]]; then VERSION="0.0.0"; fi
fi

echo "→ Version: $VERSION"
echo "→ Architecture(s): $ARCHS_FLAG"

xcodegen generate

BUILD_DIR="/tmp/lingo-pop-release"
rm -rf "$BUILD_DIR"

xcodebuild \
    -project LingoPop.xcodeproj \
    -scheme LingoPop \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR" \
    ARCHS="$ARCHS_FLAG" \
    VALID_ARCHS="$ARCHS_FLAG" \
    ONLY_ACTIVE_ARCH=NO \
    MARKETING_VERSION="$VERSION" \
    CURRENT_PROJECT_VERSION="$VERSION" \
    build

SRC_APP="$BUILD_DIR/Build/Products/Release/LingoPop.app"
if [[ ! -d "$SRC_APP" ]]; then
    echo "Build did not produce $SRC_APP" >&2
    exit 1
fi

DIST_DIR="$PROJECT_DIR/dist"
mkdir -p "$DIST_DIR"

STAGE_DIR="$(mktemp -d)"
trap 'rm -rf "$STAGE_DIR"' EXIT
STAGED_APP="$STAGE_DIR/LingoPop.app"
cp -R "$SRC_APP" "$STAGED_APP"
xattr -cr "$STAGED_APP"

if security find-certificate -c "LingoPop Dev" >/dev/null 2>&1; then
    SIGN_IDENTITY="LingoPop Dev"
else
    echo "Warning: 'LingoPop Dev' cert missing — signing ad-hoc. Run scripts/setup-cert.sh."
    SIGN_IDENTITY="-"
fi
codesign --force --deep \
    --sign "$SIGN_IDENTITY" \
    --entitlements "$PROJECT_DIR/App/LingoPop.entitlements" \
    "$STAGED_APP" 2>&1 | tail -3

echo "→ Verifying architectures:"
lipo -archs "$STAGED_APP/Contents/MacOS/LingoPop"

BASENAME="LingoPop-${VERSION}-mac-${ARCH_LABEL}"

if [[ "$MAKE_ZIP" -eq 1 ]]; then
    ZIP_PATH="$DIST_DIR/${BASENAME}.zip"
    rm -f "$ZIP_PATH"
    (cd "$STAGE_DIR" && /usr/bin/ditto -ck --keepParent LingoPop.app "$ZIP_PATH")
    echo "→ Wrote $ZIP_PATH"
fi

if [[ "$MAKE_DMG" -eq 1 ]]; then
    DMG_PATH="$DIST_DIR/${BASENAME}.dmg"
    rm -f "$DMG_PATH"
    DMG_STAGE="$(mktemp -d)"
    cp -R "$STAGED_APP" "$DMG_STAGE/"
    ln -s /Applications "$DMG_STAGE/Applications"
    hdiutil create \
        -volname "LingoPop ${VERSION}" \
        -srcfolder "$DMG_STAGE" \
        -ov -format UDZO \
        "$DMG_PATH" >/dev/null
    rm -rf "$DMG_STAGE"
    echo "→ Wrote $DMG_PATH"
fi

echo ""
echo "Done. Artifacts in $DIST_DIR:"
ls -lh "$DIST_DIR" | grep "$VERSION" || ls -lh "$DIST_DIR"

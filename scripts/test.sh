#!/usr/bin/env bash
# Generates the Xcode project and runs the host-less XCTest suite.
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate
xcodebuild test \
  -project LingoPop.xcodeproj \
  -scheme LingoPop \
  -destination 'platform=macOS' \
  -derivedDataPath "${DERIVED_DATA:-/tmp/lingopop-test}"

#!/usr/bin/env bash
# build-dmg.sh — local Release archive + .dmg builder
# Usage: ./scripts/build-dmg.sh [version]
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
VERSION="${1:-dev}"
BUILD_DIR="$ROOT/build"
ARCHIVE_PATH="$BUILD_DIR/iPScanner.xcarchive"
DMG_DIR="$BUILD_DIR/dmg"
DMG_PATH="$BUILD_DIR/iPScanner-$VERSION.dmg"

command -v xcodegen >/dev/null || { echo "xcodegen not found. brew install xcodegen"; exit 1; }
command -v create-dmg >/dev/null || { echo "create-dmg not found. brew install create-dmg"; exit 1; }

echo "==> Refreshing OUI database (best effort)"
curl -fsSL --max-time 60 https://standards-oui.ieee.org/oui/oui.txt \
  -o iPScanner/Resources/oui.txt || echo "    (could not refresh, using bundled copy)"

echo "==> xcodegen generate"
xcodegen generate

echo "==> Cleaning $BUILD_DIR"
rm -rf "$BUILD_DIR"
mkdir -p "$DMG_DIR"

echo "==> Archiving Release"
xcodebuild \
  -scheme iPScanner \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  -destination 'generic/platform=macOS' \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM="" \
  archive

APP_SRC="$ARCHIVE_PATH/Products/Applications/iPScanner.app"
[[ -d "$APP_SRC" ]] || { echo "build failed: $APP_SRC missing"; exit 1; }

cp -R "$APP_SRC" "$DMG_DIR/"

echo "==> Packaging .dmg"
create-dmg \
  --volname "iPScanner $VERSION" \
  --window-size 540 380 \
  --icon-size 96 \
  --icon "iPScanner.app" 140 180 \
  --app-drop-link 380 180 \
  "$DMG_PATH" \
  "$DMG_DIR/" \
  || true

[[ -f "$DMG_PATH" ]] || { echo "create-dmg failed"; exit 1; }

echo
echo "✅ DMG ready: $DMG_PATH"
ls -lh "$DMG_PATH"

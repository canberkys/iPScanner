#!/usr/bin/env bash
# Signed release pipeline shared by local builds and GitHub Actions.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${1:?Usage: build-dmg.sh X.Y.Z}"
VERSION="${VERSION#v}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Expected X.Y.Z version' >&2; exit 1; }
# Fail before signing if the tag and project.yml disagree or Sparkle would skip this build.
python3 scripts/check-release-version.py "$VERSION"
: "${SIGNING_IDENTITY:?Set SIGNING_IDENTITY to your Developer ID Application identity}"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to a notarytool keychain profile}"
NOTARY_ARGS=(--keychain-profile "$NOTARY_PROFILE")
if [[ -n "${NOTARY_KEYCHAIN:-}" ]]; then NOTARY_ARGS+=(--keychain "$NOTARY_KEYCHAIN"); fi
[[ "$SIGNING_IDENTITY" == 'Developer ID Application:'* || "$SIGNING_IDENTITY" =~ ^[[:xdigit:]]{40}$ ]] || { echo 'A Developer ID Application identity is required' >&2; exit 1; }
command -v xcodegen >/dev/null
BUILD_DIR="${RELEASE_BUILD_DIR:-$PWD/build/release-$VERSION}"
mkdir -p "$BUILD_DIR"
APP="$BUILD_DIR/iPScanner.xcarchive/Products/Applications/iPScanner.app"
DMG="$BUILD_DIR/iPScanner-v$VERSION.dmg"
# Refuse to reuse old package contents or overwrite a previous release artifact.
[[ ! -e "$BUILD_DIR/iPScanner.xcarchive" && ! -e "$DMG" ]] || { echo "Use a fresh build directory: $BUILD_DIR" >&2; exit 1; }
python3 scripts/build-vendor-db.py --check
xcodegen generate
COMMON=(-configuration Release -destination 'generic/platform=macOS' 'ARCHS=arm64 x86_64' ONLY_ACTIVE_ARCH=NO CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= ENABLE_HARDENED_RUNTIME=YES "MARKETING_VERSION=$VERSION")
xcodebuild test -scheme iPScanner -configuration Debug -destination 'platform=macOS' -derivedDataPath "$BUILD_DIR/tests" CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=
xcodebuild -scheme iPScanner "${COMMON[@]}" -derivedDataPath "$BUILD_DIR/app-products" -archivePath "$BUILD_DIR/iPScanner.xcarchive" archive
# Separate products directory prevents the case-insensitive product-name collision too.
xcodebuild -scheme ipscanner "${COMMON[@]}" "SYMROOT=$BUILD_DIR/cli-products" build
CLI="$BUILD_DIR/cli-products/Release/ipscanner-cli"
test -x "$CLI"
mkdir -p "$APP/Contents/Helpers"
cp "$CLI" "$APP/Contents/Helpers/ipscanner"
# Sign from the inside out. Never place ipscanner alongside iPScanner in MacOS/.
codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$APP/Contents/Helpers/ipscanner"
./scripts/sign-sparkle.sh "$APP"
codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$APP"
./scripts/verify-app.sh "$APP" "$VERSION"
ditto -c -k --keepParent "$APP" "$BUILD_DIR/iPScanner-notary.zip"
notarize() {
    local artifact="$1" report="$2"
    xcrun notarytool submit "$artifact" "${NOTARY_ARGS[@]}" --wait --timeout 20m --output-format json > "$report"
    # A submission completing is not sufficient: Apple must explicitly accept it.
    python3 - "$report" <<'PYJSON'
import json, sys
with open(sys.argv[1]) as f:
    result = json.load(f)
if result.get("status") != "Accepted":
    raise SystemExit("Notarization not accepted: " + str(result))
PYJSON
}
notarize "$BUILD_DIR/iPScanner-notary.zip" "$BUILD_DIR/app-notary.json"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=2 "$APP"
./scripts/create-dmg.sh "$APP" "$DMG" "iPScanner $VERSION"
codesign --timestamp --sign "$SIGNING_IDENTITY" "$DMG"
notarize "$DMG" "$BUILD_DIR/dmg-notary.json"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
hdiutil verify "$DMG"
codesign --verify --verbose=2 "$DMG"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
# Check exactly the app that will be delivered, after the DMG round trip.
MOUNT="$BUILD_DIR/verify-mount"
mkdir -p "$MOUNT"
hdiutil attach -readonly -nobrowse -mountpoint "$MOUNT" "$DMG"
trap 'hdiutil detach "$MOUNT" >/dev/null 2>&1 || true' EXIT
./scripts/verify-app.sh "$MOUNT/iPScanner.app" "$VERSION"
xcrun stapler validate "$MOUNT/iPScanner.app"
hdiutil detach "$MOUNT"
trap - EXIT
(cd "$BUILD_DIR" && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256")
export SPARKLE_BIN="$BUILD_DIR/app-products/SourcePackages/artifacts/sparkle/Sparkle/bin"
./scripts/generate-update-feed.sh "$DMG" "$VERSION" "$BUILD_DIR/update-feed"
echo "Verified release: $DMG"

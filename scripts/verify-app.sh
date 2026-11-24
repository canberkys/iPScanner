#!/usr/bin/env bash
set -euo pipefail
APP="${1:?Usage: verify-app.sh APP VERSION}"
VERSION="${2:?Expected version required}"
GUI="$APP/Contents/MacOS/iPScanner"
test -f "$APP/Contents/Resources/Sparkle-LICENSE.txt"
test -d "$APP/Contents/Frameworks/Sparkle.framework"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$APP/Contents/Info.plist")" == https://raw.githubusercontent.com/canberkys/iPScanner/main/appcast.xml ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$APP/Contents/Info.plist")" == 3OCQ09Gs7qW5jnR+Om4W1cL988qM9wsIxQJagVpGS1s= ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :SUVerifyUpdateBeforeExtraction' "$APP/Contents/Info.plist")" == true ]]
CLI="$APP/Contents/Helpers/ipscanner"
"$(dirname "$0")/check-bundle-layout.sh" "$APP"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Contents/Info.plist")" == iPScanner ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")" == "$VERSION" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$APP/Contents/Info.plist")" == 14.4 ]]
! cmp -s "$GUI" "$CLI" || { echo 'GUI was overwritten by CLI (#10)' >&2; exit 1; }
for BIN in "$GUI" "$CLI"; do
    ARCHITECTURES=" $(/usr/bin/lipo -archs "$BIN") "
    [[ "$ARCHITECTURES" == *" arm64 "* && "$ARCHITECTURES" == *" x86_64 "* ]] || { echo "Missing universal slice: $BIN" >&2; exit 1; }
    codesign --verify --strict --verbose=2 "$BIN"
    DETAILS="$(codesign -dv --verbose=4 "$BIN" 2>&1)"
    [[ "$DETAILS" == *'Authority=Developer ID Application:'* ]]
    [[ "$DETAILS" == *'runtime'* ]]
done
codesign --verify --deep --strict --verbose=2 "$APP"
"$CLI" --help >/dev/null

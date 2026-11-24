#!/usr/bin/env bash
# Only call after the final DMG is signed, notarized and stapled.
set -euo pipefail
DMG="${1:?Final DMG required}"
VERSION="${2:?Version required}"
DEST="${3:?Output directory required}"
: "${SPARKLE_BIN:?Path to the pinned Sparkle bin directory required}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
test -f "$DMG"
xcrun stapler validate "$DMG"
codesign --verify --verbose=2 "$DMG"
mkdir -p "$DEST"
[[ ! -e "$DEST/$(basename "$DMG")" ]]
ditto "$DMG" "$DEST/$(basename "$DMG")"
cp "docs/release-notes-$VERSION.md" "$DEST/$(basename "${DMG%.dmg}").md"
KEY_ARGS=(--account ipscanner)
if [[ -n "${SPARKLE_PRIVATE_KEY_FILE:-}" ]]; then KEY_ARGS=(--ed-key-file "$SPARKLE_PRIVATE_KEY_FILE"); fi
"$SPARKLE_BIN/generate_appcast" "${KEY_ARGS[@]}" --maximum-deltas 0 --embed-release-notes \
    --download-url-prefix "https://github.com/canberkys/iPScanner/releases/download/v$VERSION/" \
    --link "https://github.com/canberkys/iPScanner/releases/tag/v$VERSION" "$DEST"
# Builds below 5 (1.3.1 and older) trust the previous EdDSA key, which was lost.
# They would reject archives signed with the current key, so for them every item
# is informational: Sparkle shows the notes and a link to the release page.
python3 - "$DEST/appcast.xml" <<'PY'
import sys, xml.etree.ElementTree as ET
path = sys.argv[1]
KEY_ROTATION_BUILD = 5
marker = ('<sparkle:informationalUpdate><sparkle:belowVersion>%d</sparkle:belowVersion>'
          '</sparkle:informationalUpdate>' % KEY_ROTATION_BUILD)
text = open(path, encoding='utf-8').read()
count = text.count('</item>')
assert count, 'No update generated'
if marker not in text:
    text = text.replace('</item>', '    ' + marker + '\n        </item>')
    open(path, 'w', encoding='utf-8').write(text)
root = ET.parse(path); ns = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'
items = root.findall('./channel/item')
assert len(items) == count
for item in items:
    enc = item.find('enclosure')
    assert enc is not None and enc.get(ns+'edSignature'), 'Missing EdDSA signature'
    assert enc.get('url', '').startswith('https://github.com/canberkys/iPScanner/releases/download/'), 'Unexpected download host'
    assert int(enc.get('length','0')) > 0
    assert int(item.findtext(ns+'version')) >= KEY_ROTATION_BUILD, 'Build must be signed with the current key'
    below = item.findtext(ns+'informationalUpdate/'+ns+'belowVersion')
    assert below == str(KEY_ROTATION_BUILD), 'Missing informational update for builds below 5'
    assert item.findtext('link', '').startswith('https://github.com/canberkys/iPScanner/releases/tag/v'), 'Missing release link'
print('Signed appcast generated. Publish the DMG before promoting this feed.')
PY

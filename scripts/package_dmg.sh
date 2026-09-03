#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
APP_DIR="$PROJECT_DIR/dist/Halofold.app"

"$PROJECT_DIR/scripts/package_app.sh" >/dev/null

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_DIR/Contents/Info.plist")"
DMG_PATH="$PROJECT_DIR/dist/Halofold-$VERSION.dmg"
STAGING_DIR="$(/usr/bin/mktemp -d /tmp/halofold-dmg.XXXXXX)"

cleanup() {
  /bin/rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

/usr/bin/ditto "$APP_DIR" "$STAGING_DIR/Halofold.app"
/bin/ln -s /Applications "$STAGING_DIR/Applications"

/usr/bin/hdiutil create \
  -volname "Halofold" \
  -srcfolder "$STAGING_DIR" \
  -format UDZO \
  -ov \
  "$DMG_PATH" >/dev/null

/usr/bin/hdiutil verify "$DMG_PATH" >/dev/null
/bin/echo "$DMG_PATH"

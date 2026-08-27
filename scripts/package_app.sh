#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
DIST_DIR="$PROJECT_DIR/dist"
APP_DIR="$DIST_DIR/Halofold.app"
DERIVED_DATA_DIR="$PROJECT_DIR/build/local-package-derived-data"
BUILT_APP="$DERIVED_DATA_DIR/Build/Products/Release/Halofold.app"

cd "$PROJECT_DIR"
xcodebuild build \
  -project CodexIsland.xcodeproj \
  -scheme CodexIsland \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO

/bin/rm -rf "$APP_DIR"
/bin/mkdir -p "$DIST_DIR"
/usr/bin/ditto "$BUILT_APP" "$APP_DIR"
/usr/bin/codesign --force --sign - \
  --entitlements "$PROJECT_DIR/Resources/CodexIsland.entitlements" \
  "$APP_DIR"
/usr/bin/codesign --verify --deep --strict "$APP_DIR"
if /usr/bin/codesign -d --entitlements :- "$APP_DIR" 2>/dev/null | /usr/bin/grep -q "com.apple.security.app-sandbox"; then
  echo "Refusing to package: the local accurate build must not contain App Sandbox." >&2
  exit 1
fi

echo "$APP_DIR"

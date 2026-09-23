#!/bin/bash
# Builds a release .app (via build_app.sh) and packages it into a distributable
# .dmg — a plain drag-to-Applications disk image (app + an /Applications
# symlink), no fancy background/layout, no extra tooling required beyond the
# hdiutil that ships with macOS.
#
# The resulting .dmg is NOT notarized (no paid Apple Developer account
# involved here) — anyone opening it will see Gatekeeper's "can't be opened,
# unidentified developer" warning on first launch and need to right-click >
# Open once. That's expected, not a bug; see README.md.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
APP_NAME="ActivityTracker"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
DIST_DIR="$ROOT/dist"
STAGING_DIR="$(mktemp -d)"
trap 'rm -rf "$STAGING_DIR"' EXIT

echo "==> Building release .app (version $VERSION)"
"$ROOT/Scripts/build_app.sh" release

APP_PATH="$ROOT/build/${APP_NAME}.app"
if [ ! -d "$APP_PATH" ]; then
  echo "error: $APP_PATH not found after build" >&2
  exit 1
fi

echo "==> Staging DMG contents"
cp -R "$APP_PATH" "$STAGING_DIR/${APP_NAME}.app"
ln -s /Applications "$STAGING_DIR/Applications"

mkdir -p "$DIST_DIR"
rm -f "$DIST_DIR/$DMG_NAME"

echo "==> Creating $DMG_NAME"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DIST_DIR/$DMG_NAME"

echo "==> Done: $DIST_DIR/$DMG_NAME"

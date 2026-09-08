#!/bin/bash
# Builds the SwiftPM executable and wraps it into a proper ActivityTracker.app bundle
# (Info.plist + LSUIElement + ad-hoc code signature), since only the Command Line
# Tools are installed here (no xcodebuild / .xcodeproj available).
set -euo pipefail

CONFIG="${1:-debug}"   # debug or release
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "==> swift build -c $CONFIG"
swift build -c "$CONFIG"

BIN_PATH="$ROOT/.build/$CONFIG/ActivityTracker"
APP_DIR="$ROOT/build/ActivityTracker.app"
CONTENTS="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RES_DIR="$CONTENTS/Resources"

echo "==> Assembling $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RES_DIR"

cp "$BIN_PATH" "$MACOS_DIR/ActivityTracker"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"
printf 'APPL????' > "$CONTENTS/PkgInfo"

# Carry over any SwiftPM resource bundles (none expected for GRDB's default
# system-sqlite3 target, but harmless to check).
shopt -s nullglob
for bundle in "$ROOT/.build/$CONFIG"/*.bundle; do
  cp -R "$bundle" "$RES_DIR/"
done
shopt -u nullglob

SIGNING_IDENTITY="ActivityTrackerLocalSigning"
BUNDLE_ID="com.ankit.activitytracker"
IDENTITY_HASH="$(security find-identity -v -p codesigning | grep "$SIGNING_IDENTITY" | awk '{print $2}')"

if [ -n "$IDENTITY_HASH" ]; then
  # By default codesign derives the designated requirement from the code's own
  # content hash (cdhash) when the signing cert is a bare self-signed leaf with no
  # trust chain — which changes on every rebuild and defeats the whole point of a
  # "stable" identity. Pin it explicitly to the certificate instead, so TCC
  # (Accessibility/Input Monitoring/Automation) grants survive rebuilds.
  DESIGNATED_REQ="designated => identifier \"$BUNDLE_ID\" and certificate leaf = H\"$IDENTITY_HASH\""
  echo "==> Code signing (stable local identity: $SIGNING_IDENTITY, cert-pinned requirement)"
  codesign --force --deep --sign "$SIGNING_IDENTITY" --identifier "$BUNDLE_ID" -r="$DESIGNATED_REQ" "$APP_DIR"
else
  echo "==> Code signing (ad-hoc — local signing identity not found, permissions may reset on rebuild)"
  codesign --force --deep --sign - --identifier "$BUNDLE_ID" "$APP_DIR"
fi

# Install to ~/Applications too — a fixed, well-known location that Finder's "+ Add"
# picker jumps straight to (its sidebar has an Applications shortcut), and a stable
# path helps TCC permission grants survive across rebuilds.
INSTALLED_APP="$HOME/Applications/ActivityTracker.app"
mkdir -p "$HOME/Applications"
rm -rf "$INSTALLED_APP"
cp -R "$APP_DIR" "$INSTALLED_APP"

echo "==> Done: $APP_DIR"
echo "    Installed copy: $INSTALLED_APP"
echo "    Run it with: open \"$INSTALLED_APP\""

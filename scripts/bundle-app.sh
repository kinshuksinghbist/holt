#!/usr/bin/env bash
# Builds dist/Holt.app from the SwiftPM package and code-signs it.
#
# Env:
#   HOLT_VERSION        marketing version (default 0.0.0)
#   HOLT_BUILD          build number, integer (default 1)
#   HOLT_SIGN_IDENTITY  codesign identity; "-" (default) = ad-hoc
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${HOLT_VERSION:-0.0.0}"
BUILD="${HOLT_BUILD:-1}"
IDENTITY="${HOLT_SIGN_IDENTITY:--}"
APP="$ROOT/dist/Holt.app"

cd "$ROOT"
swift build -c release --product Holt
BIN_DIR="$(swift build -c release --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Holt" "$APP/Contents/MacOS/Holt"
cp Resources/Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy \
  -c "Set :CFBundleShortVersionString $VERSION" \
  -c "Set :CFBundleVersion $BUILD" \
  "$APP/Contents/Info.plist"

# SwiftPM resource bundles (none yet) go in Contents/Resources.
shopt -s nullglob
for bundle in "$BIN_DIR"/*.bundle; do
  cp -R "$bundle" "$APP/Contents/Resources/"
done

SIGN_ARGS=(--force --options runtime --entitlements Resources/Holt.entitlements --sign "$IDENTITY")
if [[ "$IDENTITY" != "-" ]]; then
  SIGN_ARGS+=(--timestamp=none)
  SIGNED_WITH="certificate $IDENTITY"
else
  SIGNED_WITH="ad-hoc signature"
fi
codesign "${SIGN_ARGS[@]}" "$APP"
codesign --verify --strict --verbose=2 "$APP"

echo "Built $APP — version $VERSION ($BUILD), $SIGNED_WITH"

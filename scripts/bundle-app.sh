#!/usr/bin/env bash
# Builds dist/Holt.app from the SwiftPM package and code-signs it (plus holt-nm-host).
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
swift build -c release --product holt-nm-host
BIN_DIR="$(swift build -c release --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Helpers" "$APP/Contents/Frameworks"
cp "$BIN_DIR/Holt" "$APP/Contents/MacOS/Holt"
cp "$BIN_DIR/holt-nm-host" "$APP/Contents/Helpers/holt-nm-host"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [[ -f Resources/Holt.icns ]]; then
  cp Resources/Holt.icns "$APP/Contents/Resources/Holt.icns"
fi
/usr/libexec/PlistBuddy \
  -c "Set :CFBundleShortVersionString $VERSION" \
  -c "Set :CFBundleVersion $BUILD" \
  "$APP/Contents/Info.plist"

# SwiftPM resource bundles go in Contents/Resources.
shopt -s nullglob
for bundle in "$BIN_DIR"/*.bundle; do
  cp -R "$bundle" "$APP/Contents/Resources/"
done

for fw in "$BIN_DIR"/*.framework; do
  cp -R "$fw" "$APP/Contents/Frameworks/"
done

if ! otool -l "$APP/Contents/MacOS/Holt" | grep -q "@executable_path/../Frameworks"; then
  install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/Holt"
fi

HELPER_SIGN_ARGS=(--force --options runtime --sign "$IDENTITY")
SIGN_ARGS=(--force --options runtime --entitlements Resources/Holt.entitlements --sign "$IDENTITY")
if [[ "$IDENTITY" != "-" ]]; then
  HELPER_SIGN_ARGS+=(--timestamp=none)
  SIGN_ARGS+=(--timestamp=none)
  SIGNED_WITH="certificate $IDENTITY"
else
  SIGNED_WITH="ad-hoc signature"
fi

for fw in "$APP/Contents/Frameworks/"*.framework; do
  codesign "${HELPER_SIGN_ARGS[@]}" "$fw"
done
codesign "${HELPER_SIGN_ARGS[@]}" "$APP/Contents/Helpers/holt-nm-host"
codesign "${SIGN_ARGS[@]}" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "Built $APP — version $VERSION ($BUILD), $SIGNED_WITH"

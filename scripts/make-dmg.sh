#!/usr/bin/env bash
# Packages dist/Holt.app into dist/Holt.dmg (drag-to-Applications) plus a SHA-256 file.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$ROOT/dist"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

cp -R "$DIST/Holt.app" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DIST/Holt.dmg"

# hdiutil is occasionally flaky on CI runners ("Resource busy"); retry a few times.
for attempt in 1 2 3; do
  if hdiutil create -volname "Holt" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DIST/Holt.dmg"; then
    break
  fi
  if [[ $attempt == 3 ]]; then
    echo "hdiutil failed 3 times" >&2
    exit 1
  fi
  sleep 5
done

(cd "$DIST" && shasum -a 256 Holt.dmg > Holt.dmg.sha256)
cat "$DIST/Holt.dmg.sha256"

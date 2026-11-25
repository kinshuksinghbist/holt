#!/usr/bin/env bash
# Stages Firefox and Chrome extension bundles in dist/extension/.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${HOLT_VERSION:-0.1.0}"
OUT="$ROOT/dist/extension"

rm -rf "$OUT"
mkdir -p "$OUT/firefox/src" "$OUT/chrome/src"

cp "$ROOT/extension/src/"*.js "$OUT/firefox/src/"
cp "$ROOT/extension/src/"*.js "$OUT/chrome/src/"

python3 - <<PY
import json
for target in ("firefox", "chrome"):
    src = f"$ROOT/extension/{target}/manifest.json"
    dst = f"$OUT/{target}/manifest.json"
    with open(src) as f:
        data = json.load(f)
    data["version"] = "$VERSION".lstrip("v").split("-")[0]
    with open(dst, "w") as f:
        json.dump(data, f, indent=2)
PY

echo "Staged extensions in $OUT (version $VERSION)"

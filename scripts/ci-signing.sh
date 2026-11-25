#!/usr/bin/env bash
# CI only. Chooses the code-signing identity and exports HOLT_SIGN_IDENTITY via $GITHUB_ENV.
#
# Without secrets: ad-hoc signing ("-").
# With MACOS_CERT_P12 (base64 .p12) + MACOS_CERT_PASSWORD: imports a (self-signed is fine)
# code-signing certificate into a throwaway keychain. A stable certificate keeps the app's
# signature stable across builds, so macOS remembers privacy permissions after updates.
set -euo pipefail

if [[ -z "${MACOS_CERT_P12:-}" ]]; then
  echo "No MACOS_CERT_P12 secret: using ad-hoc signing."
  echo "HOLT_SIGN_IDENTITY=-" >> "$GITHUB_ENV"
  exit 0
fi

KEYCHAIN="$RUNNER_TEMP/holt-signing.keychain-db"
KEYCHAIN_PASSWORD="$(uuidgen)"
CERT="$RUNNER_TEMP/holt-cert.p12"

echo "$MACOS_CERT_P12" | base64 --decode > "$CERT"
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security import "$CERT" -k "$KEYCHAIN" -P "${MACOS_CERT_PASSWORD:-}" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" > /dev/null
# shellcheck disable=SC2046
security list-keychains -d user -s "$KEYCHAIN" $(security list-keychains -d user | tr -d '"')
rm -f "$CERT"

# Self-signed certificates are listed without -v (they are not "trusted"), so take the SHA-1.
IDENTITY="$(security find-identity -p codesigning "$KEYCHAIN" | awk '/\)/ {print $2; exit}')"
if [[ -z "$IDENTITY" ]]; then
  echo "No code-signing identity found in MACOS_CERT_P12" >&2
  exit 1
fi
echo "Signing with certificate $IDENTITY"
echo "HOLT_SIGN_IDENTITY=$IDENTITY" >> "$GITHUB_ENV"

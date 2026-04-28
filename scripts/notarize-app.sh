#!/bin/bash

# Notarizes a Developer ID-signed .app bundle and staples the ticket for Gatekeeper.
#
# Prerequisites:
# - The app MUST be signed with "Developer ID Application" (not ad-hoc "-" identity).
#   CI builds that use ad-hoc signing cannot be notarized until real signing is configured.
# - App-specific password from appleid.apple.com (or ASC API credentials).
#
# Usage:
#   export APPLE_ID="you@example.com"
#   export APPLE_APP_SPECIFIC_PASSWORD="abcd-..."
#   export APPLE_TEAM_ID="XXXXXXXXXX"
#   ./scripts/notarize-app.sh "/path/to/MegaplanHepler.app"

set -euo pipefail

die() {
  echo "❌ $*" >&2
  exit 1
}

APP_PATH="${1:-}"
if [[ -z "${APP_PATH}" || ! -d "${APP_PATH}" ]]; then
  die "usage: APPLE_ID APPLE_APP_SPECIFIC_PASSWORD APPLE_TEAM_ID $0 /path/App.app"
fi

APPLE_ID="${APPLE_ID:-}"
PASS="${APPLE_APP_SPECIFIC_PASSWORD:-}"
TEAM="${APPLE_TEAM_ID:-}"

[[ -n "${APPLE_ID}" ]] || die "APPLE_ID is not set"
[[ -n "${PASS}" ]] || die "APPLE_APP_SPECIFIC_PASSWORD is not set"
[[ -n "${TEAM}" ]] || die "APPLE_TEAM_ID is not set"

BUNDLE_NAME="$(basename "${APP_PATH}")"
WORKDIR="$(cd "$(dirname "${APP_PATH}")" && pwd)"
APP_ABS="${WORKDIR}/${BUNDLE_NAME}"
ZIP_PATH="${WORKDIR}/${BUNDLE_NAME%.app}.zip"

echo "🔏 Verifying codesign…"
codesign --verify --deep --strict --verbose=2 "${APP_ABS}" || die \
  "Codesign verification failed. Use a Developer ID Application signature for notarization."

rm -f "${ZIP_PATH}"
echo "📦 Creating zip archive for submission…"
ditto -c -k --keepParent "${APP_ABS}" "${ZIP_PATH}"

echo "📮 Submitting to Apple Notary Service…"
xcrun notarytool submit "${ZIP_PATH}" \
  --apple-id "${APPLE_ID}" \
  --password "${PASS}" \
  --team-id "${TEAM}" \
  --wait

echo "📌 Stapling ticket to bundle…"
xcrun stapler staple "${APP_ABS}"

rm -f "${ZIP_PATH}"
echo "✅ Notarization complete: ${APP_ABS}"

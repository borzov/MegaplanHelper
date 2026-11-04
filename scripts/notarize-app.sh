#!/usr/bin/env bash
# Notarize a Developer ID-signed app and staple the ticket.
# Same contract as LuxControl: App Store Connect API key, staple retries, sha256 of the zip name.
#
#   APPLE_API_KEY_ID=... APPLE_API_ISSUER=... APPLE_API_KEY_PATH=/path/AuthKey.p8 \
#     ./scripts/notarize-app.sh build/export/MegaplanHepler.app build/export/MegaplanHelper-v2.1.zip
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: scripts/notarize-app.sh <app-bundle> <zip>" >&2
  exit 64
fi

app_dir="$1"
archive="$2"

if [[ -z "${APPLE_API_KEY_ID:-}" || -z "${APPLE_API_KEY_PATH:-}" ]]; then
  echo "APPLE_API_KEY_ID and APPLE_API_KEY_PATH are required" >&2
  exit 1
fi
if [[ ! -f "$APPLE_API_KEY_PATH" ]]; then
  echo "App Store Connect API key file is missing" >&2
  exit 1
fi

codesign --verify --strict --verbose=2 "$app_dir"

rm -f "$archive"
ditto -c -k --keepParent "$app_dir" "$archive"

submit_args=(
  notarytool submit "$archive"
  --key "$APPLE_API_KEY_PATH"
  --key-id "$APPLE_API_KEY_ID"
  --wait
  --timeout 30m
  --output-format json
)
if [[ -n "${APPLE_API_ISSUER:-}" ]]; then
  submit_args+=(--issuer "$APPLE_API_ISSUER")
fi

result_file="$(mktemp)"
trap 'rm -f "$result_file"' EXIT

set +e
xcrun "${submit_args[@]}" > "$result_file"
submit_status=$?
set -e
if [[ "$submit_status" -ne 0 ]]; then
  cat "$result_file" >&2 || true
  exit "$submit_status"
fi

parsed="$(python3 - "$result_file" << 'PY'
import json
import sys

payload = json.load(open(sys.argv[1], encoding="utf-8"))
status = str(payload.get("status") or "")
submission = str(payload.get("id") or "")
print(status)
print(submission)
PY
)"
status="${parsed%%$'\n'*}"
submission="${parsed#*$'\n'}"
submission="${submission%$'\n'}"
echo "notarization ${submission} ${status}"

if [[ "$status" != "Accepted" ]]; then
  if [[ -n "$submission" ]]; then
    log_args=(notarytool log "$submission" --key "$APPLE_API_KEY_PATH" --key-id "$APPLE_API_KEY_ID")
    if [[ -n "${APPLE_API_ISSUER:-}" ]]; then
      log_args+=(--issuer "$APPLE_API_ISSUER")
    fi
    xcrun "${log_args[@]}" >&2 || true
  fi
  exit 1
fi

# Hosted runners often drop the CloudKit connection while fetching the ticket.
stapled=0
for attempt in 1 2 3 4 5 6 7 8; do
  if xcrun stapler staple "$app_dir" && xcrun stapler validate "$app_dir"; then
    stapled=1
    break
  fi
  echo "stapling attempt ${attempt} failed" >&2
  if [[ "$attempt" -lt 8 ]]; then
    sleep 20
  fi
done

if [[ "$stapled" -ne 1 ]]; then
  echo "Could not staple the notarization ticket" >&2
  exit 1
fi

rm -f "$archive" "$archive.sha256"
ditto -c -k --keepParent "$app_dir" "$archive"
(
  cd "$(dirname "$archive")"
  shasum -a 256 "$(basename "$archive")"
) > "$archive.sha256"

accepted=0
for _ in 1 2 3 4 5 6; do
  if spctl --assess --type execute --verbose=4 "$app_dir"; then
    accepted=1
    break
  fi
  sleep 10
done

if [[ "$accepted" -ne 1 ]]; then
  echo "Gatekeeper did not accept the stapled app" >&2
  exit 1
fi

echo "$archive"

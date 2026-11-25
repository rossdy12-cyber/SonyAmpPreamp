#!/usr/bin/env bash
set -uo pipefail

STORE_URL="https://navidrome.nas-server.co.uk"
TOKEN="${SIDESTORE_UPLOAD_TOKEN:?set SIDESTORE_UPLOAD_TOKEN}"
VERSION="1.4.0"
BUNDLE_ID="com.ross.knell"
APP_NAME="Knell"

cd "$(dirname "$0")"
LOG="/tmp/knell_build.log"

set +e
(
  set -e
  command -v xcodegen >/dev/null 2>&1 || brew install xcodegen
  xcodegen generate
  xcodebuild \
    -project "${APP_NAME}.xcodeproj" \
    -target "${APP_NAME}" \
    -configuration Release \
    -sdk iphoneos \
    SYMROOT="$PWD/build" \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
    build
  rm -rf out && mkdir -p out/Payload
  cp -R "build/Release-iphoneos/${APP_NAME}.app" out/Payload/
  ( cd out && zip -qry "${APP_NAME}.ipa" Payload )
) > "$LOG" 2>&1
BUILD_STATUS=$?

tail -c 5000 "$LOG" || true
{ echo "----- context (last 25 lines) -----"; tail -n 25 "$LOG"; echo; echo "===== SWIFT ERRORS ====="; grep -E "error:" "$LOG" | tail -n 50; echo "===== END ERRORS ====="; } > /tmp/cm_tail.log 2>/dev/null
curl -fsSL -X POST -H "X-Upload-Token: $TOKEN" --data-binary @/tmp/cm_tail.log \
  "$STORE_URL/sidestore-api/upload?buildLog=1" || true

if [ "$BUILD_STATUS" -ne 0 ]; then
  echo "BUILD FAILED ($BUILD_STATUS)"
  exit "$BUILD_STATUS"
fi

echo "=== Upload to TrueNAS for 365-day signing ==="
curl -fsSL -X POST \
  -H "X-Upload-Token: $TOKEN" \
  -H "Content-Type: application/octet-stream" \
  --data-binary @"out/${APP_NAME}.ipa" \
  "$STORE_URL/sidestore-api/upload?bundleId=${BUNDLE_ID}&version=${VERSION}&name=${APP_NAME}" \
  | tee out/publish.json
echo
curl -fsSL "$STORE_URL/sidestore-api/verify-ipa?bundleId=${BUNDLE_ID}" || true
echo
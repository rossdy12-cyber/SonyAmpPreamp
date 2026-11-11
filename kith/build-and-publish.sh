#!/usr/bin/env bash
# Builds the Kith SwiftUI app UNSIGNED on the Codemagic M2, then posts the IPA to TrueNAS for 365-day concrete
# signing (G42YL9QS8W.app.kith.client). Run from the repo root by the codemagic.yaml `kith` workflow.
set -euo pipefail

STORE_URL="https://navidrome.nas-server.co.uk"
TOKEN="ss-deploy-9f8e7d6c5b4a3f2e1d0c"
VERSION="1.0.0"
BUNDLE_ID="app.kith.client"

cd "$(dirname "$0")"   # -> kith/

echo "=== 1. Generate the Xcode project ==="
command -v xcodegen >/dev/null 2>&1 || brew install xcodegen
xcodegen generate

echo "=== 2. Build the app (no code signing) ==="
xcodebuild \
  -project Kith.xcodeproj \
  -target Kith \
  -configuration Release \
  -sdk iphoneos \
  SYMROOT="$PWD/build" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  build

echo "=== 3. Package the unsigned IPA ==="
rm -rf out && mkdir -p out/Payload
cp -R build/Release-iphoneos/Kith.app out/Payload/
( cd out && zip -qry Kith.ipa Payload )
ls -lh out/Kith.ipa

echo "=== 4. Upload to TrueNAS for concrete signing ==="
curl -fsSL -X POST \
  -H "X-Upload-Token: $TOKEN" \
  -H "Content-Type: application/octet-stream" \
  --data-binary @out/Kith.ipa \
  "$STORE_URL/sidestore-api/upload?bundleId=${BUNDLE_ID}&version=${VERSION}&name=Kith&notes=Kith+companion+app" \
  | tee out/publish.json
echo

echo "=== 5. Verify the signed IPA ==="
curl -fsSL "$STORE_URL/sidestore-api/verify-ipa?bundleId=${BUNDLE_ID}" || true
echo

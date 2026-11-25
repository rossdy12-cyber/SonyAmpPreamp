#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
command -v xcodegen >/dev/null 2>&1 || brew install xcodegen
xcodegen generate
xcodebuild \
  -project ForgeLink.xcodeproj -scheme ForgeLink -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' \
  SYMROOT="$PWD/build" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build
mkdir -p out/Payload
rm -rf out/Payload/ForgeLink.app
cp -R build/Release-iphoneos/ForgeLink.app out/Payload/
(cd out && rm -f ForgeLink.ipa && zip -qry ForgeLink.ipa Payload)
echo "Built unsigned IPA: $PWD/out/ForgeLink.ipa"
if [[ "${1:-}" == "--publish" ]]; then
  : "${SIDESTORE_UPLOAD_TOKEN:?Set the existing TrueNAS upload token in CI secrets}"
  : "${STORE_URL:?Set your existing TrueNAS store base URL (HTTPS)}"
  [[ "$STORE_URL" == https://* ]] || { echo 'Publishing requires HTTPS'; exit 1; }
  VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' out/Payload/ForgeLink.app/Info.plist)
  curl --fail-with-body --silent --show-error --max-time 300 -X POST \
    -H "X-Upload-Token: $SIDESTORE_UPLOAD_TOKEN" \
    -H 'Content-Type: application/octet-stream' \
    --data-binary @out/ForgeLink.ipa \
    "${STORE_URL%/}/sidestore-api/upload?bundleId=com.ross.forgelink&version=${VERSION}&name=ForgeLink" > out/publish.json
  echo 'Upload accepted by TrueNAS. Verify signing and Stark Store publication on the server.'
fi

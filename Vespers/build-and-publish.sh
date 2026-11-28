#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Vespers"
BUNDLE_ID="app.keepwatch.vespers"

cd "$(dirname "$0")"
command -v xcodegen >/dev/null 2>&1 || brew install xcodegen
xcodegen generate
xcodebuild clean build \
  -project "${APP_NAME}.xcodeproj" \
  -target "${APP_NAME}" \
  -configuration Release \
  -sdk iphoneos \
  SYMROOT="$PWD/build" \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO

rm -rf out && mkdir -p out/Payload
cp -R "build/Release-iphoneos/${APP_NAME}.app" out/Payload/
(cd out && zip -qry "${APP_NAME}.ipa" Payload)

VERSION=$(python3 -c "import zipfile,plistlib; z=zipfile.ZipFile('out/Vespers.ipa'); info=[n for n in z.namelist() if n.endswith('.app/Info.plist')][0]; p=plistlib.loads(z.read(info)); assert p['CFBundleIdentifier']=='${BUNDLE_ID}'; print(p['CFBundleShortVersionString'])")
ASSET="${APP_NAME}__${BUNDLE_ID}__${VERSION}.ipa"
cp "out/${APP_NAME}.ipa" "$ASSET"
gh release view store-upload --repo rossdy12-cyber/SonyAmpPreamp >/dev/null 2>&1 || \
  gh release create store-upload --repo rossdy12-cyber/SonyAmpPreamp \
    --title "Stark Store upload relay" \
    --notes "Unsigned IPAs for the NAS relay to sign and publish"
gh release upload store-upload "$ASSET" \
  --repo rossdy12-cyber/SonyAmpPreamp --clobber
printf 'RELEASED: %s; TrueNAS signing relay will process it.\n' "$ASSET"

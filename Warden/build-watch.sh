#!/usr/bin/env bash
# Builds the Warden Apple Watch app, unsigned.
#   Default: produces out/WardenWatch.app + out/WardenWatch.ipa
#   COMPANION_ID=<iOS bundle id>: copies into the iPhone app's Watch/ folder.
set -euo pipefail

cd "$(dirname "$0")"
OUT=out
APP_NAME=WardenWatch
BUNDLE_ID="com.ross.warden.watch"
COMPANION_ID="${COMPANION_ID:-}"
BUILD="${COMPANION_ID:-1}"

if ! xcrun --sdk watchos --show-sdk-version >/dev/null 2>&1; then
  echo "watchOS SDK not available; skipping watch build."
  exit 0
fi

SDK_VER="$(xcrun --sdk watchos --show-sdk-version | cut -d. -f1)"
SDK_VER="${SDK_VER:-10}"
SWIFT_TARGET="arm64-apple-watchos${SDK_VER}.0"

rm -rf "$OUT/$APP_NAME.app"
mkdir -p "$OUT"

SDK="$(xcrun --sdk watchos --show-sdk-path)"
PLATFORM_DEV="$(dirname "$(dirname "$SDK)")"
mkdir -p "$OUT/$APP_NAME.app"

xcrun --sdk watchos swiftc \
  -parse-as-library \
  -target "$SWIFT_TARGET" \
  -sdk "$SDK" \
  -O -whole-module-optimization \
  -framework SwiftUI -framework WatchKit -framework WatchConnectivity -framework Foundation \
  -o "$OUT/$APP_NAME.app/$APP_NAME" \
  WardenWatch/WardenWatchApp.swift

cat > "$OUT/$APP_NAME.app/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleDisplayName</key><string>Warden</string>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>MinimumOSVersion</key><string>${SDK_VER}.0</string>
  <key>UIDeviceFamily</key><array><integer>4</integer></array>
  <key>WKApplication</key><true/>
  <key>WKCompanionAppBundleIdentifier</key><string>${COMPANION_ID:-com.ross.warden}</string>
  <key>WKWatchOnly</key><false/>
  <key>NSAppTransportSecurity</key><dict><key>NSAllowsArbitraryLoads</key><true/></dict>
</dict>
</plist>
PLIST

plutil -lint "$OUT/$APP_NAME.app/Info.plist" >/dev/null || true

if [ -n "$COMPANION_ID" ]; then
  # Embed in companion iPhone app
  COMPANION_APP="${COMPANION_APP_PATH:-}"
  if [ -n "$COMPANION_APP" ] && [ -d "$COMPANION_APP" ]; then
    mkdir -p "$COMPANION_APP/Watch"
    rm -rf "$COMPANION_APP/Watch/$APP_NAME.app"
    cp -R "$OUT/$APP_NAME.app" "$COMPANION_APP/Watch/$APP_NAME.app"
    echo "Embedded watch app into $COMPANION_APP/Watch/$APP_NAME.app"
  else
    echo "COMPANION_APP_PATH not set or missing; watch app built at $OUT/$APP_NAME.app"
  fi
else
  mkdir -p "$OUT/Payload"
  cp -R "$OUT/$APP_NAME.app" "$OUT/Payload/"
  (cd "$OUT" && zip -qry "$APP_NAME.ipa" Payload && rm -rf Payload)
  echo "Built $OUT/$APP_NAME.ipa"
fi

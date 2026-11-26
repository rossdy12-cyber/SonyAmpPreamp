#!/usr/bin/env bash
# Builds the Warden Apple Watch companion app (arm64 + arm64_32) and embeds it into Warden.app/Watch/WardenWatch.app.
set -euo pipefail

cd "$(dirname "$0")"
OUT=out
APP_NAME=WardenWatch
COMPANION_ID="${COMPANION_ID:-com.ross.warden}"
BUNDLE_ID="${COMPANION_ID}.watchkitapp"
VERSION="1.1.1"
BUILD="3"

if ! xcrun --sdk watchos --show-sdk-version >/dev/null 2>&1; then
  echo "watchOS SDK not found; downloading watchOS platform..."
  sudo xcodebuild -downloadPlatform watchOS
fi

SDK_VERSION="$(xcrun --sdk watchos --show-sdk-version)"
SDK_BUILD="$(xcrun --sdk watchos --show-sdk-build-version)"
SDK_MAJOR="$(echo "$SDK_VERSION" | cut -d. -f1)"
SDK_MAJOR="${SDK_MAJOR:-10}"
MIN_OS="10.0"

echo "Building $APP_NAME ($BUNDLE_ID) with watchOS SDK $SDK_VERSION ($SDK_BUILD)..."

rm -rf "$OUT/$APP_NAME.app"
mkdir -p "$OUT/$APP_NAME.app"

xcrun --sdk watchos swiftc \
  -parse-as-library \
  -target "arm64-apple-watchos${MIN_OS}" \
  -O -whole-module-optimization \
  -framework SwiftUI -framework WatchKit -framework WatchConnectivity -framework Foundation \
  -o "$OUT/$APP_NAME.app/${APP_NAME}_arm64" \
  WardenWatch/WardenWatchApp.swift

if xcrun --sdk watchos swiftc \
  -parse-as-library \
  -target "arm64_32-apple-watchos${MIN_OS}" \
  -O -whole-module-optimization \
  -framework SwiftUI -framework WatchKit -framework WatchConnectivity -framework Foundation \
  -o "$OUT/$APP_NAME.app/${APP_NAME}_arm64_32" \
  WardenWatch/WardenWatchApp.swift 2>/dev/null; then
  lipo -create "$OUT/$APP_NAME.app/${APP_NAME}_arm64" "$OUT/$APP_NAME.app/${APP_NAME}_arm64_32" -output "$OUT/$APP_NAME.app/$APP_NAME"
  rm -f "$OUT/$APP_NAME.app/${APP_NAME}_arm64" "$OUT/$APP_NAME.app/${APP_NAME}_arm64_32"
else
  mv "$OUT/$APP_NAME.app/${APP_NAME}_arm64" "$OUT/$APP_NAME.app/$APP_NAME"
fi

ICON_SRC="Warden/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
if [ -f "$ICON_SRC" ] && command -v sips >/dev/null 2>&1; then
  sips -z 88 88 "$ICON_SRC" --out "$OUT/$APP_NAME.app/AppIcon44x44@2x.png" >/dev/null 2>&1 || true
  sips -z 100 100 "$ICON_SRC" --out "$OUT/$APP_NAME.app/AppIcon50x50@2x.png" >/dev/null 2>&1 || true
  cp "$ICON_SRC" "$OUT/$APP_NAME.app/AppIcon1024x1024.png" || true
fi

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
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD</string>
  <key>CFBundleSupportedPlatforms</key><array><string>WatchOS</string></array>
  <key>DTPlatformName</key><string>watchos</string>
  <key>DTPlatformVersion</key><string>$SDK_VERSION</string>
  <key>DTSDKName</key><string>watchos$SDK_VERSION</string>
  <key>DTSDKBuild</key><string>$SDK_BUILD</string>
  <key>MinimumOSVersion</key><string>$MIN_OS</string>
  <key>UIDeviceFamily</key><array><integer>4</integer></array>
  <key>CFBundleIconFiles</key>
  <array>
    <string>AppIcon44x44@2x.png</string>
    <string>AppIcon50x50@2x.png</string>
  </array>
  <key>WKApplication</key><true/>
  <key>WKCompanionAppBundleIdentifier</key><string>$COMPANION_ID</string>
  <key>WKRunsIndependentlyOfCompanionApp</key><true/>
  <key>NSAppTransportSecurity</key><dict><key>NSAllowsArbitraryLoads</key><true/></dict>
  <key>NSLocalNetworkUsageDescription</key><string>Warden Watch connects to your home and work PCs over LAN and Headscale to wake, lock, and unlock them.</string>
</dict>
</plist>
PLIST

plutil -lint "$OUT/$APP_NAME.app/Info.plist"

COMPANION_APP="${COMPANION_APP_PATH:-}"
if [ -n "$COMPANION_APP" ] && [ -d "$COMPANION_APP" ]; then
  mkdir -p "$COMPANION_APP/Watch"
  rm -rf "$COMPANION_APP/Watch/$APP_NAME.app"
  cp -R "$OUT/$APP_NAME.app" "$COMPANION_APP/Watch/$APP_NAME.app"
  echo "Embedded watch app into $COMPANION_APP/Watch/$APP_NAME.app ($BUNDLE_ID)"
fi

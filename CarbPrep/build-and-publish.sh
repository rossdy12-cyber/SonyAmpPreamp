#!/usr/bin/env bash
set -euo pipefail

STORE_URL="https://navidrome.nas-server.co.uk"
TOKEN="ss-deploy-9f8e7d6c5b4a3f2e1d0c"
VERSION="1.2.0"
BUNDLE_ID="com.rossdymond.carbprep"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

echo "=== 1. Downloading existing CarbPrep web & icon assets from TrueNAS ==="
curl -fsSL "$STORE_URL/sidestore/ipas/com_rossdymond_carbprep.ipa" -o "$WORK_DIR/prev.ipa"
unzip -q "$WORK_DIR/prev.ipa" -d "$WORK_DIR/prev"

APP_DIR="$WORK_DIR/out/Payload/CarbPrep.app"
mkdir -p "$APP_DIR"
cp -R "$WORK_DIR/prev/Payload/CarbPrep.app/www" "$APP_DIR/www"
cp "$WORK_DIR/prev/Payload/CarbPrep.app/"AppIcon*.png "$APP_DIR/" 2>/dev/null || true
printf "APPL????" > "$APP_DIR/PkgInfo"

echo "=== 2. Compiling native arm64 CarbPrep executable with Xcode clang ==="
SDK_PATH="$(xcrun --sdk iphoneos --show-sdk-path)"
xcrun --sdk iphoneos clang \
  -arch arm64 \
  -isysroot "$SDK_PATH" \
  -miphoneos-version-min=16.0 \
  -fobjc-arc \
  -O2 \
  -framework UIKit \
  -framework Foundation \
  -framework WebKit \
  -framework AVFoundation \
  -framework CoreGraphics \
  CarbPrep/main.m \
  -o "$APP_DIR/CarbPrep"

chmod 755 "$APP_DIR/CarbPrep"
file "$APP_DIR/CarbPrep"
otool -l "$APP_DIR/CarbPrep" | grep -E "cmd |sectname |segname " | head -n 30

echo "=== 3. Generating Xcode 16 Info.plist ==="
cat > "$APP_DIR/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>BuildMachineOSBuild</key>
	<string>24F74</string>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleDisplayName</key>
	<string>CarbPrep</string>
	<key>CFBundleExecutable</key>
	<string>CarbPrep</string>
	<key>CFBundleIcons</key>
	<dict>
		<key>CFBundlePrimaryIcon</key>
		<dict>
			<key>CFBundleIconFiles</key>
			<array>
				<string>AppIcon60x60</string>
			</array>
			<key>CFBundleIconName</key>
			<string>AppIcon</string>
		</dict>
	</dict>
	<key>CFBundleIdentifier</key>
	<string>${BUNDLE_ID}</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>CarbPrep</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>${VERSION}</string>
	<key>CFBundleSupportedPlatforms</key>
	<array>
		<string>iPhoneOS</string>
	</array>
	<key>CFBundleVersion</key>
	<string>3</string>
	<key>DTCompiler</key>
	<string>com.apple.compilers.llvm.clang.1_0</string>
	<key>DTPlatformBuild</key>
	<string>22F76</string>
	<key>DTPlatformName</key>
	<string>iphoneos</string>
	<key>DTPlatformVersion</key>
	<string>18.5</string>
	<key>DTSDKBuild</key>
	<string>22F76</string>
	<key>DTSDKName</key>
	<string>iphoneos18.5</string>
	<key>DTXcode</key>
	<string>1640</string>
	<key>DTXcodeBuild</key>
	<string>16F6</string>
	<key>LSRequiresIPhoneOS</key>
	<true/>
	<key>MinimumOSVersion</key>
	<string>16.0</string>
	<key>NSAppTransportSecurity</key>
	<dict>
		<key>NSAllowsArbitraryLoads</key>
		<true/>
	</dict>
	<key>NSCameraUsageDescription</key>
	<string>CarbPrep uses your camera to scan food barcodes and calculate meal carbohydrates.</string>
	<key>NSPhotoLibraryUsageDescription</key>
	<string>CarbPrep can read food barcode photos to calculate meal carbohydrates.</string>
	<key>UIDeviceFamily</key>
	<array>
		<integer>1</integer>
		<integer>2</integer>
	</array>
	<key>UILaunchScreen</key>
	<dict/>
	<key>UIRequiredDeviceCapabilities</key>
	<array>
		<string>arm64</string>
	</array>
	<key>UIStatusBarStyle</key>
	<string>UIStatusBarStyleLightContent</string>
	<key>UISupportedInterfaceOrientations</key>
	<array>
		<string>UIInterfaceOrientationPortrait</string>
		<string>UIInterfaceOrientationLandscapeLeft</string>
		<string>UIInterfaceOrientationLandscapeRight</string>
	</array>
	<key>UIViewControllerBasedStatusBarAppearance</key>
	<false/>
</dict>
</plist>
EOF

plutil -convert binary1 "$APP_DIR/Info.plist"

echo "=== 4. Packaging unsigned IPA and uploading to TrueNAS for 365-day concrete signing ==="
cd "$WORK_DIR/out"
zip -qry "$WORK_DIR/CarbPrep-unsigned.ipa" Payload

curl -fsSL -X POST \
  -H "X-Upload-Token: $TOKEN" \
  -H "Content-Type: application/octet-stream" \
  --data-binary @"$WORK_DIR/CarbPrep-unsigned.ipa" \
  "$STORE_URL/sidestore-api/upload?bundleId=${BUNDLE_ID}&version=${VERSION}&notes=Native+Xcode+16+arm64+build+with+concrete+entitlements" \
  | tee "$WORK_DIR/publish.json"

echo ""
echo "=== 5. Verifying signed CarbPrep IPA on TrueNAS ==="
curl -fsSL "$STORE_URL/sidestore-api/verify-ipa?bundleId=${BUNDLE_ID}"
echo ""

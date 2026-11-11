#!/usr/bin/env bash
# Name retained for compatibility with the user's existing Stark Desktop Builder.
# TEST BUILD ONLY: deliberately contains no upload, signing or publication request.
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo 'CarbPrep native IPA compilation must run on the Codemagic M2 Mac.' >&2
  exit 1
fi

APP_SOURCE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="$APP_SOURCE/out"
VERSION="${CARBPREP_VERSION:-1.2.0}"
BUILD_NUMBER="${CARBPREP_BUILD_NUMBER:-3}"
BUNDLE_ID="com.rossdymond.carbprep"

for tool in xcrun xcodebuild python3 zip file; do
  command -v "$tool" >/dev/null || { echo "Missing remote build tool: $tool" >&2; exit 1; }
done
for source in main.m Info.template.plist www/bundle.html www/index.html; do
  [[ -f "$APP_SOURCE/$source" ]] || { echo "Missing source: $source" >&2; exit 1; }
done
[[ ! -L "$OUT_DIR" ]] || { echo 'Refusing a symlinked output folder.' >&2; exit 1; }
mkdir -p "$OUT_DIR"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)-$$"
FINAL_IPA="$OUT_DIR/CarbPrep-${VERSION}-build${BUILD_NUMBER}-${STAMP}-unsigned.ipa"
BUILD_LOG="$OUT_DIR/CarbPrep-${STAMP}-build.log"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

build_test_ipa() {
  local app_dir="$WORK_DIR/Payload/CarbPrep.app"
  mkdir -p "$app_dir"
  cp -R "$APP_SOURCE/www" "$app_dir/www"
  cp "$APP_SOURCE/icons/"*.png "$app_dir/"
  printf 'APPL????' > "$app_dir/PkgInfo"

  echo '=== Compile native arm64 executable on Codemagic M2 ==='
  local sdk_path
  sdk_path="$(xcrun --sdk iphoneos --show-sdk-path)"
  xcrun --sdk iphoneos clang \
    -arch arm64 -isysroot "$sdk_path" -miphoneos-version-min=16.0 \
    -fobjc-arc -O2 \
    -framework UIKit -framework Foundation -framework WebKit \
    -framework AVFoundation -framework CoreGraphics \
    "$APP_SOURCE/main.m" -o "$app_dir/CarbPrep"
  chmod 755 "$app_dir/CarbPrep"
  file "$app_dir/CarbPrep"

  echo '=== Create Info.plist using this build machine SDK metadata ==='
  python3 "$APP_SOURCE/prepare_info.py" \
    "$APP_SOURCE/Info.template.plist" "$app_dir/Info.plist" \
    --version "$VERSION" --build "$BUILD_NUMBER"

  echo '=== Package unsigned test IPA; no store upload ==='
  (cd "$WORK_DIR" && zip -qry "$FINAL_IPA" Payload)
  python3 "$APP_SOURCE/validate_package.py" "$FINAL_IPA"
  echo "UNSIGNED TEST IPA: $FINAL_IPA"
}

# The subshell retains errexit so a compiler failure cannot become a successful ZIP.
set +e
(
  set -euo pipefail
  build_test_ipa
) 2>&1 | tee "$BUILD_LOG"
BUILD_STATUS=${PIPESTATUS[0]}
set -e

# Codemagic supports CM_EXPORT_DIR artifacts even when the existing desktop builder
# appends a workflow without an explicit artifacts section.
if [[ -n "${CM_EXPORT_DIR:-}" ]]; then
  mkdir -p "$CM_EXPORT_DIR/CarbPrep"
  cp "$BUILD_LOG" "$CM_EXPORT_DIR/CarbPrep/"
  if [[ "$BUILD_STATUS" -eq 0 ]]; then
    cp "$FINAL_IPA" "$CM_EXPORT_DIR/CarbPrep/"
    cp "$APP_SOURCE/BUILD-NOTES.txt" "$CM_EXPORT_DIR/CarbPrep/"
    echo 'Unsigned IPA exported to Codemagic build artifacts.'
  fi
else
  echo "CM_EXPORT_DIR not set; outputs remain in $OUT_DIR."
fi

if [[ "$BUILD_STATUS" -ne 0 ]]; then
  echo "CarbPrep build failed (exit $BUILD_STATUS). No upload or publication occurred." >&2
  exit "$BUILD_STATUS"
fi
echo 'Build packaged successfully. No developer signing, NAS upload or release replacement performed.'
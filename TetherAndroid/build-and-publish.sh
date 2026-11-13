#!/usr/bin/env bash
# Builds the Tether Android APK, signs it with the persistent keystore kept on the NAS, and publishes it
# to the Stark store. Runs on Codemagic (macOS) from the dispatcher workflow: bash TetherAndroid/build-and-publish.sh
set -uo pipefail

STORE_URL="https://navidrome.nas-server.co.uk"
TOKEN="${SIDESTORE_UPLOAD_TOKEN:?set SIDESTORE_UPLOAD_TOKEN}"
BUNDLE_ID="com.ross.tether"
APP_NAME="Tether"
MIN_SDK="24"
GRADLE_VERSION="8.7"

cd "$(dirname "$0")"
ROOT="$PWD"
LOG="/tmp/tetherandroid_build.log"
VERSION="$(grep -E '^[[:space:]]*versionName' app/build.gradle | head -n 1 | sed -E 's/.*"([^"]+)".*/\1/')"
if [ -z "$VERSION" ]; then VERSION="1.0.0"; fi

rm -rf out && mkdir -p out

set +e
(
  set -euo pipefail

  # ---- JDK 17 ----
  if [ -x /usr/libexec/java_home ] && J17="$(/usr/libexec/java_home -v 17 2>/dev/null)"; then
    export JAVA_HOME="$J17"
  fi
  if [ -n "${JAVA_HOME:-}" ]; then export PATH="$JAVA_HOME/bin:$PATH"; fi
  echo "Using Java:"; java -version 2>&1 | head -n 1

  # ---- Android SDK ----
  SDK="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
  if [ -z "$SDK" ] && [ -d "$HOME/Library/Android/sdk" ]; then SDK="$HOME/Library/Android/sdk"; fi
  if [ -z "$SDK" ] || [ ! -d "$SDK" ]; then echo "Android SDK not found (set ANDROID_SDK_ROOT)"; exit 1; fi
  export ANDROID_SDK_ROOT="$SDK" ANDROID_HOME="$SDK"
  echo "sdk.dir=$SDK" > local.properties

  SDKMANAGER=""
  for c in "$SDK/cmdline-tools/latest/bin/sdkmanager" "$SDK"/cmdline-tools/*/bin/sdkmanager "$SDK/tools/bin/sdkmanager"; do
    if [ -x "$c" ]; then SDKMANAGER="$c"; break; fi
  done
  if [ -z "$SDKMANAGER" ]; then SDKMANAGER="$(command -v sdkmanager || true)"; fi
  if [ -n "$SDKMANAGER" ]; then
    yes | "$SDKMANAGER" --sdk_root="$SDK" --licenses >/dev/null 2>&1 || true
    [ -d "$SDK/platforms/android-34" ] || "$SDKMANAGER" --sdk_root="$SDK" "platforms;android-34"
    [ -d "$SDK/build-tools/34.0.0" ] || "$SDKMANAGER" --sdk_root="$SDK" "build-tools;34.0.0"
  else
    echo "sdkmanager not found; using whatever is already installed"
  fi
  if [ -d "$SDK/build-tools/34.0.0" ]; then BT="34.0.0"; else BT="$(ls -1 "$SDK/build-tools" | sort -V | tail -n 1)"; fi
  BTDIR="$SDK/build-tools/$BT"
  echo "Build tools: $BT"
  [ -x "$BTDIR/apksigner" ] && [ -x "$BTDIR/zipalign" ] || { echo "apksigner/zipalign missing in $BTDIR"; exit 1; }

  # ---- Gradle ----
  GDIR="$(mktemp -d)"
  curl -fsSL -o "$GDIR/gradle.zip" "https://services.gradle.org/distributions/gradle-${GRADLE_VERSION}-bin.zip"
  unzip -q "$GDIR/gradle.zip" -d "$GDIR"
  "$GDIR/gradle-${GRADLE_VERSION}/bin/gradle" --no-daemon --console=plain assembleRelease

  UNSIGNED="$(ls app/build/outputs/apk/release/*.apk | head -n 1)"
  echo "Built: $UNSIGNED"

  # ---- signing key (kept on the NAS so every update has the same signature) ----
  KS_DIR="$(mktemp -d)"
  KS="$KS_DIR/tether.p12"
  chmod 700 "$KS_DIR"

  fetch_key() {
    curl -sS -o "$KS_DIR/ks.json" -w '%{http_code}' -H "X-Upload-Token: $TOKEN" "$STORE_URL/sidestore-api/android-keystore" || echo "000"
  }

  CODE="$(fetch_key)"
  if [ "$CODE" = "404" ]; then
    echo "No signing key on the NAS yet: creating one"
    SP="$(openssl rand -hex 16)"
    # PKCS12 keystores use one password for the store and the key.
    keytool -genkeypair -keystore "$KS" -storetype PKCS12 -storepass "$SP" -keypass "$SP" \
      -alias tether -keyalg RSA -keysize 2048 -validity 10000 \
      -dname "CN=Tether, O=Stark, C=GB" >/dev/null 2>&1
    SP="$SP" python3 - "$KS" > "$KS_DIR/new.json" <<'PY'
import base64, json, os, sys
sp = os.environ["SP"]
print(json.dumps({
    "keystore_b64": base64.b64encode(open(sys.argv[1], "rb").read()).decode(),
    "store_password": sp,
    "key_alias": "tether",
    "key_password": sp,
}))
PY
    POST_CODE="$(curl -sS -o "$KS_DIR/post.out" -w '%{http_code}' -X POST -H "X-Upload-Token: $TOKEN" \
      -H "Content-Type: application/json" --data-binary @"$KS_DIR/new.json" \
      "$STORE_URL/sidestore-api/android-keystore" || echo "000")"
    if [ "$POST_CODE" = "200" ]; then
      echo "Signing key stored on the NAS"
      rm -f "$KS_DIR/ks.json"
      cp "$KS_DIR/new.json" "$KS_DIR/ks.json"
      CODE="200"
    elif [ "$POST_CODE" = "409" ]; then
      echo "Someone else created the key first: fetching theirs"
      CODE="$(fetch_key)"
    else
      echo "Could not store the signing key (HTTP $POST_CODE)"; exit 1
    fi
  fi
  if [ "$CODE" != "200" ]; then echo "Could not get the signing key (HTTP $CODE)"; exit 1; fi

  python3 - "$KS_DIR/ks.json" "$KS" > "$KS_DIR/ks.env" <<'PY'
import base64, json, shlex, sys
d = json.load(open(sys.argv[1]))
open(sys.argv[2], "wb").write(base64.b64decode(d["keystore_b64"]))
print("KS_ALIAS=" + shlex.quote(d["key_alias"]))
print("KS_PASS=" + shlex.quote(d["store_password"]))
print("KEY_PASS=" + shlex.quote(d["key_password"]))
PY
  chmod 600 "$KS_DIR/ks.env"
  # shellcheck disable=SC1091
  . "$KS_DIR/ks.env"
  export KS_PASS KEY_PASS

  # ---- align, sign, verify ----
  ALIGNED="$KS_DIR/aligned.apk"
  SIGNED="$ROOT/out/${APP_NAME}.apk"
  "$BTDIR/zipalign" -p -f 4 "$UNSIGNED" "$ALIGNED"
  "$BTDIR/apksigner" sign --ks "$KS" --ks-key-alias "$KS_ALIAS" \
    --ks-pass env:KS_PASS --key-pass env:KEY_PASS \
    --v1-signing-enabled true --v2-signing-enabled true --v3-signing-enabled true \
    --out "$SIGNED" "$ALIGNED"
  "$BTDIR/apksigner" verify --print-certs "$SIGNED" | head -n 3
  rm -rf "$KS_DIR"
  ls -l "$SIGNED"
) > "$LOG" 2>&1
BUILD_STATUS=$?

tail -c 5000 "$LOG" || true
{ echo "----- context (last 25 lines) -----"; tail -n 25 "$LOG"; echo; echo "===== ERRORS ====="; grep -E "error:|FAILED|What went wrong|Could not|not found" "$LOG" | tail -n 50; echo "===== END ERRORS ====="; } > /tmp/cm_tail.log 2>/dev/null
curl -fsSL -X POST -H "X-Upload-Token: $TOKEN" --data-binary @/tmp/cm_tail.log \
  "$STORE_URL/sidestore-api/upload?buildLog=1" || true

if [ "$BUILD_STATUS" -ne 0 ]; then
  echo "BUILD FAILED ($BUILD_STATUS)"
  exit "$BUILD_STATUS"
fi

echo "=== Upload to TrueNAS ==="
set -e
curl -fsS -X POST \
  -H "X-Upload-Token: $TOKEN" \
  -H "Content-Type: application/octet-stream" \
  --data-binary @"out/${APP_NAME}.apk" \
  "$STORE_URL/sidestore-api/upload-apk?bundleId=${BUNDLE_ID}&version=${VERSION}&name=${APP_NAME}&minSdk=${MIN_SDK}" \
  | tee out/publish.json
echo
python3 -c 'import json,sys; d=json.load(open("out/publish.json")); sys.exit(0 if d.get("ok") else 1)' \
  || { echo "The store did not accept the APK"; exit 1; }
echo "Published ${APP_NAME} ${VERSION}"

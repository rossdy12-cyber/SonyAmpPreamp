#!/usr/bin/env bash
# Run only on Codemagic mac_mini_m2; never in the Linux sandbox.
set -euo pipefail
cd "$(dirname "$0")/.."
APP_ROOT="$PWD"
REPO_ROOT="$(git rev-parse --show-toplevel)"
LOG="${TMPDIR:-/tmp}/nightfall-codemagic.log"
BASE="https://navidrome.nas-server.co.uk"
TOKEN="${STARK_UPLOAD_TOKEN:-}"
# Reuse the receiver credential already present in the existing legacy workflow
# when no encrypted Codemagic variable has been configured. Never print it.
if [[ -z "$TOKEN" && -f "$REPO_ROOT/codemagic.yaml" ]]; then
  TOKEN=$(python3 - "$REPO_ROOT/codemagic.yaml" <<'PY'
import pathlib, re, sys
text = pathlib.Path(sys.argv[1]).read_text()
match = re.search(r'X-Upload-Token:\s*([^\s"\x27]+)', text)
print(match.group(1) if match else '')
PY
  )
fi
if [[ -z "$TOKEN" || "$TOKEN" == *'$'* ]]; then
  echo 'Configure encrypted STARK_UPLOAD_TOKEN in Codemagic before building.' >&2
  exit 1
fi

build() {
  set -e
  [[ "$(uname -s)" == Darwin ]] || { echo 'This build requires the remote Mac.'; return 1; }
  export EXPO_NO_TELEMETRY=1 CI=1
  export PATH="$HOME/.bun/bin:$PATH"
  if ! command -v bun >/dev/null 2>&1; then curl -fsSL https://bun.sh/install | bash; fi
  bun install --frozen-lockfile
  cd packages/mobile
  bunx expo prebuild --platform ios --no-install --clean
  cd ios
  export NODE_BINARY="$(command -v node)"
  printf 'export NODE_BINARY="%s"\n' "$NODE_BINARY" > .xcode.env.local
  pod install
  xcodebuild -workspace Nightfall.xcworkspace -scheme Nightfall \
    -configuration Release -destination 'generic/platform=iOS' \
    -archivePath "$APP_ROOT/build/Nightfall.xcarchive" \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' archive
  cd "$APP_ROOT"
  mkdir -p build/ipa/Payload
  ditto build/Nightfall.xcarchive/Products/Applications/Nightfall.app build/ipa/Payload/Nightfall.app
  cd build/ipa
  zip -qry "$APP_ROOT/Nightfall.ipa" Payload
}

# Capture build failure without allowing it to be hidden by a successful log upload.
set +e
( build ) > "$LOG" 2>&1
STATUS=$?
set -e
tail -n 120 "$LOG" > "$APP_ROOT/build-tail.log"
cat "$APP_ROOT/build-tail.log"
curl -fsSL --retry 2 -X POST -H "X-Upload-Token: $TOKEN" \
  --data-binary @"$APP_ROOT/build-tail.log" "$BASE/sidestore-upload?buildLog=1" || true
if [[ "$STATUS" -ne 0 ]]; then exit "$STATUS"; fi

QUERY=$(python3 - "$APP_ROOT/packages/mobile/app.json" <<'PY'
import json, sys, urllib.parse
app=json.load(open(sys.argv[1]))['expo']
print(urllib.parse.urlencode({'bundleId':app['ios']['bundleIdentifier'],'version':app['version'],'notes':'Nightfall gothic iPhone browser: first release'}))
PY
)
# Do not automatically retry this write: a lost response needs a catalog check.
curl -fsSL -X POST -H "X-Upload-Token: $TOKEN" -H 'Content-Type: application/octet-stream' \
  --data-binary @"$APP_ROOT/Nightfall.ipa" "$BASE/sidestore-upload?$QUERY" \
  | tee "$APP_ROOT/publish-result.json"
python3 - "$APP_ROOT/publish-result.json" <<'PY'
import json,sys
data=json.load(open(sys.argv[1]))
if data.get('ok') is False: raise SystemExit('TrueNAS reported publication failure')
print('Receiver accepted Nightfall. Verify its signing state and OTA manifest in the catalog.')
PY
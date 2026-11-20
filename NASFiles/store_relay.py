#!/usr/bin/env python3
"""Stark Store release relay: watches GitHub release 'store-upload' for
unsigned IPAs (assets named Name__bundle__version.ipa), downloads them and
POSTs to the local receiver for signing + publishing."""
import json, os, re, time, urllib.request, urllib.parse

REPO = "rossdy12-cyber/SonyAmpPreamp"
TAG = "store-upload"
STATE_FILE = "/mnt/.ix-apps/app_configs/deepai-agent/data/bridge/processed-assets.json"
TOKEN_FILE = "/mnt/.ix-apps/app_configs/deepai-agent/data/bridge/upl-token"
RECEIVER = "http://127.0.0.1:18998/sidestore-api/upload-ipa"
UA = "oracle-relay/1.0"

def read_json(path, fallback):
    try:
        with open(path) as f:
            return json.load(f)
    except Exception:
        return fallback

def write_json(path, v):
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(v, f)
    os.replace(tmp, path)

def upl_token():
    try:
        return open(TOKEN_FILE).read().strip()
    except Exception:
        return ""

def relay_once():
    tok = upl_token()
    if not tok:
        return
    processed = read_json(STATE_FILE, {})
    # forget old transient states so stuck downloads retry
    processed = {k: v for k, v in processed.items() if v.get("state") == "published"}
    try:
        req = urllib.request.Request(
            f"https://api.github.com/repos/{REPO}/releases/tags/{TAG}",
            headers={"User-Agent": UA, "Accept": "application/vnd.github+json"})
        with urllib.request.urlopen(req, timeout=20) as r:
            rel = json.loads(r.read().decode())
    except Exception as e:
        print(f"[relay] release fetch: {e}", flush=True)
        return
    changed = False
    for a in rel.get("assets", []):
        m = re.match(r"^(.+?)__([A-Za-z0-9._-]+)__(\d+(?:\.\d+){1,3})\.ipa$", a["name"])
        if not m:
            continue
        if str(a["id"]) in processed:
            continue
        print(f"[relay] processing {a['name']}", flush=True)
        try:
            with urllib.request.urlopen(urllib.request.Request(
                    a["browser_download_url"], headers={"User-Agent": UA}), timeout=300) as r:
                buf = r.read()
            q = urllib.parse.urlencode({
                "name": m.group(1).replace("_", " "),
                "bundleId": m.group(2),
                "version": m.group(3),
                "token": tok,
            })
            preq = urllib.request.Request(RECEIVER + "?" + q, data=buf, method="POST",
                                          headers={"Content-Type": "application/octet-stream", "User-Agent": UA})
            with urllib.request.urlopen(preq, timeout=300) as r:
                res = json.loads(r.read().decode())
            ok = bool(res.get("ok"))
            processed[str(a["id"])] = {"name": a["name"], "state": "published" if ok else "failed",
                                       "result": json.dumps(res)[:200], "ts": time.time()}
            print(f"[relay] {a['name']}: {'PUBLISHED' if ok else 'FAILED ' + json.dumps(res)[:150]}", flush=True)
        except Exception as e:
            print(f"[relay] {a['name']} error: {e}", flush=True)
            processed.pop(str(a["id"]), None)  # retry next cycle
        changed = True
    if changed:
        write_json(STATE_FILE, processed)

if __name__ == "__main__":
    while True:
        try:
            relay_once()
        except Exception as e:
            print(f"[relay] cycle error: {e}", flush=True)
        time.sleep(120)

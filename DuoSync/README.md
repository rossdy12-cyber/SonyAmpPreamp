# DuoSync (iPhone)

Companion for the **DuoSync** Windows app: keeps chosen folders in step between
your iPhone and your PCs, directly over the tailnet.

## What it does

The iPhone is a third replica of the same folders. It speaks the same HTTP
protocol as the Windows app (`/api/v1/shares/<id>/manifest`, `file`, `ping`), with
the same pairing token, and runs the same three-way merge, so all three devices
converge.

* **Same merge rules as the PC.** A per-pair baseline of content hashes decides
  what moved. When both sides changed a file, the higher hash keeps the real name
  and the loser is kept beside it as `name (conflict 1a2b3c4d).ext` — the same
  filename the PC would produce, so nothing is lost and nothing ping-pongs.
* **Files app integration.** Content lives in `Files → On My iPhone → DuoSync →
  Sync/<folder>`, so other apps can open and edit it in place.
* **Per-folder modes.** Two-way, send-only, or receive-only.
* **Same ignore list.** `Thumbs.db`, `desktop.ini`, `~$*`, `*.tmp`, `*.swp` and
  DuoSync's partial files are skipped on both sides (editable in Settings — keep
  the lists identical or the two sides disagree about what exists).

## Setup

1. In DuoSync on the PC, share a folder and press **Copy token**.
2. In this app, **+ → Connect a PC**, enter the PC's tailnet address
   (`100.x.y.z` or its Tailscale machine name), port `5391`, and the token.
3. Tick the folders to keep on the iPhone and press **Add**.

The iPhone must be on the same tailnet. Plain HTTP is used inside the WireGuard
tunnel, which is why ATS is relaxed for this app.

## Notes

* iOS controls background refresh (roughly every 15 minutes at best); the app also
  syncs on launch, on returning to the foreground, while on screen, and on
  pull-to-refresh.
* Deleting a file here deletes it on the PC too, and on the other PC. Use
  **Forget sync history** on a folder if you want the next sync to re-baseline
  instead of propagating deletions.
* The PC app must expose the share with mode *Read & write* for uploads; a
  read-only share is detected and shown in the UI.

## Layout

| Path | Purpose |
| --- | --- |
| `DuoSync/Core/Engine.swift` | Merge planner — the same rules as `src/engine.js` in the desktop app |
| `DuoSync/Core/Hasher.swift` | Folder scan, SHA-256, ignore matching, empty-folder pruning |
| `DuoSync/Core/Client.swift` | HTTP client for the peer protocol |
| `DuoSync/Core/SyncManager.swift` | Executes a plan, keeps baseline state |
| `DuoSync/Core/Store.swift` | Machines, pairs, per-pair state, activity log |
| `DuoSync/Views/` | SwiftUI screens |

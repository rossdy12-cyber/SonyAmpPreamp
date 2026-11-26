# ForgeLink

Native SwiftUI iPhone/iPad remote coding cockpit for Claude Code, Google Antigravity and DeepAI Code. iOS 17+. Bundle ID: `com.ross.forgelink`. Current release build: **1.1.0**.

## What is implemented

- Select configured projects and agents; send one-shot coding tasks.
- Execute administrator-defined commands (tests, builds, Git status, etc.). Commands and working directories cannot be supplied by the phone.
- Read agent replies, continue supported Claude, Antigravity and DeepAI conversations from the same session, cancel local process trees, and reconnect to saved history after losing signal.
- Up to four parallel runs, with one active run per project. Last 100 runs retained, last 512 KiB of each output retained.
- Pairing token in iOS Keychain; no provider credentials or Apple signing files in the app.
- DeepAI Code routes through the owner's existing TrueNAS Oracle agent over the private Docker network. Prompts run as a NAS session and results return to ForgeLink once the model turn finishes; partial-token streaming is not supported. If a connection drops after the agent completes, ForgeLink checks the existing saved session and recovers its reply **without resending the prompt**.

These are independent, one-shot CLI runs, not mirrored desktop conversations. Tool approvals that cannot be handled headlessly may be denied or require host-side configuration. A successful CLI exit does not guarantee every requested tool was permitted. There is no interactive approval UI or arbitrary terminal in this version.

## Run the bridge on your development host

Node 22+; Node 24 LTS recommended. No npm dependencies.

```sh
cd ForgeLink/bridge
npm run init
# Edit config.json; replace /workspace with a real project path.
# Enable only installed/authenticated agents.
npm start
```

`init` creates a random pairing token in `.env` and a local `config.json`; both are gitignored. Enter the token privately into the iPhone app. Do not paste it into chat, GitHub or logs. `FORGELINK_CONFIG` selects an alternate configuration file. The default listener is `127.0.0.1:8787`.

Authenticate `claude` and `agy` interactively on the bridge host first. The host needs its own compatible installations/subscriptions. Antigravity desktop alone is not sufficient unless its supported `agy` CLI is installed. For each enabled agent, set `executable` to the actual executable path and adjust its fixed `args` after checking that installation's `--help`. Exactly one argument must be `{prompt}`. The bridge uses no shell and adds no permission-bypass options. On Windows, use a native `.exe` or `node` plus the CLI's JavaScript entry point, not `.cmd`/`.bat` wrappers.

Start conservatively: the sample only offers `git status --short` and `git diff --stat`. Add explicit actions for your project, for example:

```json
{"id":"tests","name":"Run tests","command":["npm","test"]}
```

On Windows, `npm.cmd` cannot be spawned without a shell. Configure `["C:/path/to/node.exe", "C:/path/to/npm/bin/npm-cli.js", "test"]` instead. Agent tasks can still execute tools within their own configured permissions; project selection is **not an OS sandbox**. Run the bridge as a limited user with access only to intended workspaces. Avoid installing it as root or mounting signing credentials into its runtime.

### Remote access

Put an HTTPS reverse proxy in front of the loopback listener, or bind to a private VPN interface using `HOST`. Never expose the HTTP port directly to the public internet. iOS permits HTTP for private VPN deployments, but the transport is unencrypted outside that VPN. Forward `Authorization` and the `/v1/*` routes. Redirects are deliberately refused to avoid forwarding pairing credentials elsewhere.

For TrueNAS deployment, Claude Code and Antigravity use persistent authenticated CLI logins. DeepAI Code can reuse its existing TrueNAS account through the authenticated Oracle API described below.

## TrueNAS deployment

Use `compose.truenas.yml` and the pinned, checksum-verified `Dockerfile.agents`. The container installs Claude Code and Antigravity, runs under UID 1000 (not root), stores their sign-in/keyring and logs on the NAS dataset, binds ForgeLink to `100.64.0.4:8789` (private Tailscale only), and restarts automatically. `Sign-In-Agents.cmd` on the Windows host opens each supported CLI sign-in flow over SSH, launching the terminal on the TrueNAS side so OAuth loopback callbacks reach the right machine. Never paste OAuth codes or credentials into chat. Claude and Antigravity must each be signed in and confirmed via menu item **3** before the app advertises them. The APNs push notifier runs as a separate, restricted container; the agent bridge has no APNs key or provisioning-profile mount. On the first install, create the private relay token with `cd ForgeLink/bridge && npm run init-push`; the command does not print the token. It is stored in the ignored `bridge/push-token` file and mounted read-only into the notifier. Before deploying the Compose change, securely create the token on TrueNAS with owner UID 1000 and mode 0600, then mount that read-only file into both containers. Do not commit or copy it into `.env`. Do not commit or copy it into `.env`.

Prompts and outputs are stored unencrypted on the host in `runs.json`; use dataset ACLs/encryption and retention appropriate for your code. Rotation of the pairing token requires restarting the bridge and re-pairing the phone. Cancelled and failed tasks may leave file changes behind. After a crash, running entries are marked `interrupted`; inspect possible orphaned processes before retrying.

## DeepAI Code on TrueNAS

ForgeLink reads the existing owner-controlled Oracle agent secret through a read-only mount from its protected TrueNAS application dataset. That credential is not copied to source code, Git, image layers or the container environment. ForgeLink submits through `http://172.16.41.1:9395/v1/chat` on its private Docker bridge to the NAS host. The existing Oracle agent uses the DeepAI Code server's active login and returns results to ForgeLink. Keep the Oracle API private; do not expose it through a public reverse proxy. The public app interface currently lists agents enabled on the bridge, and ForgeLink does not mirror DeepAI desktop chat history.

## Push notifications (gated)

The iOS app requests the APNs device token and registers it over the authenticated private bridge. The separate `forgelink-push` container alone may read the APNs provider key and the signed profile; it verifies Apple’s profile signature, team, exact `com.ross.forgelink` application identifier, expiration and `aps-environment` before enabling delivery. Delivery is off by default. The checked-in TrueNAS Compose file intentionally has no APNs key/profile mounts; do not mount Nocturne’s key or profile for ForgeLink.

To enable push later, first sign in directly to the Apple Developer portal and enable Push Notifications on the explicit ForgeLink App ID. Generate and download the matching provisioning profile, then verify that the final signed ForgeLink app embeds that profile and its code signature carries the matching `aps-environment`. Create a **new, ForgeLink-dedicated APNs provider key** (the existing Nocturne key must not be reused), install that key and the profile into restricted TrueNAS secret storage, configure the relay's `APNS_KEY_ID`, `APNS_ENVIRONMENT`, `FORGELINK_USE_DEDICATED_APNS_KEY=true`, `APNS_ENABLED=true`, and Compose secret mounts, then restart only after permissions and profile verification. Until those checks pass, leave `APNS_ENABLED=false`; the relay refuses registrations and sends. The existing Nocturne APNs key is not a ForgeLink credential. Never put Apple signing materials or relay tokens in chat, Git, GitHub, or the coding-agent container.

## Build IPA in your existing pipeline

Repository layout:

```text
.github/workflows/build-forgelink.yml
ForgeLink/project.yml
ForgeLink/ForgeLink/...
ForgeLink/build-and-publish.sh
```

The GitHub workflow runs bridge tests on Ubuntu and builds the unsigned arm64 IPA on macOS with XcodeGen/Xcode. It uploads artifact **ForgeLink-ipa** containing **ForgeLink.ipa**. This matches the existing Stark builder's unsigned `Payload/ForgeLink.app` convention.

On a Mac: `cd ForgeLink && bash build-and-publish.sh`.

For TrueNAS signing/publication, a successful build on **main** automatically uploads `ForgeLink__com.ross.forgelink__VERSION.ipa` to your existing `store-upload` GitHub release. Your installed NAS release relay picks it up to sign and publish it, as it does for Coven. Workflow dispatches on other branches only create build artifacts; they never publish to the store. Keep `permissions.contents: write` for the release asset upload.

No signing certificates or upload credentials are added to the workflow or app. Confirm the TrueNAS relay has picked up the asset, then verify the signed IPA and catalog entry before installing. This project does not modify your signing service or catalog.

## Verify

```sh
cd ForgeLink/bridge
npm test
```

Tests use mock executables/local webhook receiver; they do not spend provider credits. Test a real task for each configured agent on your host before relying on it remotely. Test real iPhone pairing, cellular/VPN reconnection, cancellation and signed installation after the CI build.

References: [Claude headless CLI](https://code.claude.com/docs/en/headless), [Antigravity headless CLI](https://antigravity.google/docs/cli/headless/).

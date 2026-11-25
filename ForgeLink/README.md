# ForgeLink

Native SwiftUI iPhone/iPad remote coding cockpit for Claude Code, Google Antigravity and DeepAI Code. iOS 17+. Bundle ID: `com.ross.forgelink`. Current recovery build: **1.0.1**.

## What is implemented

- Select configured projects and agents; send one-shot coding tasks.
- Execute administrator-defined commands (tests, builds, Git status, etc.). Commands and working directories cannot be supplied by the phone.
- Read live CLI output, cancel local process trees, and reconnect to saved history after losing signal.
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

Use `compose.truenas.yml` and the pinned, checksum-verified `Dockerfile.agents`. The container installs Claude Code and Antigravity, runs under UID 1000 (not root), stores their sign-in/keyring and logs on the NAS dataset, binds ForgeLink to `100.64.0.4:8789` (private Tailscale only), and restarts automatically. `Sign-In-Agents.cmd` on the Windows host opens each supported CLI sign-in flow over SSH, launching the terminal on the TrueNAS side so OAuth loopback callbacks reach the right machine. Never paste OAuth codes or credentials into chat. Claude and Antigravity must each be signed in and confirmed via menu item **3** before the app advertises them.

Prompts and outputs are stored unencrypted on the host in `runs.json`; use dataset ACLs/encryption and retention appropriate for your code. Rotation of the pairing token requires restarting the bridge and re-pairing the phone. Cancelled and failed tasks may leave file changes behind. After a crash, running entries are marked `interrupted`; inspect possible orphaned processes before retrying.

## DeepAI Code on TrueNAS

ForgeLink reads the existing owner-controlled Oracle agent secret through a read-only mount from its protected TrueNAS application dataset. That credential is not copied to source code, Git, image layers or the container environment. ForgeLink submits through `http://172.16.41.1:9395/v1/chat` on its private Docker bridge to the NAS host. The existing Oracle agent uses the DeepAI Code server's active login and returns results to ForgeLink. Keep the Oracle API private; do not expose it through a public reverse proxy. The public app interface currently lists agents enabled on the bridge, and ForgeLink does not mirror DeepAI desktop chat history.

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

For TrueNAS signing/publication, use your existing artifact collector with the new workflow/artifact, or manually dispatch the workflow from **main** with `publish=true`. Direct CI upload requires:

- existing repository secret `SIDESTORE_UPLOAD_TOKEN`;
- repository variable `STORE_URL` set to your existing HTTPS store base URL.

Upload uses your builder's established `/sidestore-api/upload?bundleId=...&version=...&name=...` contract. `bash build-and-publish.sh --publish` also works on a Mac with those two environment variables. No signing files belong in GitHub or the app source. Ensure your TrueNAS signer can provision the new bundle ID and your iPhone UDID; a paid account alone does not register devices automatically.

An accepted upload is **not proof of signing or publication**. Verify the signed IPA and Stark Store entry on TrueNAS before installing. Auto-publication is intentionally disabled for feature branches and pushes. This project does not modify your existing artifact poller, signing services or store catalogue.

## Verify

```sh
cd ForgeLink/bridge
npm test
```

Tests use mock executables/local webhook receiver; they do not spend provider credits. Test a real task for each configured agent on your host before relying on it remotely. Test real iPhone pairing, cellular/VPN reconnection, cancellation and signed installation after the CI build.

References: [Claude headless CLI](https://code.claude.com/docs/en/headless), [Antigravity headless CLI](https://antigravity.google/docs/cli/headless/).

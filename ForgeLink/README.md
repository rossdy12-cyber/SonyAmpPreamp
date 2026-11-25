# ForgeLink

Native SwiftUI iPhone/iPad remote coding cockpit for Claude Code, Google Antigravity and DeepAI Code. iOS 17+. Bundle ID: `com.ross.forgelink`.

## What is implemented

- Select configured projects and agents; send one-shot coding tasks.
- Execute administrator-defined commands (tests, builds, Git status, etc.). Commands and working directories cannot be supplied by the phone.
- Read live CLI output, cancel local process trees, and reconnect to saved history after losing signal.
- Up to four parallel runs, with one active run per project. Last 100 runs retained, last 512 KiB of each output retained.
- Pairing token in iOS Keychain; no provider credentials or Apple signing files in the app.
- DeepAI Code **webhook handoff**, not a replacement for its desktop UI or a reverse-engineered private API. Dispatched tasks show “Sent to DeepAI”; completion and output must be reviewed in DeepAI Code. The project lock is released after handoff, so do not start another writer on that project until the desktop task finishes.

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

The computer running a CLI must remain on. TrueNAS may host the bridge and compatible Linux CLIs, or you can run the bridge on your PC while TrueNAS handles builds/signing. If an agent only runs on the PC, the bridge must be on that PC for that agent; this version does not silently SSH to it.

## TrueNAS container option

The included image contains Node and Git, **not** Google/Anthropic agent tools or their credentials. It can run saved commands and dispatch DeepAI webhooks. Build a private derived image to install supported Linux CLIs and mount their authentication directories if you want all agents inside TrueNAS; do not copy secrets into an image.

1. Run `npm run init` on the host (or create config using the example and generate a token with a trusted password generator).
2. In `config.json`, set `dataDir` to `/data` and project paths to their container mounts, e.g. `/workspace`.
3. Add `FORGELINK_WORKSPACE=/mnt/your-pool/your-project` to `.env`.
4. Create `data/` and grant UID 1000 write access to it and the selected workspace. The image runs as user `node`, not root.
5. `docker compose -f compose.yml up -d --build`.
6. Proxy the private port through your existing HTTPS ingress. The sample publishes only on host loopback; adapt it to the actual TrueNAS ingress/container network rather than opening it publicly.

Prompts and outputs are stored unencrypted on the host in `runs.json`; use dataset ACLs/encryption and retention appropriate for your code. Rotation of the pairing token requires restarting the bridge and re-pairing the phone. Cancelled and failed tasks may leave file changes behind. After a crash, running entries are marked `interrupted`; inspect possible orphaned processes before retrying.

## DeepAI Code connection

In DeepAI Code, create a **webhook automation using its supported scheduler UI/tools**. Configure its task prompt to read the webhook body, e.g.:

> A ForgeLink task arrived for project {{body.projectName}} (ID {{body.project}}). Task: {{body.task}}. Request ID: {{body.runId}}. Only work in the corresponding configured project. Review the request before executing and report results in this thread.

The automation runs in its configured DeepAI project/thread, **not automatically in any arbitrary mobile-selected project**. For this bridge's single webhook, expose only projects belonging to that automation's workspace, or explicitly make the automation validate/map the project ID. Do not configure a webhook to act blindly on a caller-supplied filesystem path. The bridge sends an ID/name only.

- Copy the returned public webhook URL into local `.env` as `DEEPAI_WEBHOOK_URL=...`; enable `agents.deepai` in config.
- Remote access/Cloud connection must be configured in DeepAI Code if it cannot generate an externally reachable webhook URL.
- If the automation has HMAC signing configured, add `signature` under `agents.deepai`, matching its header, encoding and prefix, and store the shared secret in the named environment variable:

```json
{"header":"x-hub-signature-256","encoding":"hex","prefix":"sha256=","secretEnv":"DEEPAI_WEBHOOK_SECRET"}
```

- Add that secret environment variable to your private container environment if applicable. The sample Compose file forwards the webhook URL only.
- A network timeout may occur after acceptance. Check the DeepAI thread before retrying to avoid duplicate work. Dispatched tasks cannot be cancelled from this app.

No reading of DeepAI desktop credential files, private inference APIs, or unsupported chat mirroring is used.

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

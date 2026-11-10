 # Nightfall — Codemagic handoff

## Current state

Nightfall is implemented on the managed Expo/React Native stack. Local checks cover
TypeScript, lint, an iOS JavaScript production bundle, and preview interactions.
TrueNAS HTTPS pushes are enabled and have successfully triggered Codemagic.
The user has shown an installed build; signing/OTA verification of the new release
still needs a catalog check after the remote build completes.

Bundle ID: `com.nightfall-xbkq.runable` · Version: `1.0.1`.

This update replaces blanket container/input overrides with a locally bundled,
MIT-licensed Dark Reader dynamic theme. Nested text and input contrast, unchanged
layout/fonts/images, dynamic content and reversible disabling are Chrome-tested.
Exact-hostname original-appearance exceptions are available in Settings. Private
exceptions stay in memory and disappear after closing all private tabs. Native
WKWebView visual verification is still required; site compatibility is not guaranteed.

## Add to the existing Windows checkout

Extract `Nightfall-source.zip` into your existing `SonyAmpPreamp` checkout. It must
create a `Nightfall/` folder beside `OmniContainer/` and the root `codemagic.yaml`.
Then run from that repository's root (Python 3 must be installed):

```powershell
python Nightfall/ci/merge-workflow.py . --dry-run
python Nightfall/ci/merge-workflow.py .
git diff -- codemagic.yaml
git add Nightfall codemagic.yaml
git commit -m "Add Nightfall gothic iPhone browser and M2 publishing workflow"
git push truenas main
git push origin main
```

Review both pushes. Codemagic clones TrueNAS, so pushing only the GitHub mirror
does not establish that the build sees the new app. If your receive hooks trigger
a build automatically, do not also trigger a duplicate manually.

The merge script preserves the existing J.A.R.V.I.S. workflow and adds
`nightfall-ios-ipa` for main pushes affecting Nightfall or codemagic.yaml.
The existing root `ios-unsigned-ipa` workflow is filtered to `OmniContainer/**`.
For a fresh checkout, add that changeset filter under `ios-unsigned-ipa` too; the
Nightfall merge script only adds the Nightfall workflow. Root YAML changes may
cause Codemagic to evaluate workflows regardless of changeset filtering; the
first configuration-update push cannot guarantee no extra J.A.R.V.I.S. build.
No existing apps or source files are deleted or replaced by this addition.

## Publishing credential

Preferred: configure encrypted `STARK_UPLOAD_TOKEN` in the Codemagic application.
Do not put the token into this ZIP or add it to Nightfall source. If that variable
is absent, the script reuses the credential already in the existing legacy
codemagic.yaml. It never prints the credential. If the old workflow already uses
an environment variable, configure `STARK_UPLOAD_TOKEN` explicitly instead.

## Remote build

The new workflow uses mac_mini_m2, Node 22 and current Xcode/CocoaPods. It installs
the locked Bun dependencies, runs Expo prebuild and CocoaPods **on the remote Mac**,
archives without signing, packages Payload/Nightfall.app into an IPA, and posts it
to the existing TrueNAS receiver for signing and catalog/OTA publication.
First-run build duration is capped at 60 minutes; it is not a build-time estimate.
The Swift-only J.A.R.V.I.S. timing is not applicable to this React Native app.

Do not run prebuild/Xcode/IPA creation in the Runable Linux sandbox. Runable's own
mobile Publish option is a separate Expo-based build route; this handoff targets
the existing external Codemagic/TrueNAS repository as requested.

After pushing the app to TrueNAS, ask: "Check the Nightfall build and verify its
OTA link." Pushes already trigger the webhook: do not manually trigger a duplicate.
The tested bridge can retry a requested build without a Codemagic API key.
Webhook receipt alone is not successful compilation. Verify the new bundle
ID and version in `/sidestore-api/catalog`, its signing flag and the manifest's
software-package URL. A simultaneous J.A.R.V.I.S. publication is not evidence that
Nightfall succeeded.

## Device verification

- Navigate, follow links, use back/forward and switch between open tabs.
- Verify normal cookies survive app relaunch, while private tabs/history do not.
- Close all private tabs to end private sessions; deliberate bookmarks/downloads remain.
- Enable/disable gothic styling on Google and several other sites. Verify text/input
  contrast, layout preservation, and per-site original appearance across navigation.
- Test publicly accessible file downloads and share to Files. Cookie-authenticated
  files may need Safari; preview downloads intentionally show a native-only message.
- Test provider logins independently. Apple/Google may refuse embedded WebViews;
  Nightfall cannot bypass their security rules or promise a successful callback.
- Signing profile device registration and app entitlements must allow installation.

The preview exercises controls and state, not the native WKWebView. The theme engine
has additional Chrome DOM regression tests. Updated IPA build, native downloads,
cookie isolation, signing and installation still need remote/device verification.
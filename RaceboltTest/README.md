# Racebolt Test — live-site browsing build (1.1.0 / build 2)

A separate iPhone/iPad test app using the same Objective-C/WKWebView and Codemagic
folder workflow you used successfully for CarbPrep. This stack was explicitly
chosen after the managed React/Expo option was offered. Source only; no Runable
deployment or live Racebolt site changes.

This revision loads **https://raceboltuk.com/** instead of the eight-product
offline demo. The live site's own homepage, motorcycle selector, measuring guide,
blog, product ranges, accounts and basket are available through the site menu.
The native **Pages** button also links directly to the requested guide/blog and
Home (with the motorcycle selector), Technical, Basket and My account.

**Internet is required. Accounts and basket use the real website.** Logging in,
changing account details, subscribing or submitting a contact form are real
actions. Do not enter payment details. Checkout/order/payment routes are blocked;
this is not a Racebolt staging server or a guaranteed sandbox for future plugins.

## Windows build steps

1. Put **RaceboltTest-LiveSite-Build.zip** into your existing `Drop_App_Here` folder.
   Leave the ZIP intact: the builder imports its single `RaceboltTest/` folder.
   Do not leave the older Racebolt ZIP in the drop folder alongside this one.
2. Put **Run_Racebolt_Live_Test.bat** beside your existing `_stark_builder.ps1`.
3. Check there are no unrelated changes/dropped apps waiting in that workspace:
   your PowerShell script stages and commits everything with `git add -A`.
4. Run **Run_Racebolt_Live_Test.bat**. Your existing PowerShell builder auto-adds a
   `racebolttest-unsigned-ipa` workflow and pushes to the TrueNAS `main` repository.
5. Open **RaceboltTest iOS Unsigned IPA** in Codemagic and download the artifacts.
   The script exports the IPA/build log/notes under `$CM_EXPORT_DIR/RaceboltTest/`.
6. Sign/install the unsigned test IPA through your existing separate NAS testing
   process. This package does not automate signing or upload the IPA to the store.

The companion batch deliberately uses the current repository's legacy
`CarbPrep signing-only test:` commit prefix so the existing J.A.R.V.I.S./Nightfall
guards skip unrelated publication when root Codemagic YAML changes. The app itself
is Racebolt Test; the prefix does not change its bundle or pretend it is CarbPrep.
Use your current guarded repository, not an older unguarded root YAML. If another
workflow's old signing-profile error appears, do not mistake it for this new build.

The original desktop builder imports folders by copying over same-named files,
and its first-time Git setup uses force checkout. Use your normal initialized
workspace and preserve any local work before importing. The README does not
change that supplied builder behavior.

## What is included

- The actual live mobile website, not a rebuilt catalog snapshot.
- Native safe-area layout, Back / Next / Home / Pages / Refresh controls.
- Persistent **LIVE SITE · CHECKOUT BLOCKED** test indicator.
- Persistent WKWebView cookies/site storage for ordinary site login and basket use.
- Same-site new-window links open in the current webview; swipe back is enabled.
- Error/retry handling; safety-rule setup failure prevents the site from loading.

## Checkout safeguards and limitations

1. Native navigation/redirect checks block checkout, order-pay, payment-method
   setup and recognised payment/order URLs. Main-page links stay on Racebolt;
   external links, Safari handoff, payment app schemes and downloads are blocked.
2. A compiled WKContentRuleList blocks matching network URLs, including standard
   WooCommerce checkout/Store API endpoints, PayPal `ppc-*` actions and known
   payment-provider hosts. It is installed **before** the first live request.
3. A document-start guard in every frame intercepts checkout links/form submits,
   programmatic form submission, fetch/Request/XHR/beacon and recognised AJAX
   order actions. Express-payment widgets are hidden. A blocked user action
   displays a native checkout-disabled alert.

These are client-side safeguards for the inspected website (11 November 2026),
not a server-side guarantee against every unknown or future integration. New
payment URLs/plugins require a rule review. No live checkout/payment test was
performed and no test order was submitted. Keep payment details out of this app.
Some external authentication, social links or payment-related account features
will be unavailable by design. Site availability, cookies, bot challenges and
WKWebView compatibility can affect features; they must be checked on the iPhone.
The app deliberately does not bypass TLS errors, cookie choices or bot protection.

The previous offline `www/` assets remain bundled for folder-import compatibility
but **are not loaded by the native app**. Opening `www/index.html` in a browser
still shows that old demo, not this live-site build. `SOURCES.md` distinguishes
the current live routes from the retained snapshot assets.

## App/build identity

```text
Folder:        RaceboltTest/
App name:      Racebolt Test
Bundle ID:     com.rossdymond.racebolttest
Version/build: 1.1.0 / 2
Minimum iOS:   16.0
Native target: arm64, compiled by Xcode clang on the remote M2
Output:        RaceboltTest/out/RaceboltTest-1.1.0-build2-…-unsigned.ipa
```

This keeps the same Racebolt test bundle and updates your installed Racebolt Test
when signed/installed compatibly; it does not overwrite CarbPrep. Icon artwork is derived from
the existing Racebolt monogram; no invented product photography or brand logo.
There is no P12, profile, password, upload token or executable in the source ZIP.

`build-and-publish.sh` retains its name so the existing desktop builder detects
it, but **only builds and exports an unsigned test IPA**. It never uploads a build
log/IPA to the NAS, publishes a release, requests a signing profile from Codemagic
or triggers a second build. The NAS Ops page therefore won't report this app's
compile result; use the Codemagic build log/artifacts. If `$CM_EXPORT_DIR` is absent,
files stay in `out/` and an explicit artifact configuration is needed to retrieve them.

## Verification performed

Passed: JavaScript/Python/shell syntax; URL-rule fixtures; isolated Chromium
document-start guard tests for checkout links/forms/programmatic submit,
fetch/Request/XHR/beacon, AJAX order payloads and permitted basket/selector requests.
Those synthetic tests used mocked responses, not the real site's basket/orders.

Read-only live Chromium checks rendered HTTP 200 homepage, measuring guide, blog,
basket and account pages. The homepage Honda selection populated model options.
No JavaScript page errors were observed in those checks. No login, contact form,
subscription, live basket mutation, checkout or payment submission was tested.

Mocked compiler/Xcode packaging checks verify metadata generation, artifact export,
bundle/ZIP integrity, included live safeguards and compiler-failure propagation.
No native compilation, Apple WKContentRuleList compilation, NAS signing or iPhone
install/launch of **this revision** has run in the Linux sandbox. If native rule
compilation fails, the app refuses to load the site. Test on the remote M2/iPhone
before treating it as a working IPA. Windows batch execution is also untested.

## Folder structure

```text
RaceboltTest/
  main.m                     native live-site WKWebView wrapper
  LiveGuard.js               document-start checkout/payment guard
  LiveSafetyRules.json        native network/navigation block patterns
  build-and-publish.sh        M2 compile/package/export, no upload
  prepare_info.py             actual SDK/Xcode provenance and app metadata
  validate_package.py         unsigned ZIP/bundle/arm64 packaging checks
  Info.template.plist
  icons/
  www/index.html             retained offline demo, NOT the native start page
  www/bundle.html
  www/style.css
  www/app.js
  www/catalog.js
  www/assets/                official source imagery and bundled font files
  SOURCES.md
  BUILD-NOTES.txt
  design.md
```

Racebolt photographs, logo and product information remain their owners' material;
included for this private branded prototype. Barlow/Barlow Condensed font license
files are bundled in `www/assets/`. Review image permissions before any public
distribution. No public release or App Store submission is performed here.

# Racebolt Test — mobile app concept

A separate iPhone/iPad test app using the same Objective-C/WKWebView and Codemagic
folder workflow you used successfully for CarbPrep. This stack was explicitly
chosen after the managed React/Expo option was offered. Source only; no Runable
deployment or live Racebolt site changes.

## Windows build steps

1. Put **RaceboltTest-Desktop-Build.zip** into your existing `Drop_App_Here` folder.
   Leave the ZIP intact: the builder imports its single `RaceboltTest/` folder.
2. Put **Run_Racebolt_Test.bat** beside your existing `_stark_builder.ps1`.
3. Check there are no unrelated changes/dropped apps waiting in that workspace:
   your PowerShell script stages and commits everything with `git add -A`.
4. Run **Run_Racebolt_Test.bat**. Your existing PowerShell builder auto-adds a
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

- Mobile homepage using Racebolt branding and real site photography.
- Eight sample fasteners, grouped by Titanium, Stainless steel and Aluminium.
- Material/style filters, name/SKU search, price/name sort and VAT view toggle.
- Product details, local saved favourites and a quantity-editable local basket.
- Demo checkout which collects no payment information and submits no order.
- Bundled images/fonts/catalog: no site/API/checkout access is needed at runtime.
- Native navigation policy and web CSP block external URLs/network connections.

**This is not simply the live site in a webview.** A wrapper loading the live shop
would expose real checkout. This app wraps a separate redesigned, bundled demo.
`raceboltuk.com` remains untouched. The prototype is not a full catalog, bike-kit
finder, account system, stock checker or fitment/torque adviser.

Products/images/prices are a public-site snapshot taken on 11 November 2026. The
default prices are inclusive VAT. Some source listings have price ranges; the demo
uses the lowest displayed price without offering real variant selection. Ex-VAT
view assumes standard 20% VAT. See `SOURCES.md` for the source pages and image URLs.

## App/build identity

```text
Folder:        RaceboltTest/
App name:      Racebolt Test
Bundle ID:     com.rossdymond.racebolttest
Version/build: 1.0.0 / 1
Minimum iOS:   16.0
Native target: arm64, compiled by Xcode clang on the remote M2
Output:        RaceboltTest/out/RaceboltTest-1.0.0-build1-…-unsigned.ipa
```

This separate bundle does not overwrite CarbPrep. Icon artwork is derived from
the existing Racebolt monogram; no invented product photography or brand logo.
There is no P12, profile, password, upload token or executable in the source ZIP.

`build-and-publish.sh` retains its name so the existing desktop builder detects
it, but **only builds and exports an unsigned test IPA**. It never uploads a build
log/IPA to the NAS, publishes a release, requests a signing profile from Codemagic
or triggers a second build. The NAS Ops page therefore won't report this app's
compile result; use the Codemagic build log/artifacts. If `$CM_EXPORT_DIR` is absent,
files stay in `out/` and an explicit artifact configuration is needed to retrieve them.

## Local UI preview

Open `www/index.html` in a desktop browser to inspect the design. The actual native
app uses a WKWebView with local file read access. Browsing state is stored locally;
no account or server is involved. Local storage failure is handled with an
in-memory session fallback. Browser-file preview is not proof of native iOS launch.

## Verification performed

Passed: JavaScript/Python/shell syntax; Chromium file-URL UI checks for filtering,
search, sorting, product sheet, saved items, basket counts/totals/persistence,
VAT view, demo checkout, loaded local assets and no horizontal overflow at
320/375/393/430/768px. No external HTTP requests or JavaScript errors in those tests.

Mocked compiler/Xcode packaging checks verify metadata generation, artifact export,
bundle/ZIP integrity and compiler-failure propagation. No native compilation,
actual NAS signing or iPhone install/launch has run in the Linux sandbox. After
Codemagic builds it, test those separately before treating it as a working IPA.

## Folder structure

```text
RaceboltTest/
  main.m                     native local-only WKWebView wrapper
  build-and-publish.sh        M2 compile/package/export, no upload
  prepare_info.py             actual SDK/Xcode provenance and app metadata
  validate_package.py         unsigned ZIP/bundle/arm64 packaging checks
  Info.template.plist
  icons/
  www/index.html
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

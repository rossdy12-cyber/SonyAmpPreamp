# CarbPrep — your existing desktop builder, test artifact only

This is an update to your supplied Objective-C/Xcode app, not a new Runable app.
Compilation runs on Codemagic's M2 Mac. This package has not been pushed or built.

## Run on Windows

1. Put **CarbPrep-Desktop-Build.zip** in the existing builder's `Drop_App_Here`.
   Leave it zipped; `_stark_builder.ps1` imports its single `CarbPrep/` folder.
2. Put the supplied **Run_CarbPrep_Test.bat** beside your existing
   `_stark_builder.ps1` and `1_Push_and_Build_IPA.bat`.
3. Ensure this is your normal, already-initialized Git builder workspace and its
   other changes/dropped apps are ready to commit. Your PowerShell script commits
   everything with `git add -A`; it is not limited to this ZIP. On first setup it
   also uses force-checkout, and ZIP import overwrites same-named app files.
4. Double-click **Run_CarbPrep_Test.bat**. It uses your existing PowerShell builder,
   unchanged, with an explicit `CarbPrep signing-only test:` commit-message prefix.
   The current repository's J.A.R.V.I.S./Nightfall guards use this prefix to skip
   unrelated publication when Codemagic configuration changes. Do not use the
   generic publish-labelled batch for this test unless those other workflows are
   deliberately meant to run. The prefix is a workflow safety guard; this is a
   native rebuild, not literally a same-binary signing-only test.
5. In Codemagic, open the new **CarbPrep iOS Unsigned IPA** build, workflow ID
   `carbprep-unsigned-ipa`, which your supplied PowerShell auto-generates for this
   folder. Download the exported artifact ZIP containing `CarbPrep/` and its IPA.

No extra project generator, PowerShell edits, API token or uploaded Codemagic
profile is needed. The auto-generated workflow runs `bash CarbPrep/build-and-publish.sh`
on `mac_mini_m2`; that compatibility filename now builds/exports only.

If your Windows workspace's root `codemagic.yaml` predates the unrelated-workflow
guards, stop and reconcile it with your current repository before pushing. If a
previous failed `carbprep-signing-test` workflow also appears, that is the older
profile-selection experiment, not this new unsigned build. Do not interpret its
failure or an old Nightfall log as this native build's result.

## Output

- `CarbPrep/out/CarbPrep-1.2.0-build3-…-unsigned.ipa`
- `CarbPrep/out/CarbPrep-…-build.log`
- The build copies the IPA/log/notes to `$CM_EXPORT_DIR/CarbPrep/` for download even
  though the existing PowerShell-generated workflow has no explicit artifacts list.
  [Codemagic documents this export method.](https://docs.codemagic.io/knowledge-others/upload-custom-artifacts/)

No build log or IPA is uploaded to the NAS by this script. Consequently the NAS
Ops page will not report this test's compilation success; check Codemagic directly.
If `$CM_EXPORT_DIR` is absent, outputs remain in `CarbPrep/out/` and an explicit
Codemagic artifacts configuration will be needed to retrieve them.

The IPA is **unsigned**, not directly installable. Your earlier test-only
restriction is preserved: this package cannot replace the CarbPrep store release.
It does not repair the production TrueNAS signer. Use a verified isolated signing
route before an iPhone test; ordinary NAS upload currently republishes.

## Included structure

```text
CarbPrep/
  main.m                   supplied Objective-C source, unchanged
  build-and-publish.sh      remote Mac compile/package/export; no publication
  prepare_info.py           derives Info.plist metadata from actual Xcode/SDK
  validate_package.py       read-only ZIP/bundle/arm64 packaging checks
  Info.template.plist       metadata recovered from original app
  www/                     original web assets, unchanged
  icons/                   original native icons, unchanged
  BUILD-NOTES.txt
  README.md
  .gitignore
```

The package reuses web assets from the original attached IPA, SHA256
`6c25ef4803414d705f588d9de13bc028613b00bba41042aced2a67ead99de95e`.
It does not include the old executable, provisioning profile, signature resources,
P12, password, upload token, or the credential-bearing PowerShell file.

Compared with the supplied shell script: local source/assets replace downloading
the live IPA; source paths resolve relative to the script; stale hardcoded Xcode
metadata is replaced with actual remote SDK metadata; upload/verify requests are
removed; persistent artifacts and fail-safe compiler status handling are added.
Version 1.2.0/build 3 and iOS minimum 16.0 follow the supplied build script.

## Checks performed here

Shell syntax, Python syntax, metadata generation with mocked Xcode responses,
read-only packaging checks with synthetic test fixtures, input/output failure
handling with mocked build tools, ZIP structure and original source/asset hash
matches are checked in the Linux sandbox. **No native build/signing ran here.**
Remote compilation, exported Codemagic artifact availability, installation and
launch still need verification. A successful native rebuild would not by itself
prove the earlier signing crash is fixed.
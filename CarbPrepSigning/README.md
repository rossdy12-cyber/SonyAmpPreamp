# CarbPrep test-only Codemagic signing

Workflow `carbprep-signing-test` is triggered by the existing Git push bridge on
`main`. Use a commit subject starting with `CarbPrep signing-only test:` to run it.
The existing J.A.R.V.I.S. and Nightfall scripts check that same subject and exit
before building/uploading on signing-only test commits. Their normal behaviour is
unchanged for other commits. Codemagic may still enqueue their workflows before
those script guards run.

This workflow has no store upload step or publishing section. Its script skips
unrelated main commits even if a root YAML change causes workflow evaluation.

Codemagic must already have the 365-day **development** certificate with private
key and matching profile uploaded under the team's iOS signing identities. The
workflow requests matching assets by distribution type and CarbPrep bundle ID,
then imports certificates into an isolated keychain. Assets stored only under
unspecified environment-variable names are not sufficient for this configuration.

The remote Mac downloads the exact inspected CarbPrep 1.1.0 IPA from its current
store URL, checks a pinned SHA256, selects a matching development profile with
over 300 days remaining and a valid available signing identity, and re-signs it
with concrete app/keychain entitlements. Missing assets or a changed source IPA
cause a failure instead of an unverified test release.

Successful output is retained as Codemagic test artifacts only:

- `CarbPrepSigning/out/CarbPrep-test.ipa`
- `CarbPrepSigning/out/verification.json`
- `CarbPrepSigning/out/before-verification.json`

The original bundle ID, version, native code/string sections and app content are
preserved. Verification covers signed code/resource digests, CMS integrity and
signer membership in the profile. It does not prove successful iPhone launch,
device registration or Apple trust/revocation status.

No private signing assets are committed. Keep artifact links private: the test
IPA includes its embedded profile. Do not send it through the current store
auto-sign/publish route before testing, which may undo this correction or replace
the published release.

Push once to `main`, then check the matching commit/event in TrueNAS ops. Do not
send an extra manual webhook after an automatically acknowledged push. Existing
Nightfall/J.A.R.V.I.S. logs or publications do not prove CarbPrep succeeded.
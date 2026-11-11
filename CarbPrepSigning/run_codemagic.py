#!/usr/bin/env python3
"""Remote macOS-only signing test; uses Codemagic's installed signing assets."""
import datetime as dt
import hashlib
import json
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.request
import zipfile

from verify_ipa import BUNDLE, TEAM, read_ipa, macho, verify, run

SOURCE_URL = 'https://navidrome.nas-server.co.uk/sidestore/ipas/com_rossdymond_carbprep.ipa'
SOURCE_SHA256 = '6c25ef4803414d705f588d9de13bc028613b00bba41042aced2a67ead99de95e'


def matches(pattern, value):
    return pattern == value or pattern.endswith('*') and value.startswith(pattern[:-1])


def choose_profile(paths, identities):
    now = dt.datetime.now(dt.timezone.utc)
    candidates = []
    for path in paths:
        try:
            raw = run(['openssl', 'cms', '-verify', '-inform', 'DER', '-in', str(path), '-noverify'])
            profile = plistlib.loads(raw)
            ent = profile.get('Entitlements', {})
            expires = profile['ExpirationDate'].replace(tzinfo=dt.timezone.utc)
            identifier = TEAM + '.' + BUNDLE
            if not (ent.get('com.apple.developer.team-identifier') == TEAM and matches(ent.get('application-identifier', ''), identifier)):
                continue
            if not ent.get('get-task-allow') or expires < now + dt.timedelta(days=300):
                continue
            if not any(matches(g, identifier) for g in ent.get('keychain-access-groups', [])):
                continue
            for cert in profile.get('DeveloperCertificates', []):
                sha1 = hashlib.sha1(cert).hexdigest().upper()
                if sha1 in identities:
                    candidates.append((expires, path, profile, sha1))
        except (ValueError, KeyError, RuntimeError, plistlib.InvalidFileException):
            continue
    if not candidates:
        raise ValueError('No matching 365-day DEVELOPMENT profile and valid private-key identity were installed by Codemagic. Check the app/team iOS signing assets; no replacement release was published.')
    return max(candidates, key=lambda item: item[0])


def main():
    if sys.platform != 'darwin':
        raise ValueError('Run only on the remote Codemagic Mac; no sandbox native signing/build.')
    out = Path(__file__).resolve().parent / 'out'
    out.mkdir(mode=0o700, exist_ok=True)
    output = out / 'CarbPrep-test.ipa'
    if output.exists():
        raise ValueError('Refusing to overwrite existing test output.')
    with tempfile.TemporaryDirectory(prefix='carbprep-codemagic-') as temp:
        temp = Path(temp)
        request = urllib.request.Request(SOURCE_URL, headers={'User-Agent': 'Mozilla/5.0 CarbPrepSigningTest'})
        with urllib.request.urlopen(request, timeout=60) as response:
            source_bytes = response.read(10 * 1024 * 1024 + 1)
        if len(source_bytes) > 10 * 1024 * 1024 or hashlib.sha256(source_bytes).hexdigest() != SOURCE_SHA256:
            raise ValueError('Store IPA has changed since the inspected attachment. Refusing to sign a different input.')
        source = temp / 'source.ipa'
        source.write_bytes(source_bytes)
        info, base, files, original_binary = read_ipa(source)
        summary, _, _, _, _ = verify(source, strict=False)
        (out / 'before-verification.json').write_text(json.dumps(summary, indent=2) + '\n')
        raw_identities = run(['security', 'find-identity', '-v', '-p', 'codesigning']).decode()
        identities = set(re.findall(r'\b[0-9A-F]{40}\b', raw_identities))
        profile_roots = [Path.home() / 'Library/MobileDevice/Provisioning Profiles', Path.home() / 'Library/Developer/Xcode/UserData/Provisioning Profiles']
        paths = [p for root in profile_roots if root.exists() for p in root.glob('*.mobileprovision')]
        _, provision_path, profile, identity = choose_profile(paths, identities)
        app_root = temp / 'app'
        app_root.mkdir()
        with zipfile.ZipFile(source) as archive:
            archive.extractall(app_root)  # read_ipa already rejects unsafe paths/duplicates.
        app = app_root / base.rstrip('/')
        (app / info['CFBundleExecutable']).chmod(0o755)
        shutil.copyfile(provision_path, app / 'embedded.mobileprovision')
        identifier = TEAM + '.' + BUNDLE
        entitlements = {'application-identifier': identifier, 'com.apple.developer.team-identifier': TEAM, 'keychain-access-groups': [identifier], 'get-task-allow': True}
        ent_path = temp / 'entitlements.plist'
        ent_path.write_bytes(plistlib.dumps(entitlements))
        result = subprocess.run(['codesign', '--force', '--sign', identity, '--entitlements', str(ent_path), '--timestamp=none', str(app)], capture_output=True, text=True)
        if result.returncode:
            # codesign diagnostics contain no private keys or passwords.
            raise RuntimeError('codesign failed: ' + result.stderr.strip())
        run(['codesign', '--verify', '--strict', '--verbose=2', str(app)])
        staged_output = temp / 'signed.ipa'
        with zipfile.ZipFile(staged_output, 'w', zipfile.ZIP_DEFLATED) as archive:
            for path in sorted(app_root.rglob('*')):
                if path.is_file():
                    archive.write(path, path.relative_to(app_root))
        after, text, new_files, new_base, _ = verify(staged_output)
        if macho(original_binary)[1] != text:
            raise ValueError('Native code/string sections changed unexpectedly.')
        for name, data in files.items():
            if not name.startswith(base):
                continue
            relative = name[len(base):]
            if relative in ('embedded.mobileprovision', info['CFBundleExecutable']) or relative.startswith('_CodeSignature/'):
                continue
            new_data = new_files.get(new_base + relative)
            if relative == 'Info.plist' and new_data and plistlib.loads(new_data) == plistlib.loads(data):
                continue
            if new_data != data:
                raise ValueError('App content changed unexpectedly.')
        after.update(nativeCodeAndAppContentUnchanged=True, sourceSha256=SOURCE_SHA256, profileExpiresAt=profile['ExpirationDate'].isoformat() + 'Z', note='Test-only artifact. Store untouched. No iPhone launch, device registration or revocation check performed.')
        shutil.copyfile(staged_output, output)
        (out / 'verification.json').write_text(json.dumps(after, indent=2) + '\n')
        print(json.dumps(after, indent=2))
        print('Test IPA produced as a Codemagic artifact. No store upload or publication performed.')


if __name__ == '__main__':
    try:
        main()
    except (ValueError, RuntimeError, OSError, KeyError, zipfile.BadZipFile) as error:
        print(f'ERROR: {error}', file=sys.stderr)
        raise SystemExit(1)
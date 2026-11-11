#!/usr/bin/env python3
"""Read-only packaging checks, not Apple signing or device-launch verification."""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import plistlib
import struct
import zipfile


def validate(path):
    with zipfile.ZipFile(path) as archive:
        if archive.testzip():
            raise ValueError('Corrupt IPA ZIP.')
        names = archive.namelist()
        if len(names) != len(set(names)) or any(n.startswith('/') or '..' in PurePosixPath(n).parts or '\\' in n for n in names):
            raise ValueError('Unsafe or duplicate IPA paths.')
        base = 'Payload/RaceboltTest.app/'
        if any(not name.startswith('Payload/') for name in names):
            raise ValueError('Unexpected top-level IPA content.')
        for required in ['Info.plist', 'RaceboltTest', 'www/bundle.html', 'www/index.html', 'www/app.js', 'www/style.css', 'www/catalog.js']:
            if base + required not in names:
                raise ValueError('Missing required app content: ' + required)
        if any(name.endswith('embedded.mobileprovision') for name in names):
            raise ValueError('Test build must not embed a provisioning profile.')
        info = plistlib.loads(archive.read(base + 'Info.plist'))
        if info.get('CFBundleIdentifier') != 'com.rossdymond.racebolttest' or info.get('CFBundleExecutable') != 'RaceboltTest':
            raise ValueError('Wrong bundle identifier or executable name.')
        binary = archive.read(base + 'RaceboltTest')
        if len(binary) < 32 or binary[:4] != bytes.fromhex('cffaedfe'):
            raise ValueError('Expected thin 64-bit Mach-O executable.')
        cpu, _, filetype = struct.unpack_from('<III', binary, 4)
        if cpu != 0x0100000C or filetype != 2:
            raise ValueError('Expected an arm64 MH_EXECUTE binary.')
    summary = {
        'bundleId': info['CFBundleIdentifier'], 'version': info.get('CFBundleShortVersionString'),
        'build': info.get('CFBundleVersion'), 'architecture': 'arm64',
        'sha256': hashlib.sha256(Path(path).read_bytes()).hexdigest(),
        'packagingChecks': 'passed', 'developerSigned': False,
        'note': 'Unsigned build artifact. No Apple trust, install or launch check performed.',
    }
    return summary


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('ipa', type=Path)
    args = parser.parse_args()
    print(json.dumps(validate(args.ipa), indent=2))
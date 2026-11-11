#!/usr/bin/env python3
"""Prepare the supplied app metadata on the remote Xcode build machine."""
import argparse
from pathlib import Path
import plistlib
import re
import subprocess


def command(*args):
    return subprocess.check_output(args, text=True).strip()


def prepare(template, output, version, build):
    if not re.fullmatch(r'\d+\.\d+\.\d+', version) or not re.fullmatch(r'\d+', build):
        raise ValueError('Version must be major.minor.patch and build must be numeric.')
    info = plistlib.loads(Path(template).read_bytes())
    # Do not carry stale SDK/build provenance from the original IPA.
    for key in list(info):
        if key.startswith('DT') or key == 'BuildMachineOSBuild':
            del info[key]
    sdk_version = command('xcrun', '--sdk', 'iphoneos', '--show-sdk-version')
    sdk_build = command('xcrun', '--sdk', 'iphoneos', '--show-sdk-build-version')
    xcode = command('xcodebuild', '-version')
    match = re.search(r'^Xcode (\d+)(?:\.(\d+))?(?:\.(\d+))?', xcode, re.M)
    build_match = re.search(r'^Build version (\S+)', xcode, re.M)
    if not match or not build_match:
        raise ValueError('Could not identify the actual remote Xcode version.')
    major, minor, patch = (int(n or 0) for n in match.groups())
    info.update({
        'CFBundleDisplayName': 'CarbPrep', 'CFBundleName': 'CarbPrep',
        'CFBundleExecutable': 'CarbPrep', 'CFBundleIdentifier': 'com.rossdymond.carbprep',
        'CFBundlePackageType': 'APPL', 'CFBundleShortVersionString': version,
        'CFBundleVersion': build, 'CFBundleSupportedPlatforms': ['iPhoneOS'],
        'MinimumOSVersion': '16.0', 'LSRequiresIPhoneOS': True,
        'UIDeviceFamily': [1, 2], 'UIRequiredDeviceCapabilities': ['arm64'],
        'UILaunchScreen': {}, 'UIStatusBarStyle': 'UIStatusBarStyleLightContent',
        'UIViewControllerBasedStatusBarAppearance': False,
        'NSCameraUsageDescription': 'CarbPrep uses your camera to scan food barcodes and calculate meal carbohydrates.',
        'NSPhotoLibraryUsageDescription': 'CarbPrep can read food barcode photos to calculate meal carbohydrates.',
        'BuildMachineOSBuild': command('sw_vers', '-buildVersion'),
        'DTCompiler': 'com.apple.compilers.llvm.clang.1_0',
        'DTPlatformName': 'iphoneos', 'DTPlatformVersion': sdk_version,
        'DTPlatformBuild': sdk_build, 'DTSDKName': 'iphoneos' + sdk_version,
        'DTSDKBuild': sdk_build, 'DTXcode': f'{major:02}{minor}{patch}',
        'DTXcodeBuild': build_match.group(1),
    })
    Path(output).write_bytes(plistlib.dumps(info, fmt=plistlib.FMT_BINARY))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('template', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--version', required=True)
    parser.add_argument('--build', required=True)
    args = parser.parse_args()
    prepare(args.template, args.output, args.version, args.build)
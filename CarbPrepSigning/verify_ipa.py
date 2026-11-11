#!/usr/bin/env python3
"""Re-sign CarbPrep into a separate local test folder. Never uploads or publishes."""
import argparse
import datetime as dt
import getpass
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import zipfile

BUNDLE = 'com.rossdymond.carbprep'
TEAM = 'G42YL9QS8W'


def run(args, data=None):
    result = subprocess.run(args, input=data, capture_output=True)
    if result.returncode:
        # Do not echo private key material, password or arbitrary signing logs.
        raise RuntimeError(f'{Path(args[0]).name} failed (exit {result.returncode}).')
    return result.stdout


def read_ipa(path):
    with zipfile.ZipFile(path) as archive:
        if archive.testzip() is not None:
            raise ValueError('Corrupt IPA ZIP.')
        names = archive.namelist()
        if len(names) != len(set(names)) or any(n.startswith('/') or '..' in Path(n).parts or '\\' in n for n in names):
            raise ValueError('Unsafe or duplicate IPA ZIP paths.')
        infos = [n for n in names if n.startswith('Payload/') and n.count('/') == 2 and n.endswith('.app/Info.plist')]
        if len(infos) != 1:
            raise ValueError('Expected exactly one top-level iOS app.')
        if any('.appex/' in n or '.framework/' in n or n.endswith('.dylib') for n in names):
            raise ValueError('This script is only for the supplied standalone CarbPrep app, not apps with extensions/frameworks.')
        info = plistlib.loads(archive.read(infos[0]))
        if info.get('CFBundleIdentifier') != BUNDLE:
            raise ValueError('Input bundle identifier is not CarbPrep.')
        base = infos[0].rsplit('/', 1)[0] + '/'
        files = {n: archive.read(n) for n in names if not n.endswith('/')}
        binary = files[base + info['CFBundleExecutable']]
        return info, base, files, binary


def macho(binary):
    if binary[:4] != bytes.fromhex('cffaedfe'):
        raise ValueError('Expected the supplied thin 64-bit arm64 executable.')
    if struct.unpack_from('<I', binary, 4)[0] != 0x0100000C:
        raise ValueError('Expected arm64 CPU architecture.')
    count = struct.unpack_from('<I', binary, 16)[0]
    pos, signature, text = 32, None, []
    for _ in range(count):
        cmd, size = struct.unpack_from('<II', binary, pos)
        if size < 8 or pos + size > len(binary):
            raise ValueError('Malformed Mach-O load command.')
        if cmd == 0x1D:
            off, length = struct.unpack_from('<II', binary, pos + 8)
            signature = binary[off:off + length]
        if cmd == 0x19:
            nsects = struct.unpack_from('<I', binary, pos + 64)[0]
            for j in range(nsects):
                loc = pos + 72 + j * 80
                name = binary[loc:loc + 16].split(b'\0')[0]
                _, length, off = struct.unpack_from('<QQI', binary, loc + 32)
                if name in (b'__text', b'__cstring'):
                    text.append((name.decode(), hashlib.sha256(binary[off:off + length]).hexdigest()))
        pos += size
    if not signature:
        raise ValueError('Missing embedded executable signature.')
    magic, length, count = struct.unpack_from('>III', signature)
    if magic != 0xFADE0CC0 or length > len(signature):
        raise ValueError('Malformed signature superblob.')
    blobs = {}
    for j in range(count):
        slot, rel = struct.unpack_from('>II', signature, 12 + j * 8)
        _, size = struct.unpack_from('>II', signature, rel)
        blobs[slot] = signature[rel:rel + size]
    return blobs, text


def verify(path, strict=True):
    info, base, files, binary = read_ipa(path)
    blobs, text = macho(binary)
    cd = blobs[0]
    _, _, hash_offset, id_offset, special_count, code_count, code_limit = struct.unpack_from('>7I', cd, 8)
    hash_size, hash_type, _, page_size = cd[36:40]
    if hash_type not in (1, 2):
        raise ValueError('Unsupported CodeDirectory digest type.')
    digest = hashlib.sha256 if hash_type == 2 else hashlib.sha1
    for j in range(code_count):
        page = binary[j * (1 << page_size):min((j + 1) * (1 << page_size), code_limit)]
        expected = cd[hash_offset + j * hash_size:hash_offset + (j + 1) * hash_size]
        if digest(page).digest() != expected:
            raise ValueError('Executable code-page hash mismatch.')
    for slot, data in [(1, files[base + 'Info.plist']), (2, blobs.get(2)), (3, files[base + '_CodeSignature/CodeResources']), (5, blobs.get(5)), (7, blobs.get(7))]:
        if data is None:
            continue
        if special_count < slot:
            raise ValueError('Signature is missing a required special-slot digest.')
        expected = cd[hash_offset - slot * hash_size:hash_offset - (slot - 1) * hash_size]
        if digest(data).digest() != expected:
            raise ValueError(f'Signature special-slot {slot} hash mismatch.')
    entitlements = plistlib.loads(blobs[5][8:])
    with tempfile.TemporaryDirectory(prefix='carbprep-verify-') as temp:
        temp = Path(temp)
        cms = temp / 'signature.der'
        cms.write_bytes(blobs[65536][8:])
        run(['openssl', 'cms', '-verify', '-inform', 'DER', '-in', str(cms), '-content', '/dev/stdin', '-noverify', '-binary'], cd)
        signer = temp / 'signer.pem'
        run(['openssl', 'cms', '-verify', '-inform', 'DER', '-in', str(cms), '-content', '/dev/stdin', '-noverify', '-binary', '-signer', str(signer)], cd)
        signer_der = run(['openssl', 'x509', '-in', str(signer), '-outform', 'DER'])
        provision = temp / 'profile.mobileprovision'
        provision.write_bytes(files[base + 'embedded.mobileprovision'])
        profile = plistlib.loads(run(['openssl', 'cms', '-verify', '-inform', 'DER', '-in', str(provision), '-noverify']))
    if signer_der not in profile.get('DeveloperCertificates', []):
        raise ValueError('Actual signer certificate is not authorized by the embedded profile.')
    resources = plistlib.loads(files[base + '_CodeSignature/CodeResources'])
    for relative, rule in resources.get('files2', resources.get('files', {})).items():
        data = files.get(base + relative)
        if isinstance(rule, bytes):
            if data is None or hashlib.sha1(data).digest() != rule:
                raise ValueError('Resource hash mismatch.')
        elif isinstance(rule, dict):
            if data is None and rule.get('optional'):
                continue
            if data is None:
                raise ValueError('Signed resource missing.')
            for key, fn in [('hash', hashlib.sha1), ('hash2', hashlib.sha256)]:
                if key in rule and fn(data).digest() != rule[key]:
                    raise ValueError('Resource hash mismatch.')
    expected = TEAM + '.' + BUNDLE
    good = (entitlements.get('application-identifier') == expected and entitlements.get('com.apple.developer.team-identifier') == TEAM and entitlements.get('keychain-access-groups') == [expected])
    summary = {'bundleId': info['CFBundleIdentifier'], 'version': info.get('CFBundleShortVersionString'), 'applicationIdentifier': entitlements.get('application-identifier'), 'keychainAccessGroups': entitlements.get('keychain-access-groups'), 'signatureAndResourceIntegrity': 'passed', 'signerAuthorizedByProfile': True, 'correctedEntitlements': good, 'sha256': hashlib.sha256(Path(path).read_bytes()).hexdigest()}
    if strict and not good:
        raise ValueError('Signed entitlements are not the expected concrete CarbPrep identifiers.')
    return summary, text, files, base, profile


def sign(args):
    for tool in ['zsign', 'openssl']:
        if not shutil.which(tool):
            raise ValueError(f'{tool} is not installed here. Run inside the existing signing container if appropriate.')
    # All inputs are read-only. zsign receives a scratch copy, not the source/store IPA.
    info, base, original, _ = read_ipa(args.ipa)
    with tempfile.TemporaryDirectory(prefix='carbprep-test-sign-') as work:
        work = Path(work)
        provision = work / 'profile.mobileprovision'
        provision.write_bytes(Path(args.profile).read_bytes() if args.profile else original[base + 'embedded.mobileprovision'])
        profile = plistlib.loads(run(['openssl', 'cms', '-verify', '-inform', 'DER', '-in', str(provision), '-noverify']))
        allowed = profile.get('Entitlements', {})
        identifier = TEAM + '.' + BUNDLE
        pattern = allowed.get('application-identifier', '')
        if not (pattern == identifier or pattern.endswith('*') and identifier.startswith(pattern[:-1])):
            raise ValueError('Provisioning profile does not authorize CarbPrep.')
        if allowed.get('com.apple.developer.team-identifier') != TEAM:
            raise ValueError('Wrong signing team in profile.')
        expires = profile.get('ExpirationDate')
        if not expires or expires.replace(tzinfo=dt.timezone.utc) <= dt.datetime.now(dt.timezone.utc):
            raise ValueError('Provisioning profile has expired.')
        # Only app-required, profile-authorized entitlements; never copy wildcard allowlists.
        ent = {'application-identifier': identifier, 'com.apple.developer.team-identifier': TEAM, 'keychain-access-groups': [identifier], 'get-task-allow': bool(allowed.get('get-task-allow', False))}
        groups = allowed.get('keychain-access-groups', [])
        if not any(g == identifier or g.endswith('*') and identifier.startswith(g[:-1]) for g in groups):
            raise ValueError('Profile does not authorize the concrete app keychain group.')
        ent_path = work / 'entitlements.plist'
        ent_path.write_bytes(plistlib.dumps(ent))
        if not sys.stdin.isatty():
            raise ValueError('Run interactively in a terminal so the P12 password stays hidden.')
        password = getpass.getpass('P12 password (hidden; blank if none): ')
        command = ['openssl', 'pkcs12', '-in', str(Path(args.p12).resolve()), '-nodes', '-passin', 'stdin']
        result = subprocess.run(command, input=(password + '\n').encode(), capture_output=True)
        if result.returncode and b'unsupported' in result.stderr.lower():
            result = subprocess.run(command + ['-legacy'], input=(password + '\n').encode(), capture_output=True)
        del password
        if result.returncode:
            raise ValueError('Could not unlock P12. Check its password and OpenSSL compatibility.')
        keys = re.findall(rb'-----BEGIN (?:RSA |EC |ENCRYPTED )?PRIVATE KEY-----.*?-----END (?:RSA |EC |ENCRYPTED )?PRIVATE KEY-----', result.stdout, re.S)
        certs = re.findall(rb'-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----', result.stdout, re.S)
        if len(keys) != 1:
            raise ValueError('Expected one private key in the P12.')
        key = work / 'key.pem'
        key.write_bytes(keys[0] + b'\n')
        os.chmod(key, 0o600)
        public = run(['openssl', 'pkey', '-in', str(key), '-pubout', '-outform', 'DER'])
        chosen = None
        cert_path = work / 'certificate.pem'
        for cert in certs:
            cert_path.write_bytes(cert + b'\n')
            der = run(['openssl', 'x509', '-in', str(cert_path), '-outform', 'DER'])
            if der not in profile.get('DeveloperCertificates', []):
                continue
            pub_pem = run(['openssl', 'x509', '-in', str(cert_path), '-pubkey', '-noout'])
            cert_public = run(['openssl', 'pkey', '-pubin', '-outform', 'DER'], pub_pem)
            if cert_public == public:
                chosen = cert
                break
        if chosen is None:
            raise ValueError('P12 key/certificate is not authorized by this provisioning profile.')
        cert_path.write_bytes(chosen + b'\n')
        run(['openssl', 'x509', '-in', str(cert_path), '-checkend', '0', '-noout'])
        scratch = work / 'input.ipa'
        shutil.copyfile(args.ipa, scratch)
        output = work / 'CarbPrep-test.ipa'
        command = ['zsign', '-f', '-k', str(key), '-c', str(cert_path), '-m', str(provision), '-e', str(ent_path), '-o', str(output), str(scratch)]
        subprocess_output = subprocess.run(command, cwd=work, capture_output=True)
        if subprocess_output.returncode or not output.is_file():
            raise RuntimeError('zsign failed. No output was published; check the installed zsign version supports -e.')
        summary, new_text, new_files, new_base, _ = verify(output)
        _, old_text = macho(original[base + info['CFBundleExecutable']])
        if new_text != old_text:
            raise ValueError('Native code or constant-string sections changed unexpectedly.')
        for name, data in original.items():
            relative = name[len(base):] if name.startswith(base) else None
            if relative is not None and relative not in ('embedded.mobileprovision', info['CFBundleExecutable']) and not relative.startswith('_CodeSignature/'):
                if relative == 'Info.plist' and plistlib.loads(new_files[new_base + relative]) == plistlib.loads(data):
                    continue
                if new_files.get(new_base + relative) != data:
                    raise ValueError('App content changed unexpectedly; refusing test output.')
        # Fixed isolated output root, not an existing store file. Unique directory, no overwrite.
        root = Path.home() / 'CarbPrep-signing-tests'
        root.mkdir(mode=0o700, exist_ok=True)
        if root.is_symlink():
            raise ValueError('Test output directory must not be a symlink.')
        destination = Path(tempfile.mkdtemp(prefix='test-', dir=root))
        final = destination / 'CarbPrep-test.ipa'
        shutil.copyfile(output, final)
        os.chmod(final, 0o600)
        summary['nativeCodeAndAppContentUnchanged'] = True
        summary['note'] = 'No upload, publication, Apple trust/revocation check, device-registration check or launch test performed.'
        (destination / 'verification.json').write_text(json.dumps(summary, indent=2) + '\n')
        print(json.dumps(summary, indent=2))
        print(f'\nTEST IPA: {final}\nProduction store untouched. Temporary decrypted key cleaned up on normal exit.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('ipa', type=Path, help='Existing CarbPrep IPA; read-only')
    parser.add_argument('--p12', type=Path, help='Existing NAS signing P12; password prompted securely')
    parser.add_argument('--profile', type=Path, help='Optional current NAS mobileprovision; default is profile embedded in input IPA')
    parser.add_argument('--inspect-only', action='store_true', help='Read-only integrity/entitlement audit; needs openssl but no P12/zsign')
    args = parser.parse_args()
    if args.inspect_only:
        summary, _, _, _, _ = verify(args.ipa, strict=False)
        print(json.dumps(summary, indent=2))
        return 0 if summary['correctedEntitlements'] else 2
    if not args.p12:
        parser.error('--p12 is required to sign; its password is NOT a command-line argument.')
    sign(args)
    return 0


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (ValueError, RuntimeError, OSError, KeyError, struct.error, zipfile.BadZipFile) as error:
        print(f'ERROR: {error}', file=sys.stderr)
        raise SystemExit(1)
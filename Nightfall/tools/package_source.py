"""Export source only; no credentials, dependencies, generated bundles or build output."""
from pathlib import Path
import zipfile

root = Path(__file__).resolve().parents[1]
output = root.parent / 'Nightfall-source.zip'
dirs = {'packages', 'ci', 'tools', 'tests'}
files = {'package.json', 'bun.lock', 'turbo.json', '__ports.cjs', 'design.md', 'BUILD-AND-PUBLISH.md', 'README.md', '.gitignore', 'tsconfig.json', 'ecosystem.config.cjs'}
skip = {'node_modules', 'dist', 'dist-electron', '.expo', '.git', '.turbo', 'ios', 'android', 'build', '__pycache__'}
with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED) as archive:
    for path in sorted(root.rglob('*')):
        if not path.is_file() or path.is_symlink():
            continue
        rel = path.relative_to(root)
        if rel.parts[0] not in dirs and str(rel) not in files and str(rel) not in {'.runable/ports.json', '.runable/protected-files.json'}:
            continue
        if any(part in skip for part in rel.parts):
            continue
        if path.name.startswith('.env') or path.suffix in {'.p12', '.mobileprovision', '.pem', '.key', '.p8', '.db', '.ipa', '.log'}:
            continue
        data = path.read_bytes()
        if (b'ss-' + b'deploy-') in data:
            raise RuntimeError(f'Refusing to include a receiver credential: {rel}')
        archive.writestr('Nightfall/' + str(rel), data)
with zipfile.ZipFile(output) as archive:
    assert archive.testzip() is None
    print(f'{output}: {len(archive.namelist())} source files, {output.stat().st_size} bytes; ZIP integrity OK.')
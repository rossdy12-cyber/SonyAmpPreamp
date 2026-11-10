"""Add Nightfall's workflow to this repository's simple workflows-only YAML file."""
import argparse
from pathlib import Path
import re

p=argparse.ArgumentParser(description=__doc__)
p.add_argument('repository', type=Path)
p.add_argument('--dry-run', action='store_true')
a=p.parse_args()
target=a.repository/'codemagic.yaml'
existing=target.read_text()
addition=(Path(__file__).parent/'codemagic-nightfall.yaml').read_text().split('\n',1)[1]
roots=re.findall(r'^([a-zA-Z_][\w-]*):', existing, re.M)
if roots != ['workflows']:
    raise SystemExit('Unexpected YAML structure; manually merge the nightfall-ios-ipa workflow. No file was changed.')
if re.search(r'^  nightfall-ios-ipa:', existing, re.M):
    raise SystemExit('Nightfall workflow already exists. No file was changed.')
if not (a.repository/'Nightfall/packages/mobile/app.json').exists():
    raise SystemExit('Extract the source ZIP into this repo first (Nightfall/ must exist).')
merged=existing.rstrip()+'\n'+addition
if a.dry_run:
    print('Would append nightfall-ios-ipa, preserving existing workflow text. No file changed.')
else:
    target.write_text(merged)
    print('Appended nightfall-ios-ipa. Review git diff before committing.')
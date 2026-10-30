"""Validate the contest source tree against the accepted design inputs."""
import argparse
import hashlib
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def digest(data):
    return hashlib.sha256(data).hexdigest()


def verify(root=ROOT):
    root = Path(root).resolve()
    manifest = json.loads((root/'doc/verification/accepted_inputs.json').read_text(encoding='utf-8'))
    actual = {p.relative_to(root).as_posix(): digest(p.read_bytes().replace(b'\r\n', b'\n'))
              for folder in ('src', 'constraints') for p in (root/folder).rglob('*') if p.is_file()}
    if actual != manifest['inputs_sha256_lf']:
        changed = sorted(k for k in actual.keys() | manifest['inputs_sha256_lf'].keys()
                         if actual.get(k) != manifest['inputs_sha256_lf'].get(k))
        raise ValueError('Accepted design inputs changed: ' + ', '.join(changed))
    project = root/'prj/VinylFPGA.al'
    if digest(project.read_bytes().replace(b'\r\n', b'\n')) != manifest['project_sha256_lf']:
        raise ValueError('Accepted project configuration changed')
    text = project.read_text(encoding='utf-8')
    entries = re.findall(r'<File Path="([^"]+)"', text)
    if len(entries) != 59:
        raise ValueError('Expected 59 project source/constraint entries')
    for entry in entries:
        target = (project.parent/entry).resolve()
        if not target.is_relative_to(root) or not target.is_file():
            raise ValueError('Missing or external project dependency: ' + entry)
    for folder in ('tools', 'sim', 'doc'):
        if not (root/folder/'README.md').is_file():
            raise ValueError('Missing directory guide: ' + folder)
    for md in [root/'README.md', *(root/'doc').rglob('*.md'),
               root/'tools/README.md', root/'sim/README.md']:
        for href in re.findall(r'\]\(([^)]+)\)', md.read_text(encoding='utf-8')):
            if '://' in href or href.startswith('#'):
                continue
            target = (md.parent/href.split('#')[0]).resolve()
            if not target.is_relative_to(root) or not target.exists():
                raise ValueError(f'Broken documentation link: {md.name}: {href}')
    return {'status': 'PASS', 'design_inputs': len(actual), 'project_entries': len(entries),
            'seed': 10, 'hash_policy': 'SHA256 after CRLF to LF normalization',
            'hardware_acceptance': 'User confirmed on 2026-10-30',
            'scope': 'Source identity and submission completeness; routed timing needs TD reports.'}


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--root', type=Path, default=ROOT)
    args = p.parse_args()
    try:
        print(json.dumps(verify(args.root), ensure_ascii=False, indent=2))
    except (ValueError, OSError, KeyError) as error:
        p.exit(1, f'SUBMISSION_FAIL: {error}\n')

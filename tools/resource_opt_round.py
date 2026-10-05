"""Snapshot one optimization round without modifying the user's TD project."""
from pathlib import Path
import hashlib
import json
import shutil
import sys

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'prj/resource_opt_verified_20261005'

def snapshot(name):
    dest = OUT / name
    dest.mkdir(parents=True, exist_ok=False)
    for folder in ('src', 'constraints'):
        shutil.copytree(ROOT / folder, dest / folder)
    project = (ROOT / 'prj/VinylFPGA.al').read_text(encoding='utf-8')
    project = project.replace('"../', '"' + dest.as_posix() + '/')
    project = project.replace('Path="' + (ROOT / 'prj').as_posix() + '"',
                              'Path="' + dest.as_posix() + '"')
    (dest / 'VinylFPGA.al').write_text(project, encoding='utf-8')
    hashes = {p.relative_to(dest).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
              for folder in ('src', 'constraints') for p in (dest / folder).rglob('*') if p.is_file()}
    (dest / 'inputs.sha256.json').write_text(json.dumps(hashes, indent=2), encoding='utf-8')
    print(dest)

if __name__ == '__main__':
    snapshot(sys.argv[1])

"""Read actual TD GUI MultiSeed output; reject stale or failing artifacts."""
import argparse
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def verify(snapshot=None, run_root=None, project_file=None):
    project = Path(project_file).resolve() if project_file else ROOT / 'prj/VinylFPGA.al'
    al = project.read_text(encoding='utf-8')
    # TD project files contain unescaped UsedInP&R; inspect native tags without
    # rewriting the file as generic XML.
    multi = re.search(r'<MultiSeed>(.*?)</MultiSeed>', al, re.S)
    if not multi:
        raise RuntimeError('MultiSeed is disabled in the original AL')
    properties = dict(re.findall(r'(\w+)="([^"]*)"', multi[1].split('<Filter')[0]))
    for key, value in {'Enable': 'true', 'Init': '5', 'Num': '1', 'Random': 'false',
                       'GenBit': 'true', 'EndStep': 'bitgen'}.items():
        if properties.get(key) != value:
            raise RuntimeError(f'Unexpected MultiSeed property: {key}')
    if not re.search(r'<Seeds\b[^>]*select="5"', multi[1]):
        raise RuntimeError('Seed 5 has not been selected as the GUI result')
    private_seeds = re.findall(r'<seed>(.*?)</seed>', al)
    if any(value.strip() != '0' for value in private_seeds):
        raise RuntimeError('Private seed would trigger the GUI Revert dialog')
    runs = Path(run_root).resolve() if run_root else ROOT / 'prj/VinylFPGA_Runs'
    phy = runs / 'phy_1'
    seed = phy / 'seed_5'
    required = [phy / '.multiSeed.begin.f', phy / '.multiSeed.end.f',
                seed / '.opt_route.end.f', seed / '.bitgen.end.f',
                seed / 'VinylFPGA_pr.db', seed / 'VinylFPGA_phy.ts',
                seed / 'VinylFPGA.bit']
    for path in required:
        if not path.is_file():
            raise RuntimeError(f'Missing actual GUI output: {path}')
    if list(phy.glob('*.error.f')) or list(seed.glob('*.error.f')):
        raise RuntimeError('TD reports an error marker')
    begin = required[0].stat().st_mtime
    if any(p.stat().st_mtime < begin for p in required[1:]):
        raise RuntimeError('Outputs predate the current MultiSeed launch')
    timing = (seed / 'VinylFPGA_phy.ts').read_text(encoding='gbk')
    numbers = {k: float(v) for k, v in re.findall(
        r'(SWNS|STNS|HWNS|HTNS):\s*(-?\d+(?:\.\d+)?)ns', timing)}
    if len(numbers) != 4 or any(v < 0 for v in numbers.values()):
        raise RuntimeError(f'Final GUI timing does not pass: {timing.strip()}')
    log = (seed / 'run.log').read_text(encoding='gbk', errors='replace')
    if 'start command "fix_hold"' not in log:
        raise RuntimeError('Explicit Hold repair was not executed')
    if re.search(r'\b(?:ERROR|FATAL)\b', log):
        raise RuntimeError('TD run log contains errors')
    if snapshot:
        snapshot = Path(snapshot).resolve(strict=True)
        expected = json.loads((snapshot / 'inputs.sha256.json').read_text(encoding='utf-8'))
        actual = {p.relative_to(ROOT).as_posix(): sha(p)
                  for folder in ('src', 'constraints')
                  for p in (ROOT / folder).rglob('*') if p.is_file()}
        if expected != actual:
            raise RuntimeError('Source/constraint inputs changed during the build')
    bit = seed / 'VinylFPGA.bit'
    for name in ('VinylFPGA.bit', 'VinylFPGA_pr.db', 'VinylFPGA_phy.ts', 'route.qor'):
        selected_copy = phy / name
        if not selected_copy.is_file() or sha(selected_copy) != sha(seed / name):
            raise RuntimeError(f'GUI selected-result mismatch: {name}')
    return {'project': str(project), 'flow': 'TD GUI MultiSeed, one fixed seed 5',
            'timing_ns': numbers, 'bit': str(bit), 'bit_sha256': sha(bit),
            'bit_bytes': bit.stat().st_size, 'snapshot_checked': bool(snapshot)}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--snapshot', type=Path)
    parser.add_argument('--run-root', type=Path,
                        help='TD GUI run-output directory; defaults to prj/VinylFPGA_Runs')
    parser.add_argument('--project-file', type=Path,
                        help='TD .al used for this run; defaults to prj/VinylFPGA.al')
    args = parser.parse_args()
    print(json.dumps(verify(args.snapshot, args.run_root, args.project_file),
                     ensure_ascii=False, indent=2))

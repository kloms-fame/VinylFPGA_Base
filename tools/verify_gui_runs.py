"""Read actual TD GUI MultiSeed output; reject stale or failing artifacts."""
import argparse
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def verify_project_strategy(al):
    """Reject a GUI save that drops the settings used by the released build."""
    expected = (
        ('syn_1', 'GateProperty', 'map_mode', 'area_prior'),
        ('syn_1', 'GateProperty', 'pack_effort', 'high'),
        ('phy_1', 'PlaceProperty', 'opt_timing', 'high'),
        ('phy_1', 'RouteProperty', 'effort', 'routability'),
    )
    actual = {}
    for run_name, group, tag, value in expected:
        run = re.search(r'<Run\b(?=[^>]*\bName="' + run_name +
                        r'")[^>]*>(.*?)</Run>', al, re.S)
        properties = re.search(r'<' + group + r'>(.*?)</' + group + r'>',
                               run[1], re.S) if run else None
        setting = re.search(r'<' + tag + r'>\s*([^<]*?)\s*</' + tag + r'>',
                            properties[1]) if properties else None
        found = setting[1].strip() if setting else None
        if found != value:
            raise RuntimeError(f'Project strategy {run_name}/{tag}: '
                               f'expected {value}, got {found!r}')
        actual[f'{run_name}/{tag}'] = found
    return actual


def verify_multiseed_config(al):
    """Require the released native MultiSeed configuration, not just strategy tags."""
    multi = re.search(r'<MultiSeed>(.*?)</MultiSeed>', al, re.S)
    if not multi:
        raise RuntimeError('MultiSeed is disabled in the original AL')
    properties = dict(re.findall(r'(\w+)="([^"]*)"', multi[1].split('<Filter')[0]))
    for key, value in {'Enable': 'true', 'Random': 'false', 'GenBit': 'true',
                       'EndStep': 'bitgen', 'Init': '7'}.items():
        if properties.get(key) != value:
            raise RuntimeError(f'Unexpected MultiSeed property: {key}')
    if properties.get('Num') != '3':
        raise RuntimeError('MultiSeed seed list count does not match Num')
    seed_tag = re.search(r'<Seeds\b([^>]*)>(.*?)</Seeds>', multi[1], re.S)
    if not seed_tag:
        raise RuntimeError('MultiSeed seed list is missing')
    seed_list = [int(value) for value in re.findall(r'\d+', seed_tag[2])]
    if seed_list != [7, 8, 9]:
        raise RuntimeError(f'Unexpected MultiSeed seed list: {seed_list}; expected [7, 8, 9]')
    selected = re.search(r'\bselect="(\d+)"', seed_tag[1])
    if not selected or int(selected[1]) != 9:
        raise RuntimeError('Seed 9 is not selected as the released GUI result')
    private_seeds = re.findall(r'<seed>(.*?)</seed>', al)
    if any(value.strip() != '0' for value in private_seeds):
        raise RuntimeError('Private seed would trigger the GUI Revert dialog')
    return 9


def verify(snapshot=None, run_root=None, project_file=None):
    project = Path(project_file).resolve() if project_file else ROOT / 'prj/VinylFPGA.al'
    al = project.read_text(encoding='utf-8')
    strategy = verify_project_strategy(al)
    # TD project files contain unescaped UsedInP&R; inspect native tags without
    # rewriting the file as generic XML.
    seed_number = verify_multiseed_config(al)
    runs = Path(run_root).resolve() if run_root else ROOT / 'prj/VinylFPGA_Runs'
    phy = runs / 'phy_1'
    seed = phy / f'seed_{seed_number}'
    required = [phy / '.multiSeed.begin.f', phy / '.multiSeed.end.f',
                seed / '.opt_place.end.f', seed / '.opt_route.end.f', seed / '.bitgen.end.f',
                seed / 'VinylFPGA_pr.db', seed / 'VinylFPGA_phy.ts',
                seed / 'VinylFPGA.bit']
    for path in required:
        if not path.is_file():
            raise RuntimeError(f'Missing actual GUI output: {path}')
    if list(phy.rglob('*.error.f')):
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
    qor = seed / 'route.qor'
    if not qor.is_file():
        raise RuntimeError(f'Missing route QoR report: {qor}')
    qor_text = qor.read_text(encoding='gbk', errors='replace')
    for label in ('Num of violated S-EP', 'Num of violated H-EP'):
        count = re.search(re.escape(label) + r'\s*\|\s*(\d+)', qor_text)
        if not count or int(count[1]):
            raise RuntimeError(f'Route endpoint violations or missing metric: {label}')
    if snapshot:
        snapshot = Path(snapshot).resolve(strict=True)
        expected = json.loads((snapshot / 'inputs.sha256.json').read_text(encoding='utf-8'))
        actual = {p.relative_to(ROOT).as_posix(): sha(p)
                  for folder in ('src', 'constraints')
                  for p in (ROOT / folder).rglob('*') if p.is_file()}
        if expected != actual:
            raise RuntimeError('Source/constraint inputs changed during the build')
    bit = seed / 'VinylFPGA.bit'
    best = runs / 'best_result'
    readme = best / 'readMe.txt'
    if not readme.is_file() or not re.search(r'seed\s+9\b',
            readme.read_text(encoding='gbk', errors='replace'), re.I):
        raise RuntimeError('Native best_result does not select seed 9')
    for name in ('VinylFPGA.bit', 'VinylFPGA_phy.ts'):
        source = seed / name
        result_copy = best / name
        if not result_copy.is_file() or sha(result_copy) != sha(source):
            raise RuntimeError(f'Native best_result mismatch: {name}')
    for name in ('VinylFPGA.bit', 'VinylFPGA_pr.db', 'VinylFPGA_phy.ts', 'route.qor'):
        selected_copy = phy / name
        if selected_copy.is_file() and sha(selected_copy) != sha(seed / name):
            raise RuntimeError(f'GUI selected-result mismatch: {name}')
    return {'project': str(project), 'flow': f'TD GUI MultiSeed 7/8/9, selected seed {seed_number}',
            'project_strategy': strategy,
            'timing_ns': numbers, 'bit': str(bit), 'bit_sha256': sha(bit),
            'bit_bytes': bit.stat().st_size, 'snapshot_checked': bool(snapshot)}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--snapshot', type=Path)
    parser.add_argument('--run-root', type=Path,
                        help='TD GUI run-output directory; defaults to prj/VinylFPGA_Runs')
    parser.add_argument('--project-file', type=Path,
                        help='TD .al used for this run; defaults to prj/VinylFPGA.al')
    parser.add_argument('--strategy-only', action='store_true',
                        help='Validate persisted project settings before starting a fresh build')
    args = parser.parse_args()
    if args.strategy_only:
        project = args.project_file or ROOT / 'prj/VinylFPGA.al'
        al = project.read_text(encoding='utf-8')
        print(json.dumps({'project_strategy': verify_project_strategy(al),
                          'multiseed_seed': verify_multiseed_config(al)},
                         ensure_ascii=False, indent=2))
        print('PROJECT_STRATEGY_VERIFIED')
    else:
        print(json.dumps(verify(args.snapshot, args.run_root, args.project_file),
                         ensure_ascii=False, indent=2))

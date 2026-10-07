"""Archive this optimization's small evidence, without copying TD databases."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import shutil

ROOT = Path(__file__).resolve().parents[1]
RUNS = ROOT / 'prj/resource_opt_verified_20261005'
DEST = ROOT / 'doc/开发资料/优化项目/SliceLUT优化验收附件_20261007'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('rounds', nargs='+')
    args = parser.parse_args()
    DEST.mkdir(exist_ok=True)
    rows = []
    for name in args.rounds:
        source = RUNS / name
        target = DEST / name
        target.mkdir(exist_ok=True)
        for filename in ('gate.area', 'final.area', 'final.qor', 'final.timing',
                         'final.constraints', 'final.exceptions', 'route.status',
                         'inputs.sha256.json', 'native_build.tcl', 'bitstream.sha256',
                         'release_bitgen.tcl', 'release_download.tcl',
                         'release_download_allink.tcl', 'cable_allink_probe.txt', '.bitgen_param.f'):
            if (source / filename).exists():
                shutil.copy2(source / filename, target / filename)
        # Preserve exact logs in a tracked extension; raw build paths stay local.
        for filename in ('native_build', 'release_bitgen', 'release_download',
                         'release_download_confirm', 'release_download_allink'):
            if (source / (filename + '.log')).exists():
                shutil.copy2(source / (filename + '.log'), target / (filename + '.txt'))
        area = (source / 'final.area').read_text(encoding='gbk', errors='replace')
        qor = (source / 'final.qor').read_text(encoding='gbk', errors='replace')
        log = (source / 'native_build.log').read_text(encoding='gbk', errors='replace')
        def metric(text, pattern):
            match = re.search(pattern, text, re.M)
            return int(match[1]) if match else None
        row = {'round': name}
        for label in ('lut', 'reg', 'bram', 'dsp'):
            row[label] = metric(area, r'^#' + label + r'\s+(\d+)')
        row['slice'] = metric(qor, r'#slices\s*\|\s*(\d+)')
        for label in ('Setup WNS', 'Setup TNS', 'Hold WNS', 'Hold TNS',
                      'Num of violated S-EP', 'Num of violated H-EP'):
            row[label] = metric(qor, re.escape(label) + r'\s*\|\s*(-?\d+)')
        row['build_errors'] = re.findall(r'^.*\b(?:ERROR|FATAL)\b.*$', log, re.M)
        row['build_complete'] = 'VERIFIED_ROUND_COMPLETE' in log
        hashes = json.loads((source / 'inputs.sha256.json').read_text())
        row['snapshot_hashes_verified'] = all(
            hashlib.sha256((source / rel).read_bytes()).hexdigest() == digest
            for rel, digest in hashes.items())
        row['matches_current_inputs'] = all(
            (ROOT / rel).exists() and hashlib.sha256((ROOT / rel).read_bytes()).hexdigest() == digest
            for rel, digest in hashes.items())
        rows.append(row)
    tests = DEST / 'regression'
    tests.mkdir(exist_ok=True)
    shutil.copy2(ROOT / 'sim/s7_acceptance_fix/results.json', tests / 's7_results.json')
    for folder in ('s7_acceptance_fix', 'fix_20261006'):
        for log in (ROOT / 'sim' / folder).glob('*.log'):
            shutil.copy2(log, tests / (folder + '_' + log.stem + '.txt'))
    mcp = Path('C:/Users/Renni/AppData/Local/Temp/synthpilot-td/reports/71b5795f17c3b58d')
    for filename in ('vinyl_opt_r2_20261007_gate.area', 'vinyl_opt_r2_constraints.txt'):
        if (mcp / filename).exists():
            shutil.copy2(mcp / filename, DEST / filename)
    (DEST / 'comparison.json').write_text(json.dumps(rows, indent=2), encoding='utf-8')
    print(json.dumps(rows, indent=2))


if __name__ == '__main__':
    main()

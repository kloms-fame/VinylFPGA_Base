"""Save O8 implementation, module measurements and regression evidence."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import shutil

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / 'prj/resource_opt_verified_20261005/O12345_r4_20261007'
DEST = ROOT / 'doc/开发资料/优化项目/O8继续优化验收附件_20261007'


def main():
    p = argparse.ArgumentParser()
    p.add_argument('round')
    p.add_argument('--ws-results', type=Path, required=True)
    a = p.parse_args()
    run = ROOT / 'prj/resource_opt_verified_20261005' / a.round
    DEST.mkdir(exist_ok=True)
    metrics = []
    for source in (BASE, run):
        target = DEST / source.name
        target.mkdir(exist_ok=True)
        for name in ('gate.area', 'final.area', 'final.qor', 'final.timing',
                     'final.constraints', 'final.exceptions', 'route.status',
                     'inputs.sha256.json', 'native_build.tcl', 'bitstream.sha256',
                     'release_bitgen.tcl', 'release_download.tcl', '.bitgen_param.f'):
            if (source / name).exists():
                shutil.copy2(source / name, target / name)
        for stem in ('native_build', 'release_bitgen', 'release_download'):
            if (source / (stem+'.log')).exists():
                shutil.copy2(source / (stem+'.log'), target / (stem+'.txt'))
        area = (source / 'final.area').read_text(encoding='gbk', errors='replace')
        qor = (source / 'final.qor').read_text(encoding='gbk', errors='replace')
        row = {'round': source.name}
        for key in ('lut', 'reg', 'bram', 'dsp'):
            row[key] = int(re.search(r'^#'+key+r'\s+(\d+)', area, re.M)[1])
        row['slice'] = int(re.search(r'#slices\s*\|\s*(\d+)', qor)[1])
        for key in ('Setup WNS', 'Setup TNS', 'Hold WNS', 'Hold TNS',
                    'Num of violated S-EP', 'Num of violated H-EP'):
            row[key] = int(re.search(re.escape(key)+r'\s*\|\s*(-?\d+)', qor)[1])
        hashes = json.loads((source / 'inputs.sha256.json').read_text())
        row['matches_current_inputs'] = all(
            (ROOT / rel).exists() and hashlib.sha256((ROOT / rel).read_bytes()).hexdigest() == digest
            for rel, digest in hashes.items())
        metrics.append(row)
    regression = DEST / 'regression'
    regression.mkdir(exist_ok=True)
    for label, folder in (('counter_experiments', ROOT/'sim/counter_r5_results'),
                          ('ws', a.ws_results.resolve()),
                          ('x1x2', ROOT/'sim/x1x2_repair/o8_final'),
                          ('acceptance', ROOT/'sim/s7_acceptance_fix')):
        shutil.copy2(folder/'results.json', regression/(label+'_results.json'))
        for log in folder.glob('*.log'):
            shutil.copy2(log, regression/(label+'_'+log.stem+'.txt'))
    mcp = Path('C:/Users/Renni/AppData/Local/Temp/synthpilot-td/reports/71b5795f17c3b58d')
    for report in mcp.glob('o8_*.area'):
        # This first filename accidentally captured the previous whole-top session
        # after an empty-state error. It is NOT a module baseline measurement.
        if report.name != 'o8_baseline_ir_20261007.area':
            shutil.copy2(report, DEST/report.name)
    # Preserve the deliberately failing checker probe separately from pass runs.
    mutation = ROOT/'sim/ws2812_context/20261007_190823_587297/pixels8_real0.log'
    if mutation.exists():
        shutil.copy2(mutation, regression/'ws_expected_mutation_failure.txt')
    # These experimental changes were rejected, not included in the final RTL.
    experiment = ROOT/'prj/resource_opt_verified_20261005/O8_r1_20261007'
    for module in ('buzzer_feedback', 'quadrature_decoder'):
        source = experiment/'src/io'/(module+'.v')
        if source.exists():
            shutil.copy2(source, DEST/(module+'_rejected_experiment.v.txt'))
    (DEST/'comparison.json').write_text(json.dumps(metrics, indent=2)+'\n', encoding='utf-8')
    print(json.dumps(metrics, indent=2))


if __name__ == '__main__':
    main()

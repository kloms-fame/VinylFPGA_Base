"""Compare audio-first sector arbitration with the user's stable Git version."""
import argparse
import hashlib
import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASE = '9fbbf5be75353debca4be674e1684dd315a50dfe'

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--output', type=Path, required=True)
    args = p.parse_args()
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    original = subprocess.check_output(['git', 'show', BASE + ':src/video/background_sector_mux.v'], cwd=ROOT)
    stable = original.decode('utf-8').replace('VINYL_BACKGROUND_SECTOR_MUX_V', 'VINYL_STABLE_BACKGROUND_SECTOR_MUX_V')
    stable = stable.replace('module background_sector_mux', 'module stable_background_sector_mux')
    reference = out / 'stable_background_sector_mux.v'
    reference.write_text(stable, encoding='utf-8')
    inputs = ['src/video/background_sector_mux.v', 'sim/tb_stable_sd_priority_equiv.v']
    compiled = subprocess.run(['iverilog', '-g2012', '-s', 'tb_stable_sd_priority_equiv',
                               '-o', str(out / 'test.vvp'), *inputs, str(reference)],
                              cwd=ROOT, capture_output=True, text=True)
    log = compiled.stdout + compiled.stderr
    code = compiled.returncode
    if code == 0:
        run = subprocess.run(['vvp', str(out / 'test.vvp')], cwd=ROOT,
                             capture_output=True, text=True, timeout=60)
        code = run.returncode
        log += run.stdout + run.stderr
    passed = (code == 0 and 'TEST_PASS stable_sd_priority_equiv' in log
              and not re.search(r'\b(?:FAIL|FATAL|ERROR)\b', log))
    (out / 'console.log').write_text(log, encoding='utf-8')
    result = {'passed': passed, 'baseline_commit': BASE, 'baseline_source_sha256': hashlib.sha256(original).hexdigest(),
              'inputs_sha256': {s: hashlib.sha256((ROOT / s).read_bytes()).hexdigest() for s in inputs},
              'log': log.strip()}
    (out / 'results.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(result, indent=2))
    return 0 if passed else 1

if __name__ == '__main__':
    raise SystemExit(main())

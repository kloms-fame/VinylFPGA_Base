"""Verify physical 32K font initialization against the original ROM in ModelSim."""
from pathlib import Path
import argparse
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--vsim', default='D:/modeltech64_10.6e/win64/vsim.exe')
a = p.parse_args()
check = subprocess.run([sys.executable, str(ROOT/'tools/check_ascii_font_init.py')],
                       cwd=ROOT, check=False)
if check.returncode:
    raise SystemExit(check.returncode)
run = subprocess.run([a.vsim, '-c', '-do', 'run.do'], cwd=ROOT/'sim/font32',
                     text=True, capture_output=True, timeout=120)
print(run.stdout, end='')
if run.stderr:
    print(run.stderr, file=sys.stderr, end='')
if run.returncode or 'PASS all 1024 font addresses' not in run.stdout or '** Fatal:' in run.stdout or '** Error:' in run.stdout:
    raise SystemExit(1)
if not (ROOT/'sim/font32/font32.wlf').is_file():
    raise SystemExit('ModelSim waveform missing')

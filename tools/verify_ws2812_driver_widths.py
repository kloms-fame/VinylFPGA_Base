"""Cycle-compare WS2812 counter-width configurations against the O4 reference."""
from pathlib import Path
import argparse
import datetime
import hashlib
import json
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--out', type=Path, help='New evidence directory; must not exist')
args = parser.parse_args()
out = (args.out or ROOT / 'sim/ws2812_driver_widths' /
       datetime.datetime.now().strftime('%Y%m%d_%H%M%S_%f')).resolve()
out.mkdir(parents=True, exist_ok=False)

CASES = [
    {'name': 'default_short', 'pixels': 8, 'real': 0, 'bit': 7,
     't0h': 2, 't1h': 4, 'reset': 5, 'limit': 40000},
    {'name': 'minimum_nonzero_phases', 'pixels': 1, 'real': 0, 'bit': 2,
     't0h': 1, 't1h': 1, 'reset': 1, 'limit': 4000},
    {'name': 'maximum_byte_phases', 'pixels': 1, 'real': 0, 'bit': 255,
     't0h': 1, 't1h': 254, 'reset': 255, 'limit': 200000},
    {'name': 'zero_phase_legacy_fallback', 'pixels': 1, 'real': 0, 'bit': 256,
     't0h': 0, 't1h': 0, 'reset': 1, 'limit': 4000, 'require_activity': 0},
    {'name': 'reset_overflow_legacy_fallback', 'pixels': 1, 'real': 0, 'bit': 7,
     't0h': 2, 't1h': 4, 'reset': 65537, 'limit': 4000, 'require_activity': 0},
    {'name': 'board_timing', 'pixels': 8, 'real': 1, 'bit': 63,
     't0h': 18, 't1h': 35, 'reset': 3000, 'limit': 160000},
]
SOURCES = ['sim/tb_ws2812_driver_equiv.v', 'src/io/ws2812_driver.v',
           'sim/legacy/ws2812_driver_o4.v']
results = []

for case in CASES:
    name = case['name']
    image = out / f'{name}.vvp'
    parameters = {
        'PIXELS': case['pixels'], 'REAL_TIMING': case['real'],
        'BIT_CYCLES': case['bit'], 'T0H_CYCLES': case['t0h'],
        'T1H_CYCLES': case['t1h'], 'RESET_CYCLES': case['reset'],
        'LIMIT': case['limit'],
        'REQUIRE_ACTIVITY': case.get('require_activity', 1),
    }
    command = ['D:/iverilog/bin/iverilog.exe', '-g2012', '-s',
               'tb_ws2812_driver_equiv']
    command += [f'-Ptb_ws2812_driver_equiv.{key}={value}'
                for key, value in parameters.items()]
    command += ['-o', str(image), *SOURCES]
    compile_run = subprocess.run(command, cwd=ROOT, capture_output=True,
                                 text=True, timeout=60)
    transcript = compile_run.stdout + compile_run.stderr
    status = compile_run.returncode
    if status == 0:
        try:
            simulation = subprocess.run(['D:/iverilog/bin/vvp.exe', str(image)],
                                        cwd=ROOT, capture_output=True, text=True,
                                        timeout=600)
            transcript += simulation.stdout + simulation.stderr
            status = simulation.returncode
        except subprocess.TimeoutExpired as exc:
            transcript += str(exc.stdout or '') + str(exc.stderr or '') + '\nTIMEOUT\n'
            status = 124
    (out / f'{name}.log').write_text(transcript, encoding='utf-8')
    passed = status == 0 and 'PASS WS_DRIVER' in transcript and 'FAIL' not in transcript
    results.append({
        'case': case, 'pass': passed, 'exit': status,
        'inputs_sha256': {path: hashlib.sha256((ROOT / path).read_bytes()).hexdigest()
                          for path in SOURCES},
    })
    print(f"{'PASS' if passed else 'FAIL'} {name} ({out / (name + '.log')})",
          flush=True)

(out / 'results.json').write_text(json.dumps(results, indent=2), encoding='utf-8')
print(f'Evidence: {out}', flush=True)
sys.exit(0 if all(item['pass'] for item in results) else 1)

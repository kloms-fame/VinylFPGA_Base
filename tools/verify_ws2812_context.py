"""Cycle equivalence to frozen 6ffce23 WS effects, with deterministic input stress."""
from pathlib import Path
import argparse
import datetime
import json
import subprocess

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--mutate', action='store_true', help='Prove pin checker rejects one flipped sample')
parser.add_argument('--quick', action='store_true')
args = parser.parse_args()
out = ROOT / 'sim' / 'ws2812_context' / datetime.datetime.now().strftime('%Y%m%d_%H%M%S_%f')
out.mkdir(parents=True)
cases = [(1, 0), (3, 0), (8, 0), (16, 0), (8, 1)]
if args.quick or args.mutate:
    cases = [(8, 0)]
results = {}
jobs = [('tb_ws2812_context_equiv', pixels, real) for pixels, real in cases]
if not args.mutate:
    jobs += [('tb_ws2812_driver_equiv', pixels, real) for pixels, real in cases]
for top, pixels, real in jobs:
    name = f'{top}_pixels{pixels}_real{real}'
    vvp = out / (name + '.vvp')
    command = ['D:/iverilog/bin/iverilog.exe', '-g2012', '-s', top,
               f'-P{top}.PIXELS={pixels}', f'-P{top}.REAL_TIMING={real}',
               '-o', str(vvp), f'sim/{top}.v',
               'src/io/ws2812_effects.v', 'src/io/ws2812_driver.v',
               'sim/legacy/ws2812_effects_o4.v', 'sim/legacy/ws2812_driver_o4.v']
    compile_run = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=60)
    log = compile_run.stdout + compile_run.stderr
    success = False
    if compile_run.returncode == 0:
        sim_run = subprocess.run(['D:/iverilog/bin/vvp.exe', str(vvp)] + (['+MUTATE'] if args.mutate else []),
                                 cwd=ROOT, capture_output=True, text=True, timeout=180)
        log += sim_run.stdout + sim_run.stderr
        success = sim_run.returncode == 0 and 'PASS WS_' in log and 'FAIL' not in log
    (out / (name + '.log')).write_text(log, encoding='utf-8')
    results[name] = success
    print(log.strip(), flush=True)
(out / 'results.json').write_text(json.dumps(results, indent=2), encoding='utf-8')
print(f'Evidence: {out}', flush=True)
raise SystemExit(0 if all(results.values()) else 1)

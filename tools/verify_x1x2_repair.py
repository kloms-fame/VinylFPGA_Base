"""Directed repair regression; preserve each run in a fresh evidence directory."""
from pathlib import Path
import argparse, datetime, json, subprocess
R = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser()
p.add_argument('tests', nargs='*')
p.add_argument('--label', default=datetime.datetime.now().strftime('%Y%m%d_%H%M%S'))
a = p.parse_args()
out = R/'sim'/'x1x2_repair'/a.label
out.mkdir(parents=True, exist_ok=False)
tests = a.tests or ['tb_x1x2_input_repair', 'tb_x1x2_timebase', 'tb_x1x2_mv_hold', 'tb_x1x2_display', 'tb_x1x2_lights']
results = {}
for name in tests:
    cmd = ['D:/iverilog/bin/iverilog.exe', '-g2005', '-I.', '-Isrc', '-Isrc/include', '-Isrc/SD']
    for d in [R/'src', *[d for d in (R/'src').iterdir() if d.is_dir() and d.name != 'IP']]:
        cmd += ['-y', str(d)]
    cmd += ['-s', name, '-o', str(out/(name+'.vvp')), str(R/'sim'/(name+'.v'))]
    c = subprocess.run(cmd, cwd=R, capture_output=True, text=True, errors='replace', timeout=90)
    log = c.stdout+c.stderr
    ok = False
    if c.returncode == 0:
        r = subprocess.run(['D:/iverilog/bin/vvp.exe', str(out/(name+'.vvp'))], cwd=R, capture_output=True, text=True, errors='replace', timeout=180)
        log += r.stdout+r.stderr
        ok = r.returncode == 0 and 'PASS' in r.stdout and 'FAIL' not in log
    (out/(name+'.log')).write_text(log, encoding='utf-8')
    results[name] = ok
    print(name, 'PASS' if ok else 'FAIL', flush=True)
    if not ok: print(log[-4000:], flush=True)
(out/'results.json').write_text(json.dumps(results, indent=2))
raise SystemExit(0 if all(results.values()) else 1)

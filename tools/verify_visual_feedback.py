"""Focused display/WS2812 regression. Does not invoke TD, bitgen or JTAG."""
from pathlib import Path
import datetime
import json
import subprocess

ROOT = Path(__file__).resolve().parents[1]
out = ROOT/'sim/visual_feedback'/datetime.datetime.now().strftime('%Y%m%d_%H%M%S_%f')
out.mkdir(parents=True)
cases = [
    ('tb_x1x2_display', False, False),
    ('tb_x1x2_lights', False, False),
    ('tb_x1x2_lights', False, True),
    ('tb_ws2812_progress', False, False),
    ('tb_visual_feedback_top', True, False),
    ('tb_opt_metadata', True, False),
]
results = {}
for top, use_top, real in cases:
    label = top + ('_real50MHz' if real else '')
    output = out/(label+'.vvp')
    cmd = ['D:/iverilog/bin/iverilog.exe', '-g2005', '-I.', '-Isrc', '-Isrc/include', '-Isrc/SD']
    for folder in [ROOT/'src', ROOT/'sim', *[d for d in (ROOT/'src').iterdir() if d.is_dir() and d.name != 'IP']]:
        cmd += ['-y', str(folder)]
    if real:
        cmd += ['-P'+top+'.REAL_TIMING=1']
    cmd += ['-s', top, '-o', str(output), str(ROOT/'sim'/(top+'.v'))]
    if use_top:
        cmd += ['src/top_tf_hdmi_audio.v', 'sim/integration/vendor_control_stubs.v']
    compile_run = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, errors='replace', timeout=90)
    log = compile_run.stdout + compile_run.stderr
    passed = False
    if compile_run.returncode == 0:
        sim_run = subprocess.run(['D:/iverilog/bin/vvp.exe', str(output)], cwd=ROOT,
                                 capture_output=True, text=True, errors='replace', timeout=180)
        log += sim_run.stdout + sim_run.stderr
        passed = sim_run.returncode == 0 and 'PASS' in log and 'FAIL' not in log
    (out/(label+'.log')).write_text(log, encoding='utf-8')
    results[label] = passed
    print(label, 'PASS' if passed else 'FAIL', flush=True)
    if not passed:
        print(log[-4000:], flush=True)
(out/'results.json').write_text(json.dumps(results, indent=2)+'\n', encoding='utf-8')
print('Evidence:', out, flush=True)
raise SystemExit(0 if all(results.values()) else 1)

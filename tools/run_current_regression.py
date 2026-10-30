"""Run the curated current-function suites with logs and explicit failure status."""
import argparse
import datetime
import json
from pathlib import Path
import shutil
import subprocess
import sys
from verify_submission import ROOT, verify


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--output', type=Path)
    p.add_argument('--quick', action='store_true', help='Tool tests and 10 closure RTL cases')
    args = p.parse_args()
    verify(ROOT)
    if not shutil.which('iverilog') or not shutil.which('vvp'):
        p.error('Icarus Verilog (iverilog and vvp) must be available on PATH')
    out = (args.output or ROOT/'.codex_tmp'/('regression_'+datetime.datetime.now().strftime('%Y%m%d_%H%M%S'))).resolve()
    out.mkdir(parents=True, exist_ok=False)
    suites = [('tool_tests', ['-m', 'unittest', 'discover', '-s', 'tools', '-p', 'test_*.py']),
              ('closure', ['tools/verify_finish_rtl.py', '--output', str(out/'closure')])]
    if not args.quick:
        suites += [('audio', ['tools/run_audio_cache_regression.py', '--out', str(out/'audio')]),
                   ('sd_owner', ['tools/verify_mv_owner.py', '--out', str(out/'sd_owner')]),
                   ('seek', ['tools/verify_seek_integration.py']),
                   ('lyrics', ['tools/verify_lyric_focus.py', '--output', str(out/'lyrics')]),
                   ('sound_flash', ['tools/verify_system_sound.py', '--output', str(out/'sound_flash')]),
                   ('brightness', ['tools/verify_brightness_contrast_steps.py'])]
    results = []
    for name, command in suites:
        try:
            completed = subprocess.run([sys.executable, '-X', 'utf8', *command], cwd=ROOT,
                                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=600)
            data, code = completed.stdout, completed.returncode
        except subprocess.TimeoutExpired as error:
            data, code = (error.stdout or b'')+b'\nSUITE_TIMEOUT\n', 124
        (out/(name+'.log')).write_bytes(data)
        results.append({'suite': name, 'passed': code == 0, 'exit_code': code})
        print(name, 'PASS' if code == 0 else 'FAIL', flush=True)
    (out/'results.json').write_text(json.dumps(results, indent=2), encoding='utf-8')
    return 0 if all(item['passed'] for item in results) else 1


if __name__ == '__main__':
    raise SystemExit(main())

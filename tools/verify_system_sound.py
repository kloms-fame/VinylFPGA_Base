"""Directed system-sound regression; logs and hashes identify the tested inputs."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import subprocess
from verify_finish_rtl import ROOT, top_compile_options


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--top-only', action='store_true')
    args = parser.parse_args()
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    cases = [('top_alarm', 'tb_system_sound_top', ['sim/tb_system_sound_top.v',
              'src/top_tf_hdmi_audio.v', 'sim/integration/vendor_control_stubs.v'], ['+mode=1']),
             ('top_save', 'tb_system_sound_top', ['sim/tb_system_sound_top.v',
              'src/top_tf_hdmi_audio.v', 'sim/integration/vendor_control_stubs.v'], ['+mode=2']),
             ('top_save_busy', 'tb_system_sound_top', ['sim/tb_system_sound_top.v',
              'src/top_tf_hdmi_audio.v', 'sim/integration/vendor_control_stubs.v'], ['+mode=3'])]
    if not args.top_only:
        cases += [('scheduler', 'tb_system_sound_scheduler', ['sim/tb_system_sound_scheduler.v'], []),
                  ('flash_save', 'tb_system_sound_flash', ['sim/tb_system_sound_flash.v', 'sim/tb_stage4_nvm.v'], []),
                  ('legacy_events', 'tb_stage4_sound_events', ['sim/tb_stage4_sound_events.v'], [])]
    hashes = {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
              for folder in ('src', 'constraints', 'sim')
              for p in (ROOT / folder).rglob('*') if p.is_file() and p.suffix in ('.v', '.vh', '.adc', '.sdc')}
    results = []
    for name, top, files, flags in cases:
        image = out / (name + '.vvp')
        command = ['iverilog', '-g2005', *top_compile_options(), '-Isrc/include', '-s', top,
                   '-o', str(image), *files]
        if name == 'top_save':
            command.insert(1, '-Ptb_system_sound_top.IR_CYCLES=1750000')
        if name == 'flash_save':
            command.insert(1, '-Ptb_system_sound_flash.FULL_TONE_RUN=0')
        build = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=90)
        log = build.stdout + build.stderr
        code = build.returncode
        if code == 0:
            run = subprocess.run(['vvp', str(image), *flags], cwd=out, capture_output=True, text=True, timeout=180)
            log += run.stdout + run.stderr
            code = run.returncode
        passed = code == 0 and re.search(r'\b(?:PASS|TEST_PASS)\b', log) is not None and not re.search(r'\b(?:FAIL|FATAL|ERROR)\b', log)
        (out / (name + '.log')).write_text(log, encoding='utf-8')
        results.append({'test': name, 'passed': bool(passed), 'exit': code, 'compile': command})
        print(name, 'PASS' if passed else 'FAIL', flush=True)
        if not passed:
            print(log[-2400:], flush=True)
    (out / 'results.json').write_text(json.dumps({'inputs_sha256': hashes, 'results': results}, indent=2), encoding='utf-8')
    return 0 if all(r['passed'] for r in results) else 1


if __name__ == '__main__':
    raise SystemExit(main())

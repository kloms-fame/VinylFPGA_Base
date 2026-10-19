"""Focused closure acceptance cases with per-input hashes and fresh logs."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
CASES = {
    'tb_closure_sector_fairness': ['src/video/background_sector_mux.v'],
    'tb_closure_mv_service': ['src/video/background_sector_mux.v', 'src/video/mv_stream_player.v'],
    'tb_closure_triple_buffer': ['src/video/mv_frame_scheduler.v'],
    'tb_closure_no_blackflash': ['src/display/video_transition_apply.v'],
    'tb_video_fade_transition': ['src/display/video_fade_transition.v', 'src/display/video_transition_apply.v'],
    'tb_mv_frame_scheduler': ['src/video/mv_frame_scheduler.v'],
    'tb_mv_audio_shared': ['src/video/mv_stream_player.v', 'src/video/mv_sector_mux.v', 'src/audio/wav_stream_player.v'],
    'tb_mv_stream_player': ['src/video/mv_stream_player.v'],
    'tb_closure_top_handoff': ['src/top_tf_hdmi_audio.v', 'sim/integration/vendor_control_stubs.v'],
}

def top_compile_options():
    options = ['-DVINYL_AUDIO_CACHE_SIM', '-I.', '-Isrc', '-Isrc/SD']
    for directory in [ROOT / 'src', ROOT / 'sim',
                      *(p for p in (ROOT / 'src').iterdir() if p.is_dir() and p.name != 'IP')]:
        options += ['-y', str(directory)]
    return options


def input_hashes(name, files):
    inputs = set(files)
    if name == 'tb_closure_top_handoff':
        inputs.update(p.relative_to(ROOT).as_posix() for p in (ROOT / 'src').rglob('*') if p.is_file())
    return {s: hashlib.sha256((ROOT / s).read_bytes()).hexdigest() for s in sorted(inputs)}

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--output', type=Path, required=True)
    args = p.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    results = []
    for name, sources in CASES.items():
        files = [*sources, 'sim/' + name + '.v']
        image = (args.output / (name + '.vvp')).resolve()
        top_case = name == 'tb_closure_top_handoff'
        options = top_compile_options() if top_case else []
        build = subprocess.run(['iverilog', '-g2005' if top_case else '-g2012', *options, '-Isrc/include', '-s', name,
                                '-o', str(image), *files], cwd=ROOT, capture_output=True, text=True)
        transcript = build.stdout + build.stderr
        code = build.returncode
        if code == 0:
            try:
                run = subprocess.run(['vvp', str(image)], cwd=ROOT, capture_output=True,
                                     text=True, timeout=60)
                transcript += run.stdout + run.stderr
                code = run.returncode
            except subprocess.TimeoutExpired:
                transcript += '\nTIMEOUT\n'
                code = 124
        passed = (code == 0 and re.search(r'\b(?:TEST_PASS|PASS)\b', transcript) is not None
                  and re.search(r'\b(?:FAIL|FATAL|ERROR)\b', transcript) is None)
        (args.output / (name + '.log')).write_text(transcript, encoding='utf-8')
        results.append({'test': name, 'passed': passed, 'exit': code,
                        'inputs_sha256': input_hashes(name, files)})
        print(name, 'PASS' if passed else 'FAIL', flush=True)
        if not passed:
            print(transcript[-2000:], flush=True)
    (args.output / 'results.json').write_text(json.dumps(results, indent=2), encoding='utf-8')
    return 0 if all(r['passed'] for r in results) else 1

if __name__ == '__main__':
    raise SystemExit(main())

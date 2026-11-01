"""Run the five microphone ADC, conditioning, gain and mixer regressions."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
CASES = {
    'tb_mic_adc_capture': [
        'src/audio/mic_adc_capture.v',
        'sim/tb_mic_adc_capture.v',
    ],
    'tb_mic_signal_condition': [
        'src/audio/mic_signal_condition.v',
        'sim/microphone/tb_mic_signal_condition.v',
    ],
    'tb_mic_pcm_mixer': [
        'src/audio/mic_pcm_mixer.v',
        'sim/microphone/tb_mic_pcm_mixer.v',
    ],
    'tb_mic_gain_follow': [
        'src/audio/mic_gain_follow.v',
        'sim/microphone/tb_mic_gain_follow.v',
    ],
    'tb_mic_pipeline': [
        'src/audio/mic_adc_capture.v',
        'src/audio/mic_signal_condition.v',
        'src/audio/mic_pcm_mixer.v',
        'sim/tb_mic_adc_capture.v',
        'sim/microphone/tb_mic_pipeline.v',
    ],
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)

    results = []
    for name, sources in CASES.items():
        image = (args.output / (name + '.vvp')).resolve()
        build = subprocess.run(
            ['iverilog', '-g2012', '-Isrc/audio', '-Isrc/include', '-s', name,
             '-o', str(image), *sources],
            cwd=ROOT, capture_output=True, text=True,
        )
        transcript = build.stdout + build.stderr
        code = build.returncode
        if code == 0:
            run = subprocess.run(
                ['vvp', str(image)], cwd=ROOT, capture_output=True,
                text=True, timeout=120,
            )
            transcript += run.stdout + run.stderr
            code = run.returncode
        passed = (
            code == 0
            and re.search(r'\bPASS\b', transcript) is not None
            and re.search(r'\b(?:FAIL|FATAL|ERROR)\b', transcript) is None
        )
        (args.output / (name + '.log')).write_text(transcript, encoding='utf-8')
        results.append({
            'test': name,
            'passed': passed,
            'exit': code,
            'inputs_sha256': {
                source: hashlib.sha256((ROOT / source).read_bytes()).hexdigest()
                for source in sources
            },
        })
        print(name, 'PASS' if passed else 'FAIL', flush=True)
        if not passed:
            print(transcript[-2000:], flush=True)

    (args.output / 'results.json').write_text(
        json.dumps(results, indent=2), encoding='utf-8'
    )
    return 0 if all(item['passed'] for item in results) else 1


if __name__ == '__main__':
    raise SystemExit(main())

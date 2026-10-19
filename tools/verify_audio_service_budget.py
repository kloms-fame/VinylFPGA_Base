"""ModelSim service-budget stress: real cache/DMA, synthetic SD and SDRAM."""
import argparse
import hashlib
import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ['src/audio/audio_prefetch_stage.v', 'src/audio/audio_sdram_dma.v',
           'src/audio/audio_prefetch_sdram.v', 'src/video/background_sector_mux.v',
           'sim/audio_cache/tb_audio_mv_slow_window.v']

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--policy', choices=['stable', 'regressed'], default='stable')
    p.add_argument('--vsim', type=Path, default=Path('D:/modeltech64_10.6e/win64/vsim.exe'))
    args = p.parse_args()
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    compile_command = 'vlog -sv +define+VINYL_AUDIO_CACHE_SIM ' + ' '.join(
        '{' + (ROOT / path).as_posix() + '}' for path in SOURCES)
    (out / 'compile.f').write_text('\n'.join((ROOT / s).as_posix() for s in SOURCES) + '\n', encoding='utf-8')
    (out / 'wave.do').write_text('log /tb_audio_mv_slow_window/slow_started /tb_audio_mv_slow_window/completed /tb_audio_mv_slow_window/cache/occupied\n', encoding='utf-8')
    script = ['onerror {quit -force -code 1}', 'vlib work', 'vmap work work', compile_command,
              'vsim -voptargs=+acc -wlf waves.wlf -gREGRESSED_POLICY=' + ('1' if args.policy == 'regressed' else '0') +
              ' work.tb_audio_mv_slow_window', 'onfinish stop',
              'do wave.do',
              'run -all', 'quit -force -code 0']
    (out / 'run.do').write_text('\n'.join(script) + '\n', encoding='utf-8')
    result = subprocess.run([str(args.vsim), '-c', '-do', 'run.do'], cwd=out,
                            capture_output=True, text=True, errors='replace', timeout=600)
    log = result.stdout + result.stderr
    (out / 'console.log').write_text(log, encoding='utf-8')
    exported = subprocess.run([str(args.vsim.with_name('wlf2vcd.exe')), '-o', str(out / 'waveform.vcd'),
                               str(out / 'waves.wlf')], capture_output=True, text=True, errors='replace', timeout=60)
    (out / 'wave_export.log').write_text(exported.stdout + exported.stderr, encoding='utf-8')
    waves_ok = exported.returncode == 0 and all(
        (out / name).is_file() and (out / name).stat().st_size > 0
        for name in ('waves.wlf', 'waveform.vcd'))
    passed = (result.returncode == 0 and 'TEST_PASS audio_mv_slow_window' in log
              and waves_ok and not re.search(r'\b(?:FATAL|Fatal|FAIL)\b|\*\* Error:', log))
    summary = {'policy': args.policy, 'passed': passed, 'exit': result.returncode,
               'wlf_retained': (out / 'waves.wlf').is_file(), 'vcd_exported': waves_ok,
               'underrun_observed': 'BUDGET_UNDERRUN' in log,
               'measurements': [line.strip() for line in log.splitlines()
                                if any(marker in line for marker in ('BEFORE_SLOW', 'SLOW_COMPLETE', 'BUDGET_UNDERRUN', 'TEST_PASS'))],
               'inputs_sha256': {s: hashlib.sha256((ROOT / s).read_bytes()).hexdigest() for s in SOURCES}}
    (out / 'results.json').write_text(json.dumps(summary, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(summary, indent=2), flush=True)
    if not passed:
        print(log[-2500:])
    return 0 if passed else 1

if __name__ == '__main__':
    raise SystemExit(main())

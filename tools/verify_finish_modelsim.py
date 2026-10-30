"""Independently run focused closure RTL checks in ModelSim and retain waves."""
import argparse
import json
import os
import re
import subprocess
from pathlib import Path

from verify_finish_rtl import CASES, ROOT, TOP_CASES, input_hashes

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--vsim', type=Path, default=Path('D:/modeltech64_10.6e/win64/vsim.exe'))
    p.add_argument('--td-root', type=Path, default=Path(os.environ.get(
        'TD_ROOT', 'D:/Anlogic/TD_6.2.1_Engineer_6.2.168.116')))
    args = p.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    results = []
    for name in [*list(CASES)[:4], *[n for n in CASES if n in TOP_CASES]]:
        folder = output / name
        folder.mkdir()
        sources = [*CASES[name], 'sim/' + name + '.v']
        (folder / 'compile.f').write_text('\n'.join((ROOT / f).as_posix() for f in sources) + '\n', encoding='utf-8')
        (folder / 'wave.do').write_text('log -r /*\nadd wave -r /*\n', encoding='utf-8')
        options = ['-sv']
        primitive_commands = []
        simulation_tops = 'work.' + name
        if name in TOP_CASES:
            options = ['+define+VINYL_AUDIO_CACHE_SIM+VINYL_MV_BURST_BEHAV', '+libext+.v']
            options += ['+incdir+' + (ROOT / p).as_posix() for p in ('src', 'src/include', 'src/SD')]
            directories = [ROOT / 'src', ROOT / 'sim',
                           *(p for p in (ROOT / 'src').iterdir() if p.is_dir() and p.name != 'IP')]
            options += ['-y {' + p.as_posix() + '}' for p in directories]
            primitives = [args.td_root/'sim_release/eg4'/f for f in
                          ('eg_phy_bram32k.v', 'eg_phy_glbl.v')]
            for primitive in primitives:
                if not primitive.is_file():
                    raise FileNotFoundError(primitive)
            primitive_commands = ['vlog -sv ' + ' '.join(
                '{' + p.resolve().as_posix() + '}' for p in primitives)]
            simulation_tops += ' work.glbl'
        script = ['onerror {quit -force -code 1}', 'vlib work', 'vmap work work',
                  *primitive_commands,
                  'vlog ' + ' '.join(options + ['{' + (ROOT / f).as_posix() + '}' for f in sources]),
                  'vsim -voptargs=+acc -wlf waves.wlf ' + simulation_tops, 'onfinish stop',
                  'do wave.do', 'vcd file waveform.vcd', 'vcd add -r /*',
                  'run -all', 'vcd flush', 'quit -force -code 0']
        (folder / 'run.do').write_text('\n'.join(script) + '\n', encoding='utf-8')
        run = subprocess.run([str(args.vsim), '-c', '-do', 'run.do'], cwd=folder,
                             capture_output=True, text=True, errors='replace', timeout=90)
        log = run.stdout + run.stderr
        (folder / 'console.log').write_text(log, encoding='utf-8')
        waves = all((folder / f).is_file() and (folder / f).stat().st_size > 0
                    for f in ('waves.wlf', 'waveform.vcd'))
        passed = (run.returncode == 0 and waves and re.search(r'\b(?:TEST_PASS|PASS)\b', log) is not None
                  and not re.search(r'\b(?:FATAL|Fatal|FAIL)\b|\*\* Error:', log))
        results.append({'test': name, 'passed': bool(passed), 'exit': run.returncode,
                        'wlf_retained': (folder / 'waves.wlf').exists(),
                        'vcd_exported': (folder / 'waveform.vcd').exists(),
                        'inputs_sha256': input_hashes(name, sources)})
        print(name, 'PASS' if passed else 'FAIL', flush=True)
        if not passed:
            print(log[-3000:], flush=True)
    (output / 'results.json').write_text(json.dumps(results, indent=2) + '\n', encoding='utf-8')
    return 0 if all(r['passed'] for r in results) else 1

if __name__ == '__main__':
    raise SystemExit(main())

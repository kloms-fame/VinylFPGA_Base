"""Real SD controller integration with a byte-level SPI card model."""
from pathlib import Path
import argparse
import hashlib
import json
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
BENCH = ROOT / 'sim/mv_owner_20261028'
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--out', required=True, type=Path)
args = parser.parse_args()
out = args.out.resolve()
out.mkdir(parents=True, exist_ok=False)
names = ['sd_card_top', 'sd_card_sec_read_write', 'sd_card_cmd',
         'sd_cmd18_reader', 'sd_sector_adapter']
sources = [ROOT/'src/SD'/f'{n}.v' for n in names]
sources += [BENCH/'fake_spi_card.v', BENCH/'tb_sd_owner.v']
command = ['iverilog', '-g2012', '-Isrc', '-s', 'tb_sd_owner', '-o', str(out/'owner.vvp')]
command += ['-DFIXE']
compile_run = subprocess.run(command + list(map(str, sources)), capture_output=True, text=True, cwd=ROOT)
(out/'compile.log').write_text(compile_run.stdout+compile_run.stderr, encoding='utf-8')
if compile_run.returncode:
    print(compile_run.stderr)
    sys.exit(1)
results = []
for case in range(8):
    run = subprocess.run(['vvp', str(out/'owner.vvp'), f'+CASE={case}'],
                         capture_output=True, text=True, cwd=out, timeout=60)
    transcript = run.stdout+run.stderr
    (out/f'case{case}.log').write_text(transcript, encoding='utf-8')
    passed = run.returncode == 0 and 'PASS' in transcript
    results.append({'case': case, 'pass': passed, 'exit': run.returncode})
    print(f"{'PASS' if passed else 'FAIL'} case={case}: {transcript.strip().splitlines()[-2:]}", flush=True)
recovery_sources = [ROOT/'src/SD'/f'{n}.v' for n in
                    ['sd_card_top','sd_card_sec_read_write','sd_card_cmd',
                     'sd_cmd18_reader','media_supervisor']]
recovery_sources += [BENCH/'fake_spi_card.v', BENCH/'tb_mv_recovery.v']
recovery_compile = subprocess.run(['iverilog','-g2012','-Isrc','-s','tb_mv_recovery',
    '-o',str(out/'recovery.vvp'),*map(str,recovery_sources)],cwd=ROOT,capture_output=True,text=True)
(out/'recovery_compile.log').write_text(recovery_compile.stdout+recovery_compile.stderr,encoding='utf-8')
for case in range(3):
    if recovery_compile.returncode:
        run = recovery_compile
    else:
        run = subprocess.run(['vvp',str(out/'recovery.vvp'),f'+CASE={case}'],
                             cwd=out,capture_output=True,text=True,timeout=60)
    transcript = run.stdout+run.stderr
    passed = run.returncode == 0 and 'PASS mv_recovery' in transcript
    (out/f'recovery{case}.log').write_text(transcript,encoding='utf-8')
    results.append({'case':f'recovery{case}','pass':passed,'exit':run.returncode})
    print(f"{'PASS' if passed else 'FAIL'} recovery={case}: {transcript.strip().splitlines()[:1]}",flush=True)
sources += recovery_sources
(out/'results.json').write_text(json.dumps({'legacy': False, 'results': results,
    'inputs_sha256': {str(f.relative_to(ROOT)): hashlib.sha256(f.read_bytes()).hexdigest() for f in sources}}, indent=2), encoding='utf-8')
sys.exit(0 if all(r['pass'] for r in results) else 1)

"""Checkpointed TD phases. Refuse to replace logs, scripts, or databases."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import subprocess
import time

TD = Path('D:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/bin/td_commands_prompt.exe')
p = argparse.ArgumentParser()
p.add_argument('snapshot', type=Path)
p.add_argument('phase', choices=['gate', 'place', 'route', 'bitgen', 'bitgen_release'])
p.add_argument('--seed',type=int,default=6)
a = p.parse_args()
dest = a.snapshot.resolve(strict=True)
assert (dest / 'VinylFPGA.al').is_file()
phase = a.phase
assert 1 <= a.seed <= 100
seed = a.seed
if phase in ['route','bitgen','bitgen_release'] and (dest/'place.process.json').exists():
    seed = json.loads((dest/'place.process.json').read_text())['seed']
bit_name = 'VFPGA_AUDIO_PREFETCH_CLOSED_S'+str(seed)+('_RELEASE' if phase=='bitgen_release' else '')+'.bit'
marker = 'AUDIO_' + phase.upper() + '_COMPLETE'
scripts = {
    'gate': '''open_project ./VinylFPGA.al -single_run
elaborate -top top
read_adc ./constraints/pin.adc
read_sdc ./constraints/timing.sdc
optimize_rtl
report_area -file ./rtl.area
export_db ./rtl.db
set_param gate map_mode area_prior
optimize_gate
legalize_phy_inst
read_sdc ./constraints/timing.sdc
update_timing
report_area -file ./gate.area
report_timing_summary -ep_num 50 -file ./gate.timing
flow_status -file ./gate.status
export_db ./gate.db''',
    'place': '''import_db ./gate.db
set_param place seed 6
place
update_timing -mode manhattan
report_area -file ./place.area
report_timing_summary -ep_num 30 -file ./place.timing
flow_status -file ./place.status
export_db ./place.db''',
    'route': '''import_db ./place.db
route
export_db ./pre_hold.db
fix_hold
update_timing -mode final
report_area -io_info -file ./final.area
report_qor -step route -file ./final.qor
report_timing_summary -ep_num 500 -file ./final.timing
report_timing_exception -file ./final.exceptions
check_timing -verbose -file ./final.constraints
flow_status -file ./route.status
export_db ./routed.db''',
    'bitgen': '''open_project ./VinylFPGA.al -single_run
import_db ./routed.db
commit_param -step bitgen
bitgen -bit ./VFPGA_AUDIO_PREFETCH_CLOSED_S6.bit
setup_debugger
export_bitgen_param -file ./VFPGA_AUDIO_PREFETCH_CLOSED_S6.bitgen_param.f''',
}
scripts['bitgen_release']=scripts['bitgen']
dbs = {'gate': ['rtl.db', 'gate.db'], 'place': ['place.db'],
       'route': ['pre_hold.db', 'routed.db'],
       'bitgen': [bit_name]}
dbs['bitgen_release']=[bit_name]
script, log = dest / (phase + '.tcl'), dest / (phase + '.log')
for item in [script, log, *(dest / n for n in dbs[phase])]:
    if item.exists():
        raise SystemExit('Refusing to replace evidence: ' + str(item))
inputs = json.loads((dest / 'inputs.sha256.json').read_text())
for name, digest in inputs.items():
    assert hashlib.sha256((dest / name).read_bytes()).hexdigest() == digest, name
if phase in ['bitgen','bitgen_release']:
    signoff = json.loads((dest / 'sta_release.result.json').read_text())
    assert signoff['internal_sta_pass'] is True
    assert signoff['clock_and_constraint_checks_pass'] is True
    assert hashlib.sha256((dest / 'routed.db').read_bytes()).hexdigest() == signoff['database_sha256']
    qor = (dest / 'final.qor').read_text(encoding='gbk')
    for name in ['Setup WNS', 'Setup TNS', 'Hold WNS', 'Hold TNS', 'Num of violated S-EP', 'Num of violated H-EP']:
        match = re.search(re.escape(name) + r'\s*\|\s*(-?\d+)', qor)
        assert match and (int(match[1]) >= 0 if name.endswith('WNS') else int(match[1]) == 0), name
phase_commands = scripts[phase].replace('set_param place seed 6','set_param place seed '+str(seed))
if phase in ['bitgen','bitgen_release']: phase_commands=phase_commands.replace('VFPGA_AUDIO_PREFETCH_CLOSED_S6.bit',bit_name)
script.write_text('import_device eagle_s20.db -package EG4S20BG256\n' +
                  phase_commands + '\nset phase_marker [open .'+phase+'.end.f w]\n'+
                  'puts $phase_marker '+marker+'\nclose $phase_marker\nputs ' + marker + '\nexit\n', encoding='utf-8')
start = time.time()
with log.open('xb') as output:
    proc = subprocess.Popen([str(TD), script.name], cwd=dest,
                            stdout=output, stderr=subprocess.STDOUT)
    (dest / (phase + '.process.json')).write_text(json.dumps({
        'pid': proc.pid, 'start_epoch': start, 'command': [str(TD), script.name],
        'cwd': str(dest), 'seed': seed, 'inputs_manifest_sha256':
        hashlib.sha256((dest / 'inputs.sha256.json').read_bytes()).hexdigest(),
        'script_sha256': hashlib.sha256(script.read_bytes()).hexdigest()}, indent=2))
    status = proc.wait(timeout=1800)
transcript = log.read_text(encoding='gbk', errors='replace')
bad = re.search(r"couldn't read file|Assert failed|\b(?:ERROR|FATAL)\b", transcript, re.I)
fresh = all((dest / n).is_file() and (dest / n).stat().st_mtime >= start - 2
            for n in dbs[phase])
passed = status == 0 and marker in transcript and not bad and fresh
(dest / (phase + '.result.json')).write_text(json.dumps({
    'exit': status, 'marker': marker in transcript, 'error': bad.group() if bad else None,
    'fresh_artifacts': fresh, 'phase_completed': bool(passed),
    'duration_seconds': time.time() - start,
    'artifacts': {n: hashlib.sha256((dest / n).read_bytes()).hexdigest()
                  for n in dbs[phase] if (dest / n).exists()}}, indent=2))
print(('COMPLETE ' if passed else 'FAILED ') + str(log), flush=True)
if not passed:
    print(transcript[-5000:])
raise SystemExit(0 if passed else 1)

"""Native TD snapshot/seed runner; write literal EDA paths and preserve checkpoints."""
from pathlib import Path
import argparse
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser()
p.add_argument('round')
p.add_argument('--seed', type=int, default=1)
p.add_argument('--gate', type=Path)
p.add_argument('--map-mode')
p.add_argument('--td', type=Path, default=Path('D:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/bin/td_commands_prompt.exe'))
a = p.parse_args()
dest = (ROOT / 'prj/resource_opt_verified_20261005' / a.round).resolve(strict=True)
assert 1 <= a.seed <= 100
assert not (dest / 'native_build.log').exists(), 'Use a new snapshot for each build'

def tcl_path(path):
    value = Path(path).resolve().as_posix()
    assert not any(c in value for c in '{}\n\r')
    return '{' + value + '}'

def out(name):
    return tcl_path(dest / name)

lines = ['import_device eagle_s20.db -package EG4S20BG256']
if a.gate:
    lines += ['import_db ' + tcl_path(a.gate.resolve(strict=True))]
else:
    lines += ['open_project ' + out('VinylFPGA.al') + ' -single_run', 'elaborate -top top',
              'read_adc ' + out('constraints/pin.adc'), 'read_sdc ' + out('constraints/timing.sdc'),
              'optimize_rtl', 'report_area -file ' + out('rtl.area'), 'export_db ' + out('rtl.db')]
    if a.map_mode:
        assert a.map_mode in ('area_prior', 'balance_explore', 'auto')
        lines += ['set_param gate map_mode ' + a.map_mode]
    lines += ['optimize_gate', 'legalize_phy_inst', 'read_sdc ' + out('constraints/timing.sdc'),
              'update_timing', 'report_area -file ' + out('gate.area'),
              'report_timing_summary -file ' + out('gate.timing'),
              'flow_status -file ' + out('gate.status'), 'export_db ' + out('gate.db')]
lines += ['set_param place seed ' + str(a.seed),
          'place', 'export_db ' + out('place.db'), 'route', 'update_timing -mode final',
          'report_area -io_info -file ' + out('final.area'),
          'report_qor -step route -file ' + out('final.qor'),
          'report_timing_summary -file ' + out('final.timing'),
          'report_timing_exception -file ' + out('final.exceptions'),
          'check_timing -verbose -file ' + out('final.constraints'),
          'flow_status -file ' + out('route.status'), 'export_db ' + out('routed.db'),
          'puts VERIFIED_ROUND_COMPLETE', 'exit']
script = dest / 'native_build.tcl'
script.write_text('\n'.join(lines) + '\n', encoding='utf-8')
with (dest / 'native_build.log').open('wb') as log:
    result = subprocess.run([a.td.as_posix(), script.as_posix()], cwd=dest, stdout=log, stderr=subprocess.STDOUT, timeout=900)
log = (dest / 'native_build.log').read_text(encoding='gbk', errors='replace')
if result.returncode or 'VERIFIED_ROUND_COMPLETE' not in log:
    print(log[-3000:])
    sys.exit(1)
qor = (dest / 'final.qor').read_text(encoding='gbk')
print(qor)
print('Reports and checkpoints saved in ' + str(dest))
for field in ('Setup WNS', 'Hold WNS'):
    value = re.search(re.escape(field) + r'\s*\|\s*(-?\d+)', qor)
    if value is None or int(value[1]) < 0:
        sys.exit(2)

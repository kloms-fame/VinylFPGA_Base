"""Generate a bitstream from a passing saved route, optionally load JTAG SRAM."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser()
p.add_argument('round')
p.add_argument('--program-sram', action='store_true')
p.add_argument('--td', type=Path, default=Path('D:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/bin/td_commands_prompt.exe'))
a = p.parse_args()
dest = (ROOT/'prj/resource_opt_verified_20261005'/a.round).resolve(strict=True)
qor = (dest/'final.qor').read_text(encoding='gbk')
for field in ('Setup WNS','Hold WNS','Setup TNS','Hold TNS'):
    m = re.search(re.escape(field)+r'\s*\|\s*(-?\d+)',qor)
    assert m and int(m[1])>=0, 'Routed timing must pass'
checks = (dest/'final.constraints').read_text(encoding='gbk')
# Positive slack is insufficient when a combinational feedback path was cut
# by static timing. Require these structural checks before generating a bit.
for label in ('no clock', 'invalid constraint', 'combinational loops'):
    m = re.search(r'checking '+re.escape(label)+r'\((\d+)\)', checks)
    assert m and int(m[1]) == 0, 'Unresolved timing structure: '+label
hashes=json.loads((dest/'inputs.sha256.json').read_text())
for rel, expected in hashes.items():
    assert hashlib.sha256((ROOT/rel).read_bytes()).hexdigest()==expected, 'Current input differs: '+rel
bit=dest/'VinylFPGA_optimized.bit'
def quote(path):
    value=Path(path).resolve().as_posix()
    assert not any(c in value for c in '{}\n\r')
    return '{'+value+'}'
def execute(name,lines,marker):
    script=dest/(name+'.tcl')
    script.write_text('\n'.join(lines)+'\n',encoding='utf-8')
    with (dest/(name+'.log')).open('wb') as log:
        result=subprocess.run([a.td.as_posix(),script.as_posix()],cwd=dest,stdout=log,stderr=subprocess.STDOUT,timeout=180)
    output=(dest/(name+'.log')).read_text(encoding='gbk',errors='replace')
    print(output[-2500:])
    assert result.returncode==0 and marker in output and not re.search(r'\b(?:ERROR|FATAL)\b',output), 'Inspect '+str(dest/(name+'.log'))
assert not bit.exists(), 'Do not overwrite an existing release'
execute('release_bitgen',[
    'import_device eagle_s20.db -package EG4S20BG256',
    'import_db '+quote(dest/'routed.db'),
    'bitgen -bit '+quote(bit),
    'setup_debugger',
    'export_bitgen_param -file '+quote(dest/'.bitgen_param.f'),
    'puts VERIFIED_BITGEN_COMPLETE','exit'], 'VERIFIED_BITGEN_COMPLETE')
assert bit.stat().st_size>0
digest=hashlib.sha256(bit.read_bytes()).hexdigest()
(dest/'bitstream.sha256').write_text(digest+'  '+bit.name+'\n',encoding='utf-8')
print('BITSTREAM_SHA256 '+digest)
if a.program_sram:
    execute('release_download',[
        'connect_cable -open -auto_start',
        'set verified_device [read_device_id -level 1]',
        'puts "VERIFIED_DEVICE $verified_device"',
        'if {![string match *EG4S20BG256* $verified_device]} {error "Unexpected JTAG target"}',
        'if {[catch {download -mode jtag -bit '+quote(bit)+'} verified_error]} {puts "VERIFIED_DOWNLOAD_FAILED $verified_error"; exit 2}',
        'puts VERIFIED_SRAM_DOWNLOAD_COMPLETE','exit'], 'VERIFIED_SRAM_DOWNLOAD_COMPLETE')

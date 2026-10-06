"""Validate a saved TD route, generate/program SRAM, and archive bridge telemetry.

This is a board smoke test, not a replacement for physical IR/DIP/HDMI testing.
Only reads the OmniProbe bridge; never sends serial commands or writes Flash.
"""
from pathlib import Path
import argparse
import hashlib
import json
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser()
p.add_argument('round')
p.add_argument('--client', type=Path, required=True)
p.add_argument('--seconds', type=int, default=45)
p.add_argument('--tag', default='board')
p.add_argument('--td', type=Path, default=Path('D:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/bin/td_commands_prompt.exe'))
a = p.parse_args()
folder = ROOT/'prj/resource_opt_verified_20261005'/a.round
qor=(folder/'final.qor').read_text(encoding='gbk')
for name in ('Setup WNS','Hold WNS','Setup TNS','Hold TNS','Num of violated S-EP','Num of violated H-EP'):
    value=int(re.search(re.escape(name)+r'\s*\|\s*(-?\d+)',qor)[1])
    assert value>=0 if name.endswith('WNS') else value==0, name
checks=(folder/'final.constraints').read_text(encoding='gbk')
for label in ('no clock','invalid constraint','combinational loops'):
    match=re.search(r'checking '+re.escape(label)+r'\((\d+)\)',checks)
    assert match and int(match[1])==0, label
hashes=json.loads((folder/'inputs.sha256.json').read_text())
for name,digest in hashes.items():
    assert hashlib.sha256((folder/name).read_bytes()).hexdigest()==digest, name

def quote(path):
    value=Path(path).resolve().as_posix()
    assert not any(c in value for c in '{}\n\r')
    return '{'+value+'}'

def execute(name,lines,marker):
    script=folder/(name+'.tcl');logfile=folder/(name+'.log')
    assert not logfile.exists(), 'Use another tag for a new attempt'
    script.write_text('\n'.join(lines)+'\n',encoding='utf-8')
    with logfile.open('wb') as log:
        r=subprocess.run([a.td.as_posix(),script.as_posix()],cwd=folder,stdout=log,stderr=subprocess.STDOUT,timeout=180)
    log=logfile.read_text(encoding='gbk',errors='replace')
    print(log[-1500:],flush=True)
    assert r.returncode==0 and marker in log and not re.search(r'\b(?:ERROR|FATAL)\b',log), logfile

bit=folder/'VinylFPGA_optimized.bit'
if not bit.exists():
    execute(a.tag+'_bitgen', ['import_device eagle_s20.db -package EG4S20BG256',
            'import_db '+quote(folder/'routed.db'), 'bitgen -bit '+quote(bit),
            'setup_debugger','export_bitgen_param -file '+quote(folder/'.bitgen_param.f'),
            'puts VERIFIED_BITGEN_COMPLETE','exit'], 'VERIFIED_BITGEN_COMPLETE')
    assert bit.stat().st_size>0
    (folder/'bitstream.sha256').write_text(hashlib.sha256(bit.read_bytes()).hexdigest()+'  '+bit.name+'\n',encoding='utf-8')
digest=hashlib.sha256(bit.read_bytes()).hexdigest()
assert (folder/'bitstream.sha256').read_text().split()[0]==digest
telemetry=folder/(a.tag+'_telemetry.ndjson')
assert not telemetry.exists(), 'Use a new tag to preserve observations'
with telemetry.open('wb') as log:
    watch=subprocess.Popen([sys.executable,'-u',str(a.client),'watch','--port','8765','--seconds',str(a.seconds)],stdout=log,stderr=subprocess.STDOUT)
    try:
        execute(a.tag+'_download', ['connect_cable -open -auto_start',
                'set verified_device [read_device_id -level 1]', 'puts "VERIFIED_DEVICE $verified_device"',
                'if {![string match *EG4S20BG256* $verified_device]} {error "Unexpected JTAG target"}',
                'if {[catch {download -mode jtag -bit '+quote(bit)+'} verified_error]} {puts "VERIFIED_DOWNLOAD_FAILED $verified_error"; exit 2}',
                'puts VERIFIED_SRAM_DOWNLOAD_COMPLETE','exit'], 'VERIFIED_SRAM_DOWNLOAD_COMPLETE')
    finally:
        watch.wait(timeout=a.seconds+10)
lines=[]
for raw in telemetry.read_text(encoding='utf-8',errors='replace').splitlines():
    try:
        message=json.loads(raw)
    except json.JSONDecodeError:
        continue
    lines.extend(item['text'] for item in message.get('lines',[]) if item.get('direction')=='rx')
stats=[dict(re.findall(r'(UR|BL|VF|OV|ERR|VER)=([0-9A-Fa-f]+)',line)) for line in lines if line.startswith('STAT ')]
boot=any('BOOT' in line or 'VINYL' in line for line in lines)
ok=watch.returncode==0 and boot and len(stats)>=3 and all(s.get('ERR')=='00' and s.get('OV')=='0000' for s in stats[-3:])
result=dict(round=a.round,bit_sha256=digest,download=True,bridge_exit=watch.returncode,
            boot_observed=boot,received_lines=lines,stat_count=len(stats),last_stats=stats[-3:],
            smoke_pass=ok,physical_controls_tested=False)
(folder/(a.tag+'_result.json')).write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({k:v for k,v in result.items() if k!='received_lines'},indent=2),flush=True)
raise SystemExit(0 if ok else 1)

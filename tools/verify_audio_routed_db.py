"""Reopen a timing-passing routed DB and save independent STA/clock/route evidence."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import subprocess

p=argparse.ArgumentParser(description=__doc__)
p.add_argument('snapshot',type=Path)
p.add_argument('--prefix',default='signoff')
a=p.parse_args();dest=a.snapshot.resolve(strict=True)
assert re.fullmatch(r'[a-zA-Z0-9_]+',a.prefix)
prefix=a.prefix
qor=(dest/'final.qor').read_text(encoding='gbk')
fields=['Setup WNS','Setup TNS','Num of violated S-EP','Hold WNS','Hold TNS','Num of violated H-EP']
def metrics(text):
    result={}
    for name in fields:
        m=re.search(re.escape(name)+r'\s*\|\s*(-?\d+)',text)
        assert m,name
        result[name]=int(m[1])
        assert (result[name]>=0 if name.endswith('WNS') else result[name]==0), (name,result[name])
    return result
before=metrics(qor)
db=dest/'routed.db';digest=hashlib.sha256(db.read_bytes()).hexdigest()
script=dest/(prefix+'.tcl');log=dest/(prefix+'.log')
assert not script.exists() and not log.exists(), 'Use new evidence filenames'
script.write_text('''import_device eagle_s20.db -package EG4S20BG256
import_db ./routed.db
get_param place seed
get_param gate map_mode
get_clocks -verbose *
update_timing -mode final
report_qor -step route -file ./signoff.qor
report_timing_summary -ep_num 50 -file ./signoff.timing
report_timing_path -to [get_regs {*cluster_delta*}] -ep_num 32 -file ./signoff_fat_regs.timing
report_timing_path -to [get_regs {*e_cov_by*}] -ep_num 128 -file ./signoff_index_regs.timing
report_timing_path -to [get_regs {*background_cache_loader/sector_lba*}] -ep_num 32 -file ./signoff_background_regs.timing
report_clock_summary -file ./signoff.clocks
report_clock_intersection -file ./signoff.intersections
report_timing_ignored -ep_num 10 -file ./signoff.ignored
report_route_status -drc
update_timing -mode final
report_qor -step route -file ./signoff_refreshed.qor
report_timing_summary -ep_num 50 -file ./signoff_refreshed.timing
check_timing -verbose -file ./signoff.constraints
puts AUDIO_SIGNOFF_COMPLETE
exit
'''.replace('signoff',prefix),encoding='utf-8')
td='D:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/bin/td_commands_prompt.exe'
with log.open('xb') as output:
    status=subprocess.run([td,script.name],cwd=dest,stdout=output,stderr=subprocess.STDOUT,timeout=180).returncode
text=log.read_text(encoding='gbk',errors='replace')
assert status==0 and 'AUDIO_SIGNOFF_COMPLETE' in text and not re.search(r"couldn't read file|Assert failed|\b(?:ERROR|FATAL)\b",text,re.I)
after=metrics((dest/(prefix+'_refreshed.qor')).read_text(encoding='gbk'))
assert before==after,(before,after)
assert hashlib.sha256(db.read_bytes()).hexdigest()==digest
assert 'Check Corner        : Both (Slow and Fast)' in (dest/(prefix+'_refreshed.timing')).read_text(encoding='gbk')
constraints=(dest/(prefix+'.constraints')).read_text(encoding='gbk')
for check in ['no clock','clock definition','invalid constraint','combinational loops']:
    assert 'checking '+check+'(0)' in constraints,check
(dest/(prefix+'.result.json')).write_text(json.dumps({'internal_sta_pass':True,'external_io_signoff_complete':False,
    'clock_and_constraint_checks_pass':True,'constraint_report':str(dest/(prefix+'.constraints')),
    'metrics_ps':after,'database':str(db),'database_sha256':digest,
    'log_sha256':hashlib.sha256(log.read_bytes()).hexdigest()},indent=2))
print('INTERNAL_STA_VERIFIED',after,'DB',digest)

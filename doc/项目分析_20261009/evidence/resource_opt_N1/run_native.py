"""Run the frozen full TD flow in an isolated round; no main-tree writes."""
from pathlib import Path
import json, subprocess, sys, time

candidate = Path(sys.argv[1]).resolve()
script = candidate/'prj/native_candidate.tcl'
if not script.is_file() or not (candidate/'prj/VinylFPGA.al').is_file():
    raise SystemExit('Missing isolated project or flow script')
exe = Path('D:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/bin/td_commands_prompt.exe')
started = time.time()
log_path = candidate/'prj/native_candidate_run.log'
with log_path.open('w',encoding='utf-8') as log:
    proc = subprocess.run([str(exe)],input='source {'+script.as_posix()+'}\n',
        cwd=candidate/'prj',stdout=log,stderr=subprocess.STDOUT,text=True,
        creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0),timeout=1500)
text = log_path.read_text(encoding='utf-8',errors='replace')
required = ['final.area','final.qor','final.timing','final.constraints','route.status','routed.db','native_final.v']
missing = [name for name in required if not (candidate/'prj'/name).is_file()]
result = {'candidate':str(candidate),'exit_code':proc.returncode,'seconds':round(time.time()-started,3),
          'completion_marker':'NATIVE_ROUND_COMPLETE' in text,'missing_outputs':missing,
          'error_lines':[line for line in text.splitlines() if line.startswith(('RUN-8102','PHY-8023','SYN-900','ERROR:'))]}
(candidate/'prj/native_execution.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print(json.dumps(result,indent=2),flush=True)
if (candidate/'prj/final.qor').is_file():
    print((candidate/'prj/final.qor').read_text(encoding='utf-8',errors='replace'),flush=True)
raise SystemExit(0 if proc.returncode==0 and result['completion_marker'] and not missing else 1)

from pathlib import Path
import hashlib
import json
import re
import shutil

OUT=Path(__file__).resolve().parent
ROOT=OUT.parents[3]
ctx=json.loads((OUT/'isolated_context.json').read_text(encoding='utf-8'))
native=Path(ctx['native_isolated'])/'prj'
mcp=Path('C:/Users/Renni/AppData/Local/Temp/synthpilot-td/reports/6762a545367c4d95')
manifest=[]
for label,folder in [('current_native',native),('current_mcp',mcp),('baseline_sim',Path(ctx['isolated'])/'baseline_sim'),('baseline_full',Path(ctx['isolated'])/'baseline_full')]:
    dest=OUT/label
    dest.mkdir(exist_ok=True)
    for p in folder.iterdir():
        if p.is_file() and p.suffix in ('.area','.qor','.timing','.rpt','.status','.constraints','.exceptions','.tcl','.log','.txt','.json'):
            shutil.copy2(p,dest/p.name)
            manifest.append({'source':str(p),'artifact':str((dest/p.name).relative_to(OUT)),'sha256':hashlib.sha256(p.read_bytes()).hexdigest().upper(),'bytes':p.stat().st_size})
for p in [native/'routed.db',native/'gate.db',native/'native_gate.v',native/'native_final.v',Path(ctx['isolated'])/'prj/current_gate.v']:
    if p.is_file():
        manifest.append({'source':str(p),'artifact':None,'sha256':hashlib.sha256(p.read_bytes()).hexdigest().upper(),'bytes':p.stat().st_size})
(OUT/'artifact_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
full=json.loads((OUT/'baseline_full/results.json').read_text(encoding='utf-8'))
old=json.loads((OUT/'candidate_analysis.json').read_text(encoding='utf-8'))['historical_regression']
fail_details=[]
for name,passed in full.items():
    if passed: continue
    log=(OUT/'baseline_full'/f'{name}.log').read_text(encoding='utf-8',errors='replace')
    kind='compile/interface' if 'error:' in log or 'Unknown module type' in log else 'simulation assertion'
    evidence=[line for line in log.splitlines() if ('error:' in line or 'FATAL:' in line or 'FAIL' in line)]
    fail_details.append({'name':name,'category':kind,'evidence':evidence[:3]})
summary={'current_count':len(full),'current_pass':sum(full.values()),'current_fail':sum(not v for v in full.values()),'failed_set_matches_historical':set(k for k,v in full.items() if not v)==set(old['failed']),'failures':fail_details,'fresh_directed':json.loads((OUT/'baseline_sim/results.json').read_text(encoding='utf-8'))}
area=(native/'final_verbose.area').read_text(errors='replace')
summary['native_utilization']={key:int(value) for key,value in re.findall(r'^#(mslice|lslice|plb|lut|reg|bram|dsp)\s+(\d+)',area,re.M)}
summary['native_complete']='NATIVE_ROUND_COMPLETE' in (native/'native_baseline_run.log').read_text(errors='replace')
summary['native_qor_identical_to_E_confirm']=(native/'final.qor').read_bytes()==(OUT/'historical/E_confirm/final.qor').read_bytes()
summary['input_files_changed']=[x['path'] for x in json.loads((OUT/'input_manifest.json').read_text(encoding='utf-8')) if hashlib.sha256((ROOT/x['path']).read_bytes()).hexdigest().upper()!=x['sha256']]
(OUT/'verification_summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({k:v for k,v in summary.items() if k not in ('failures','fresh_directed')},ensure_ascii=True,indent=2))
print('Failure categories:',{k:sum(x['category']==k for x in fail_details) for k in ('compile/interface','simulation assertion')})

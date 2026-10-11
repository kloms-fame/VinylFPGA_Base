"""Archive measured reports/tests with separate MCP and native metrics."""
from pathlib import Path
import difflib, hashlib, json, os, re, shutil, sys

OUT = Path(sys.argv[1]).resolve()
ROOT = OUT.parents[3]
context = json.loads((OUT/'context.json').read_text(encoding='utf-8'))
before, after = Path(context['before']), Path(context['after'])
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest().upper()
manifest = []
def archive(path, relative):
    dest = OUT/relative
    dest.parent.mkdir(parents=True,exist_ok=True)
    shutil.copy2(path,dest)
    manifest.append({'source':str(path),'artifact':relative,'sha256':sha(dest),'bytes':dest.stat().st_size})

for stage,folder in [('before',before),('after',after)]:
    for p in (folder/'sim').glob('resource_*'):
        if p.is_file() and p.suffix in ('.json','.log','.diff'):
            archive(p,stage+'/'+p.relative_to(folder).as_posix())
        if p.is_dir():
            for f in p.rglob('*'):
                if f.is_file() and f.suffix in ('.json','.log','.diff'):
                    archive(f,stage+'/'+f.relative_to(folder).as_posix())
    for f in ('src/SD/fat32_volume_scanner.v','src/SD/song_index_db.v'):
        archive(folder/f,stage+'/'+f)
    for f in (folder/'sim').glob('tb_resource_*.v'):
        archive(f,stage+'/sim/'+f.name)
    for f in (folder/'sim/optimization').glob('*.v'):
        archive(f,stage+'/sim/optimization/'+f.name)
    for name in ('mcp_gate.v','mcp_gate_fresh.v'):
        p=folder/'prj'/name
        if p.is_file():manifest.append({'source':str(p),'artifact':None,'sha256':sha(p),'bytes':p.stat().st_size})

native_before = Path(context.get('native_before',json.loads((OUT.parent/'resource_review_20261011_followup/isolated_context.json').read_text(encoding='utf-8'))['native_isolated']))/'prj'
for stage,folder in [('before',native_before),('after',after/'prj')]:
    for p in folder.glob('*'):
        if p.is_file() and p.suffix in ('.area','.qor','.timing','.constraints','.exceptions','.status','.tcl','.log','.json'):
            archive(p,'native_'+stage+'/'+p.name)
    for name in ('gate.db','place.db','routed.db','native_gate.v','native_final.v'):
        p=folder/name
        if p.is_file():manifest.append({'source':str(p),'artifact':None,'sha256':sha(p),'bytes':p.stat().st_size})

mcp_root=Path(os.environ['TEMP'])/'synthpilot-td/reports'
for stage,prefix in context['mcp_prefixes'].items():
    for p in mcp_root.rglob(prefix+'*'):
        if p.is_file():archive(p,'mcp_'+stage+'/'+p.name)

changed=[]
for p in (before/'src').rglob('*'):
    if p.is_file() and sha(p)!=sha(after/p.relative_to(before)):
        changed.append(p.relative_to(before).as_posix())
        diff=''.join(difflib.unified_diff(p.read_text(encoding='utf-8').splitlines(True),
            (after/p.relative_to(before)).read_text(encoding='utf-8').splitlines(True),
            fromfile='before/'+p.relative_to(before).as_posix(),tofile='after/'+p.relative_to(before).as_posix()))
        (OUT/(p.stem+'.patch')).write_text(diff,encoding='utf-8')

def native_metrics(folder):
    area,qor=folder/'final_verbose.area',folder/'final.qor'
    if not area.is_file() or not qor.is_file():return None
    a,q=area.read_text(errors='replace'),qor.read_text(errors='replace')
    value={}
    for key,label in [('mslice','mslice'),('lslice','lslice'),('plb','plb'),('lut','lut'),('reg','reg'),('bram','bram'),('dsp','dsp')]:
        m=re.search(r'#'+label+r'\s+(\d+)',a)
        value[key]=int(m[1]) if m else None
    value['slice']=value['mslice']+value['lslice']
    for key,label in [('setup_ps','Setup WNS'),('hold_ps','Hold WNS'),('setup_violations','Num of violated S-EP'),('hold_violations','Num of violated H-EP'),('wire','Wire length')]:
        m=re.search(r'\|\s*'+re.escape(label)+r'\s*\|\s*(-?\d+)',q)
        value[key]=int(m[1]) if m else None
    return value

result={'changed_src':changed,'native_before':native_metrics(native_before),'native_after':native_metrics(after/'prj'),
        'native_before_reused_from':str(native_before),'artifacts':len(manifest)}
before_full=Path(context.get('before_full',str(before/'sim/resource_N1_before_full')))
for label,folder in [('before_full',before_full),('after_full',after/('sim/resource_'+context.get('round','N1')+'_full'))]:
    p=folder/'results.json'
    if p.is_file():
        r=json.loads(p.read_text());result[label]={'count':len(r),'pass':sum(r.values()),'failed':[k for k,v in r.items() if not v]}
        if label=='before_full' and context.get('before_full'):
            for f in folder.glob('*'):
                if f.is_file() and f.suffix in ('.log','.json'):
                    archive(f,'baseline_full_reused/'+f.name)
result['artifacts']=len(manifest)
if result['native_before'] and result['native_after']:
    result['native_delta']={k:result['native_after'][k]-v for k,v in result['native_before'].items() if v is not None and result['native_after'][k] is not None}
(OUT/'artifact_manifest.json').write_text(json.dumps(manifest,indent=2,ensure_ascii=False),encoding='utf-8')
(OUT/'measurement_summary.json').write_text(json.dumps(result,indent=2,ensure_ascii=False),encoding='utf-8')
print(json.dumps(result,indent=2,ensure_ascii=True))

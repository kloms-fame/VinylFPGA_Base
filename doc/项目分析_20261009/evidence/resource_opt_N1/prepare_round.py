from pathlib import Path
import datetime, hashlib, json, os, re, shutil, subprocess

ROOT = Path(__file__).resolve().parents[4]
OUT = Path(__file__).resolve().parent
STAMP = datetime.datetime.now().strftime('%Y%m%d_%H%M%S')
BASE = Path(os.environ['TEMP']) / ('vinylfpga_resource_N1_N2_' + STAMP)
BASE.mkdir()
OUT.mkdir(parents=True, exist_ok=True)
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest().upper()
inputs = [p for d in ('src','constraints') for p in (ROOT/d).rglob('*') if p.is_file()]
inputs.append(ROOT/'prj/VinylFPGA.al')
manifest = [{'path':p.relative_to(ROOT).as_posix(),'sha256':sha(p)} for p in sorted(inputs)]
old = json.loads((OUT.parent/'resource_review_20261011_followup/input_manifest.json').read_text(encoding='utf-8'))
oldhash = {e['path']:e['sha256'] for e in old}
changes = [e['path'] for e in manifest if oldhash.get(e['path']) != e['sha256']]
tracked = subprocess.check_output(['git','ls-files','-z'],cwd=ROOT).decode('utf-8').split('\0')
alltracked = [{'path':p,'sha256':sha(ROOT/p)} for p in tracked if p and (ROOT/p).is_file()]
for name,value in [('input_manifest.json',manifest),('all_tracked_manifest.json',alltracked),('prior_analysis_input_changes.json',changes)]:
    (OUT/name).write_text(json.dumps(value,ensure_ascii=False,indent=2),encoding='utf-8')
(OUT/'git_status_before.txt').write_bytes(subprocess.check_output(['git','-c','core.quotepath=false','status','--short'],cwd=ROOT))
(OUT/'git_head.txt').write_bytes(subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT))
before = BASE/'N1_before'
before.mkdir()
for folder in ('src','constraints','sim','tools'):
    shutil.copytree(ROOT/folder,before/folder,ignore=shutil.ignore_patterns('__pycache__','*.vvp','*.vcd','*.fst'))
shutil.copytree(ROOT/'doc/资源',before/'doc/资源')
(before/'prj').mkdir()
project = (ROOT/'prj/VinylFPGA.al').read_text(encoding='utf-8')
project = re.sub(r'(<Project\b[^>]*\bPath=")[^"]*(")',lambda m:m[1]+(before/'prj').as_posix()+m[2],project,count=1)
(before/'prj/VinylFPGA.al').write_text(project,encoding='utf-8')
after = BASE/'N1_after'
shutil.copytree(before,after)
p = after/'prj/VinylFPGA.al'
p.write_text(p.read_text(encoding='utf-8').replace(before.as_posix(),after.as_posix()),encoding='utf-8')
template = (OUT.parent/'resource_review_20261011_followup/current_native/native_baseline.tcl').read_text(encoding='utf-8')
context = json.loads((OUT.parent/'resource_review_20261011_followup/isolated_context.json').read_text(encoding='utf-8'))
for folder in (before,after):
    script = template.replace(Path(context['native_isolated']).as_posix(),folder.as_posix())
    (folder/'prj/native_candidate.tcl').write_text(script,encoding='utf-8')
value = {'workspace':str(ROOT),'base':str(BASE),'before':str(before),'after':str(after),'prior_analysis_input_changes':changes,
         'authorization':'User approved N1 then N2, preserving all existing functionality and compatibility; no bitgen or commits.'}
(OUT/'context.json').write_text(json.dumps(value,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(value,ensure_ascii=True,indent=2))

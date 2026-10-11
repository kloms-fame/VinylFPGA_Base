from pathlib import Path
import datetime
import hashlib
import json
import os
import shutil
import subprocess
import re

ROOT = Path(__file__).resolve().parents[4]
OUT = Path(__file__).resolve().parent
STAMP = datetime.datetime.now().strftime('%Y%m%d_%H%M%S')
ISOLATED = Path(os.environ['TEMP']) / ('vinylfpga_resource_review_' + STAMP)
OUT.mkdir(parents=True, exist_ok=True)
ISOLATED.mkdir()

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()

def write(name, value):
    (OUT / name).write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding='utf-8')

inputs = sorted([p for folder in ('src', 'constraints') for p in (ROOT / folder).rglob('*') if p.is_file()])
inputs += [ROOT / 'prj/VinylFPGA.al']
baseline = [{'path':p.relative_to(ROOT).as_posix(), 'sha256':sha(p), 'bytes':p.stat().st_size} for p in inputs]
write('input_manifest.json', baseline)
(OUT / 'git_status_before.txt').write_bytes(subprocess.check_output(['git','-c','core.quotepath=false','status','--short'],cwd=ROOT))
(OUT / 'git_head.txt').write_bytes(subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT))
for folder in ('src', 'constraints'):
    shutil.copytree(ROOT / folder, ISOLATED / folder)
(ISOLATED / 'prj').mkdir()
# TD's .al uses literal ampersands (UsedInP&R), so preserve its vendor format.
project = (ROOT / 'prj/VinylFPGA.al').read_text(encoding='utf-8')
project = re.sub(r'(<Project\b[^>]*\bPath=")[^"]*(")', lambda m:m[1]+(ISOLATED/'prj').as_posix()+m[2], project, count=1)
(ISOLATED / 'prj/VinylFPGA.al').write_text(project, encoding='utf-8')
missing = []
for path in re.findall(r'<File\s+Path="([^"]+)"', project):
    if not ((ISOLATED / 'prj') / path).resolve().is_file():
        missing.append(path)
write('isolated_context.json', {'workspace':str(ROOT),'isolated':str(ISOLATED),'project':str(ISOLATED/'prj/VinylFPGA.al'),'missing_project_files':missing})
old = Path(os.environ['TEMP']) / 'vinylfpga_optE_native_confirm_v4'
comparison = []
for entry in baseline:
    if entry['path'].startswith(('src/','constraints/')):
        p = old / entry['path']
        if not p.is_file() or sha(p) != entry['sha256']:
            comparison.append({'path':entry['path'], 'historical_sha':sha(p) if p.is_file() else None,'current_sha':entry['sha256']})
write('historical_input_differences.json', comparison)
history = {
    'E_before':Path(os.environ['TEMP'])/'vinylfpga_optE_20261011b/before/prj',
    'E_after':Path(os.environ['TEMP'])/'vinylfpga_optE_20261011b/after/prj',
    'E_confirm':old/'prj',
    'D_after':Path(os.environ['TEMP'])/'vinylfpga_candD_20261011/native_after/prj',
    'F_after':Path(os.environ['TEMP'])/'vinylfpga_candF_20261011/native_after/prj',
    'diagnostic_after':Path(os.environ['TEMP'])/'vinylfpga_sp_diag_after_v2/prj',
}
archive = []
for label, folder in history.items():
    dest = OUT / 'historical' / label
    dest.mkdir(parents=True, exist_ok=True)
    for p in folder.glob('*'):
        if p.is_file() and p.suffix in ('.area','.qor','.timing','.status','.constraints','.exceptions','.tcl','.log'):
            shutil.copy2(p, dest/p.name)
            archive.append({'label':label,'source':str(p),'copy':str((dest/p.name).relative_to(OUT)),'sha256':sha(p)})
write('historical_artifact_manifest.json', archive)
hierarchy = []
area = OUT/'historical/E_confirm/final_verbose.area'
if area.is_file():
    for line in area.read_text(errors='replace').splitlines():
        cols = [x.strip() for x in line.split('|')]
        if len(cols)==10 and all(x.isdigit() for x in cols[3:9]):
            hierarchy.append(dict(zip(('instance','module','le','lut','ripple','seq','bram','dsp'),cols[1:9])))
write('historical_hierarchy.json', hierarchy)
print(json.dumps({'isolated':str(ISOLATED),'input_files':len(baseline),'missing':missing,'historical_input_differences':comparison,'historical_artifacts':len(archive),'hierarchy_rows':len(hierarchy)},ensure_ascii=True,indent=2))

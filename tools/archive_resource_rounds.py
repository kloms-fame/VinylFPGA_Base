"""Copy small, reviewable evidence out of ignored TD snapshot directories."""
from pathlib import Path
import difflib
import json
import re
import shutil

ROOT = Path(__file__).resolve().parents[1]
RUNS = ROOT / 'prj/resource_opt_verified_20261005'
HISTORY = ROOT / 'prj/resource_history/20261005_verified'
HISTORY.mkdir(parents=True, exist_ok=True)
rows = []
for run in sorted(RUNS.iterdir()):
    qor_files = list(run.glob('vfpga_*.qor')) or list(run.glob('final.qor'))
    area_files = list(run.glob('vfpga_*.area')) or list(run.glob('final.area'))
    if not qor_files or not area_files:
        continue
    area = area_files[0].read_text(encoding='gbk', errors='replace')
    qor = qor_files[0].read_text(encoding='gbk', errors='replace')
    def metric(text, pattern):
        m = re.search(pattern, text, re.M)
        return int(m[1]) if m else None
    row = dict(round=run.name, lut=metric(area,r'^#lut\s+(\d+)'),
               ff=metric(area,r'^#reg\s+(\d+)'), bram9k=metric(area,r'^\s*#bram9k\s+(\d+)'),
               bram32k=metric(area,r'^#bram32k\s+(\d+)'), dsp=metric(area,r'^#dsp\s+(\d+)'),
               slices=metric(qor,r'#slices\s*\|\s*(\d+)'),
               setup_ps=metric(qor,r'Setup WNS\s*\|\s*(-?\d+)'),
               hold_ps=metric(qor,r'Hold WNS\s*\|\s*(-?\d+)'))
    rows.append(row)
    dest = HISTORY / run.name
    dest.mkdir(exist_ok=True)
    for p in run.iterdir():
        if p.is_file() and (p.suffix in ('.area','.qor','.timing','.status','.constraints','.params','.exceptions')
                           or p.name in ('inputs.sha256.json','native_build.tcl','round_settings.tcl',
                                         'bitstream.sha256','release_bitgen.tcl','release_download.tcl')):
            shutil.copy2(p,dest/p.name)
    if (run/'regression.log').exists():
        shutil.copy2(run/'regression.log',dest/'regression_results.md')
    for step in ('release_bitgen','release_download'):
        if (run/(step+'.log')).exists():
            shutil.copy2(run/(step+'.log'),dest/(step+'_results.md'))
    patches = []
    for original in (RUNS/'baseline/src').rglob('*.v'):
        rel = original.relative_to(RUNS/'baseline')
        changed = run / rel
        if changed.exists() and original.read_bytes()!=changed.read_bytes():
            before=original.read_text(encoding='utf-8',errors='replace').splitlines(keepends=True)
            after=changed.read_text(encoding='utf-8',errors='replace').splitlines(keepends=True)
            patches.extend(difflib.unified_diff(before,after,fromfile='baseline/'+rel.as_posix(),tofile=run.name+'/'+rel.as_posix()))
    (dest/'candidate.patch').write_text(''.join(patches),encoding='utf-8')
    (dest/'metrics.json').write_text(json.dumps(row,indent=2),encoding='utf-8')
(HISTORY/'comparison.json').write_text(json.dumps(rows,indent=2),encoding='utf-8')
print(json.dumps(rows,indent=2))

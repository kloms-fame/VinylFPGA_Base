"""Freeze task inputs into a new TD project, without touching existing runs."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import shutil
import subprocess
import xml.etree.ElementTree as ET

p=argparse.ArgumentParser(description=__doc__)
p.add_argument('destination',type=Path)
p.add_argument('--template',required=True,type=Path)
a=p.parse_args()
root=Path(__file__).resolve().parents[1]
dest=a.destination.resolve()
assert subprocess.check_output(['git','branch','--show-current'],cwd=root).strip()==b'main'
assert not dest.exists(), 'Use a new snapshot'
dest.mkdir(parents=True)
for name in ['src','constraints']:
    shutil.copytree(root/name,dest/name)
raw=a.template.read_text(encoding='utf-8')
old=re.search(r'<Project[^>]*Path="([^"]+)"',raw)[1]
raw=raw.replace(old,dest.as_posix())
(dest/'VinylFPGA.al').write_text(raw,encoding='utf-8')
# TD's project format has the literal UsedInP&R attribute name. Normalize
# the ampersand only for validation, preserving the vendor project bytes.
x=ET.fromstring(re.sub(r'&(?!amp;|lt;|gt;|quot;|apos;|#)','&amp;',raw))
for n in x.findall('.//File'):
    f=Path(n.attrib['Path'])
    assert f.is_file() and f.resolve().is_relative_to(dest), str(f)
inputs={f.relative_to(dest).as_posix():hashlib.sha256(f.read_bytes()).hexdigest()
        for f in dest.rglob('*') if f.is_file()}
(dest/'inputs.sha256.json').write_text(json.dumps(inputs,indent=2))
(dest/'provenance.json').write_text(json.dumps({
    'branch':'main','head':subprocess.check_output(['git','rev-parse','HEAD'],cwd=root).decode().strip(),
    'source_root':str(root),'seed':6,'map_mode':'area_prior',
    'template_sha256':hashlib.sha256(a.template.read_bytes()).hexdigest(),
    'tools_sha256':{n:hashlib.sha256((root/'tools'/n).read_bytes()).hexdigest()
                    for n in ['snapshot_audio_timing.py','run_audio_timing_phase.py','run_audio_cache_regression.py']}
},indent=2))
print(dest)

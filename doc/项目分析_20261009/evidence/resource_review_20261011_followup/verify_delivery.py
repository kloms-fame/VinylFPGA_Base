"""Read-only audit of product inputs and archived analysis evidence."""
from pathlib import Path
import hashlib
import json
import re
import subprocess

OUT = Path(__file__).resolve().parent
ROOT = OUT.parents[3]
DOC = OUT.parents[1]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


inputs = json.loads((OUT / 'input_manifest.json').read_text(encoding='utf-8'))
changed = [item['path'] for item in inputs
           if not (ROOT / item['path']).is_file()
           or digest(ROOT / item['path']) != item['sha256']]
artifacts = json.loads((OUT / 'artifact_manifest.json').read_text(encoding='utf-8'))
bad_artifacts = []
for item in artifacts:
    path = OUT / item['artifact'] if item['artifact'] else Path(item['source'])
    if not path.is_file() or digest(path) != item['sha256']:
        bad_artifacts.append(str(path))
historical = json.loads((OUT / 'historical_artifact_manifest.json').read_text(encoding='utf-8'))
for item in historical:
    path = OUT / item['copy']
    if not path.is_file() or digest(path) != item['sha256']:
        bad_artifacts.append(str(path))

before = (OUT / 'git_status_before.txt').read_text(encoding='utf-8').splitlines()
current = subprocess.run(
    ['git', '-c', 'core.quotepath=false', 'status', '--short'],
    cwd=ROOT, check=True, capture_output=True, encoding='utf-8').stdout.splitlines()
tracked_before = [line for line in before if not line.startswith('??')]
tracked_after = [line for line in current if not line.startswith('??')]

documents = [DOC / '当前进度复核与资源优化续轮分析报告_20261011.md',
             DOC / '资源优化续轮实施方案_待确认_20261011.md']
missing_links = []
document_info = []
for path in documents:
    content = path.read_text(encoding='utf-8')
    for target in re.findall(r'\]\(([^)]+)\)', content):
        if '://' not in target and not target.startswith('#'):
            if not (path.parent / target).exists():
                missing_links.append({'document': path.name, 'target': target})
    document_info.append({'path': str(path), 'sha256': digest(path),
                          'lines': len(content.splitlines())})

result = {
    'input_count': len(inputs),
    'input_files_changed': changed,
    'artifact_count': len(artifacts),
    'historical_artifact_count': len(historical),
    'bad_artifacts': bad_artifacts,
    'tracked_git_status_unchanged': tracked_before == tracked_after,
    'tracked_dirty_count': len(tracked_after),
    'missing_document_links': missing_links,
    'documents': document_info,
}
(OUT / 'delivery_verification.json').write_text(
    json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
print(json.dumps(result, ensure_ascii=False, indent=2))
raise SystemExit(1 if changed or bad_artifacts or missing_links
                 or tracked_before != tracked_after else 0)

"""Verify original workspace content, archived outputs, and regression identity."""
from pathlib import Path
import hashlib, json, re, subprocess, sys

OUT = Path(__file__).resolve().parent
ROOT = OUT.parents[3]
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest().upper()
allowed = json.loads(sys.argv[1]) if len(sys.argv) > 1 else {}
results = {'allowed_product_changes': allowed}
for label, manifest_name in [('product_inputs', 'input_manifest.json'), ('original_tracked', 'all_tracked_manifest.json')]:
    items = json.loads((OUT.parent/'resource_opt_N1'/manifest_name).read_text(encoding='utf-8'))
    errors = []
    for item in items:
        p = ROOT/item['path']
        expected = allowed.get(item['path'], item['sha256']).upper()
        if not p.is_file() or sha(p) != expected:
            errors.append(item['path'])
    results[label] = {'checked': len(items), 'errors': errors}

results['rounds'] = {}
for name in ('resource_opt_N1', 'resource_opt_N2', 'resource_opt_N2_polarity'):
    folder = OUT.parent/name
    manifest = json.loads((folder/'artifact_manifest.json').read_text(encoding='utf-8'))
    errors = []
    for item in manifest:
        p = folder/item['artifact'] if item['artifact'] else Path(item['source'])
        if not p.is_file() or sha(p) != item['sha256'].upper():
            errors.append(str(p))
    summary = json.loads((folder/'measurement_summary.json').read_text(encoding='utf-8'))
    b, a = summary['before_full'], summary['after_full']
    same = b['count'] == a['count'] == 53 and b['pass'] == a['pass'] == 40 and set(b['failed']) == set(a['failed'])
    native = json.loads((folder/'native_after/native_execution.json').read_text(encoding='utf-8'))
    completed = native['exit_code'] == 0 and native['completion_marker'] and not native['missing_outputs'] and not native['error_lines']
    results['rounds'][name] = {'archived_or_referenced_files': len(manifest), 'hash_errors': errors,
        'default_53_regression_same_failure_set': same, 'native_complete': completed,
        'native_final': summary['native_after']}

results['git_head'] = subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()
initial_head = (OUT.parent/'resource_opt_N1/git_head.txt').read_text(encoding='utf-8-sig').strip()
results['head_unchanged'] = results['git_head'] == initial_head
results['report_link_errors'] = []
for name in ('资源优化续轮_N1实施结果.md','资源优化续轮_N2实施结果.md','资源优化续轮_N1_N2执行记录_20261011.md'):
    p = ROOT/'doc/项目分析_20261009'/name
    if not p.is_file():
        results['report_link_errors'].append(str(p))
        continue
    for target in re.findall(r'\]\(([^)]+)\)', p.read_text(encoding='utf-8')):
        if '://' not in target and not (p.parent/target.split('#')[0]).exists():
            results['report_link_errors'].append(name+': '+target)
results['passed'] = results['head_unchanged'] and all(not results[k]['errors'] for k in ('product_inputs','original_tracked')) and all(
    not r['hash_errors'] and r['default_53_regression_same_failure_set'] and r['native_complete'] for r in results['rounds'].values()) and not results['report_link_errors']
(OUT/'closeout_verification.json').write_text(json.dumps(results,indent=2,ensure_ascii=False),encoding='utf-8')
print(json.dumps(results,indent=2,ensure_ascii=True))
sys.exit(0 if results['passed'] else 1)

"""校验收尾候选的源码、产物哈希和布线时序；最终验收另行检查。"""
import argparse
import hashlib
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def verify(root, manifest_path, require_final=False):
    manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
    for role in ('bit', 'qor'):
        if manifest[role] not in manifest['artifacts']:
            raise RuntimeError('交付文件未纳入哈希清单：' + role)
    current = {p.relative_to(root).as_posix()
               for folder in ('src', 'constraints')
               for p in (root / folder).rglob('*') if p.is_file()}
    if current != set(manifest['inputs']):
        raise RuntimeError('源码或约束文件集合已变化，需重新构建')
    for category in ('inputs', 'artifacts'):
        for name, digest in manifest[category].items():
            path = (root / name).resolve()
            if not path.is_relative_to(root.resolve()):
                raise RuntimeError('清单路径超出工程目录')
            if not path.is_file() or sha(path) != digest:
                raise RuntimeError('文件缺失或哈希不一致：' + name)
    if (root / manifest['bit']).stat().st_size == 0:
        raise RuntimeError('bit 文件为空')
    qor = (root / manifest['qor']).read_text(encoding='utf-8')
    for field in ('Setup WNS', 'Hold WNS', 'Setup TNS', 'Hold TNS',
                  'Num of violated S-EP', 'Num of violated H-EP'):
        match = re.search(re.escape(field) + r'\s*\|\s*(-?\d+)', qor)
        if not match:
            raise RuntimeError('缺少布线指标：' + field)
        value = int(match[1])
        if (field.endswith('WNS') and value <= 0) or (not field.endswith('WNS') and value != 0):
            raise RuntimeError('布线时序未通过：' + field)
    if require_final and (manifest['board_acceptance'] != 'passed'
                          or manifest['open_items']):
        raise RuntimeError('最终验收未完成：' + '；'.join(manifest['open_items']))
    return {'candidate_verified': True, 'board_acceptance': manifest['board_acceptance'],
            'open_items': manifest['open_items']}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--manifest', type=Path,
                        default=ROOT/'doc/开发方案/closeout_candidate_20261029.json')
    parser.add_argument('--require-final', action='store_true')
    args = parser.parse_args()
    try:
        result = verify(ROOT, args.manifest, args.require_final)
    except (RuntimeError, OSError, ValueError, KeyError) as error:
        parser.exit(1, str(error) + '\n')
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()

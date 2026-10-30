"""Create and verify a source-only contest ZIP, without Git history or TD Runs."""
import argparse
import hashlib
import json
from pathlib import Path
import zipfile
from verify_submission import ROOT, verify


def package(output):
    output = Path(output).resolve()
    if output.suffix.lower() != '.zip':
        raise ValueError('Output must use a .zip filename')
    if any(output.is_relative_to(ROOT/d) for d in ('src', 'constraints', 'prj', 'tools', 'sim', 'doc')):
        raise ValueError('Write submission archives outside source directories, e.g. output/')
    verify(ROOT)
    paths = [ROOT/'README.md', ROOT/'.gitignore', ROOT/'requirements-media.txt',
             ROOT/'prj/VinylFPGA.al']
    allowed = {'tools': {'.py', '.ps1', '.tcl', '.md', '.txt'},
               'sim': {'.v', '.vh', '.sv', '.hex', '.mem', '.do', '.md'},
               'doc': {'.md', '.json', '.pdf', '.pptx'}}
    for directory in ('src', 'constraints', 'tools', 'sim', 'doc'):
        paths += [p for p in (ROOT/directory).rglob('*') if p.is_file()
                  and not any(part in ('__pycache__', 'work', 'run', '.pytest_cache') for part in p.parts)
                  and (directory not in allowed or p.suffix.lower() in allowed[directory])
                  and p.name != 'results.json']
    if len(set(paths)) != len(paths):
        raise ValueError('Duplicate package entry')
    contents = {p.relative_to(ROOT).as_posix(): p.read_bytes() for p in sorted(paths)}
    manifest = {name: hashlib.sha256(data).hexdigest() for name, data in contents.items()}
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, 'x', compression=zipfile.ZIP_DEFLATED) as z:
        for name, data in contents.items():
            z.writestr('VinylFPGA/'+name, data)
        z.writestr('VinylFPGA/SHA256SUMS.json', json.dumps(manifest, ensure_ascii=False, indent=2))
    with zipfile.ZipFile(output) as z:
        if z.testzip() is not None:
            raise ValueError('ZIP integrity check failed')
        for name, expected in manifest.items():
            if hashlib.sha256(z.read('VinylFPGA/'+name)).hexdigest() != expected:
                raise ValueError('ZIP hash mismatch: '+name)
    checksum = hashlib.sha256(output.read_bytes()).hexdigest()
    Path(str(output)+'.sha256').write_text(f'{checksum}  {output.name}\n', encoding='utf-8')
    return {'zip': str(output), 'files': len(contents), 'bytes': output.stat().st_size, 'sha256': checksum}


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--output', type=Path, required=True, help='A new ZIP path')
    args = p.parse_args()
    try:
        print(json.dumps(package(args.output), ensure_ascii=False, indent=2))
    except (ValueError, OSError) as error:
        p.exit(1, f'PACKAGE_FAIL: {error}\n')

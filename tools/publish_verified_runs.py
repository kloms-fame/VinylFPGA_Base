"""Import verified same-input databases and regenerate the original TD Runs.

No timing numbers are edited: TD recalculates reports from the actual saved
gate/route databases. Back up the previous Runs before publishing.
"""
from pathlib import Path
import argparse
import datetime
import hashlib
import json
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def quote(path):
    value = Path(path).resolve().as_posix()
    if any(c in value for c in '{}\n\r'):
        raise ValueError('Unsupported TD path')
    return '{' + value + '}'


def assert_inputs(build):
    hashes = json.loads((build / 'inputs.sha256.json').read_text())
    current = {p.relative_to(ROOT).as_posix() for folder in ('src', 'constraints')
               for p in (ROOT / folder).rglob('*') if p.is_file()}
    assert current == set(hashes), 'Source/constraint file set differs'
    for rel, expected in hashes.items():
        assert digest(ROOT / rel) == expected, 'Input differs: ' + rel
    expected_project = (ROOT / 'prj/VinylFPGA.al').read_text(encoding='utf-8')
    expected_project = expected_project.replace('"../', '"' + build.as_posix() + '/')
    expected_project = expected_project.replace('Path="' + (ROOT / 'prj').as_posix() + '"',
                                                'Path="' + build.as_posix() + '"')
    assert expected_project == (build / 'VinylFPGA.al').read_text(encoding='utf-8'), 'Project differs'


def passing_qor(path):
    text = path.read_text(encoding='gbk', errors='replace')
    values = {}
    for key in ('Setup WNS', 'Hold WNS', 'Setup TNS', 'Hold TNS'):
        match = re.search(re.escape(key) + r'\s*\|\s*(-?\d+)', text)
        assert match, 'Missing timing metric: ' + key
        values[key] = int(match[1])
    assert values['Setup WNS'] >= 0 and values['Hold WNS'] >= 0, 'Negative final WNS'
    assert values['Setup TNS'] == values['Hold TNS'] == 0, 'Negative final TNS'
    return values


def main():
    project_text = (ROOT / 'prj/VinylFPGA.al').read_text(encoding='utf-8')
    if re.search(r'<MultiSeed>\s*<Property\b[^>]*Enable="true"', project_text):
        raise RuntimeError('Original AL uses GUI MultiSeed. Rebuild it with Run All; historical database import is disabled.')
    parser = argparse.ArgumentParser()
    parser.add_argument('round')
    parser.add_argument('--td', type=Path, default=Path('D:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/bin/td_commands_prompt.exe'))
    args = parser.parse_args()
    assert re.fullmatch(r'[A-Za-z0-9_]+', args.round), 'Invalid round name'
    build = (ROOT / 'prj/resource_opt_verified_20261005' / args.round).resolve(strict=True)
    assert_inputs(build)
    passing_qor(build / 'final.qor')
    for name in ('gate.db', 'rtl.db', 'place.db', 'routed.db', 'VinylFPGA_optimized.bit'):
        assert (build / name).is_file(), 'Missing verified artifact: ' + name
    assert digest(build / 'VinylFPGA_optimized.bit') in (build / 'bitstream.sha256').read_text()
    checks = (build / 'final.constraints').read_text(encoding='gbk', errors='replace')
    for key in ('no clock', 'invalid constraint', 'combinational loops'):
        assert re.search(r'checking ' + re.escape(key) + r'\(0\)', checks), 'Timing structure: ' + key

    runs = (ROOT / 'prj/VinylFPGA_Runs').resolve(strict=True)
    assert runs.is_relative_to((ROOT / 'prj').resolve()), 'Runs outside project'
    stamp = datetime.datetime.now().strftime('%Y%m%d_%H%M%S_%f')
    backup = build / ('original_runs_before_' + stamp)
    # Preserve all GUI results, databases, bitstreams and state files.
    shutil.copytree(runs, backup)

    def execute(label, lines, cwd):
        script = build / ('publish_' + label + '_' + stamp + '.tcl')
        log = script.with_suffix('.log')
        marker = 'VERIFIED_RUNS_' + label.upper() + '_COMPLETE'
        script.write_text('\n'.join(lines + ['puts ' + marker, 'exit']) + '\n', encoding='utf-8')
        with log.open('wb') as stream:
            result = subprocess.run([args.td.as_posix(), script.as_posix()], cwd=cwd, stdout=stream,
                                    stderr=subprocess.STDOUT, timeout=180)
        output = log.read_text(encoding='gbk', errors='replace')
        assert result.returncode == 0 and marker in output and not re.search(r'\b(?:ERROR|FATAL)\b', output), str(log)
        return log

    syn, phy = runs / 'syn_1', runs / 'phy_1'
    gate_log = execute('gate', [
        'import_device eagle_s20.db -package EG4S20BG256',
        'import_db ' + quote(build / 'gate.db'),
        'update_timing',
        'report_area -file VinylFPGA_gate.area',
        'report_timing_status -file VinylFPGA_gate.ts',
        'report_timing_summary -file VinylFPGA_gate.timing',
        'report_timing_summary -file final_timing.rpt',
        'report_qor -step gate -file gate.qor',
        'flow_status -file flow.status',
        'export_db ' + quote(syn / 'VinylFPGA_gate.db'),
    ], syn)
    place_log = execute('place', [
        'import_device eagle_s20.db -package EG4S20BG256',
        'import_db ' + quote(build / 'place.db'),
        'update_timing -mode manhattan',
        'report_qor -step place -file place.qor',
        'report_timing_status -file VinylFPGA_place.ts',
        'report_timing_summary -file VinylFPGA_place.timing',
        'flow_status -file place_flow.status',
    ], phy)
    route_log = execute('route', [
        'import_device eagle_s20.db -package EG4S20BG256',
        'import_db ' + quote(build / 'routed.db'),
        'update_timing -mode final',
        'report_area -io_info -file VinylFPGA_phy.area',
        'report_area -verbose -file final_verbose.area',
        'report_timing_status -file VinylFPGA_phy.ts',
        'report_timing_summary -file VinylFPGA_pr.timing',
        'report_timing_summary -file final_timing.rpt',
        'report_timing_exception -file VinylFPGA_exception.timing',
        'report_qor -step route -file route.qor',
        'check_timing -verbose -file final.constraints',
        'flow_status -file route_flow.status',
        'export_db ' + quote(phy / 'VinylFPGA_pr.db'),
    ], phy)
    values = passing_qor(phy / 'route.qor')
    assert_inputs(build)
    bitgen_log = execute('bitgen', [
        'import_device eagle_s20.db -package EG4S20BG256',
        'import_db ' + quote(phy / 'VinylFPGA_pr.db'),
        'bitgen -bit ' + quote(phy / 'VinylFPGA.bit'),
        'setup_debugger',
        'export_bitgen_param -file ' + quote(phy / '.bitgen_param.f'),
    ], phy)
    assert_inputs(build)
    shutil.copyfile(gate_log, syn / 'run.log')
    with (phy / 'run.log').open('wb') as output:
        output.write(('Verified input round: ' + args.round + '\n'
                      'Operation: import verified databases, recalculate timing, generate bit.\n').encode('ascii'))
        for log in (place_log, route_log, bitgen_log):
            output.write(log.read_bytes())
    for src, dest in ((build / 'rtl.db', syn / 'VinylFPGA_rtl.db'),
                      (build / 'place.db', phy / 'VinylFPGA_place.db')):
        shutil.copyfile(src, dest)
    # Update best_result with the actual newly generated bit and timing status.
    best = runs / 'best_result'
    best.mkdir(exist_ok=True)
    for name in ('VinylFPGA.bit', 'VinylFPGA_phy.ts'):
        shutil.copyfile(phy / name, best / name)
    if (phy / 'VinylFPGA_inst.bid').is_file():
        shutil.copyfile(phy / 'VinylFPGA_inst.bid', best / 'VinylFPGA_inst.bid')
    manifest = {'verified_round': args.round, 'backup': str(backup),
                'input_hashes_verified': True, 'project_hash': digest(ROOT / 'prj/VinylFPGA.al'),
                'gate_database_sha256': digest(syn / 'VinylFPGA_gate.db'),
                'route_database_sha256': digest(phy / 'VinylFPGA_pr.db'),
                'final_timing_ps': values, 'bit': str(phy / 'VinylFPGA.bit'),
                'bit_sha256': digest(phy / 'VinylFPGA.bit'),
                'operation': 'import_actual_verified_databases_recompute_reports_generate_bit',
                'programmed': False}
    (phy / 'verified_release.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps(manifest, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()

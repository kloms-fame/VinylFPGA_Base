"""Compare S7-03 candidates against an immutable source snapshot, cycle by cycle.

The loader comparison includes EVERY output, including inactive payloads. Index
cover/audio payloads are compared when valid; their invalid-cycle differences
must not escape the loader. Existing functional scoreboards remain enabled.
"""
from pathlib import Path
import argparse
import json
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--baseline', default='S703_M0_20261006')
    parser.add_argument('--label', default='current')
    args = parser.parse_args()
    baseline = ROOT / 'prj/resource_opt_verified_20261005' / args.baseline
    out = ROOT / 'sim/resource_opt_verified' / ('s703_' + args.label)
    out.mkdir(parents=True, exist_ok=True)
    for module in ('song_index_db', 'fat32_media_loader'):
        source = (baseline / 'src/SD' / (module + '.v')).read_text(encoding='utf-8')
        source = source.replace('EXP_SONG_INDEX_DB_V', 'S703_REFERENCE_INDEX_V')
        for old in ('song_index_db', 'fat32_media_loader'):
            source = re.sub(r'\b' + old + r'\b', old + '_reference', source)
        (out / (module + '_reference.v')).write_text(source, encoding='utf-8')

    results = {}
    cases = [('tb_song_index_db', 'song_index_db'), ('tb_mv_index', 'song_index_db'),
             ('tb_fat32_index_loader', 'fat32_media_loader'),
             ('tb_s7_media_lifecycle', 'fat32_media_loader'),
             ('tb_fat32_media_loader', 'fat32_media_loader')]
    cases = [(bench, module, False) for bench, module in cases]
    cases.append(('tb_fat32_media_loader', 'fat32_media_loader', True))
    for bench, module, stalls in cases:
        case_name = bench + ('_stalls' if stalls else '')
        source = (ROOT / 'sim' / (bench + '.v')).read_text(encoding='utf-8')
        instance = re.search(r'\b' + module + r'\s+(?:#\(.*?\)\s*)?dut\s*\(.*?\n?\s*\);', source, re.S)
        assert instance, bench
        reference = instance[0].replace(module, module + '_reference', 1)
        reference = re.sub(r'\bdut\b', 'reference_dut', reference, count=1)
        header = (baseline / 'src/SD' / (module + '.v')).read_text(encoding='utf-8').split(');', 1)[0]
        ports = []
        for declaration in re.finditer(r'output\s+(?:reg|wire)\s*(?:\[[^\]]+\])?\s*([^\n]+)', header):
            ports.extend(re.findall(r'\b(song_mv\d|[a-zA-Z_]\w*)\b', declaration[1].split('//')[0].rstrip(', ')))
        for port in ports:
            reference = re.sub(r'\.' + port + r'\s*\([^)]*\)', '.' + port + '()', reference)
        checks = ['integer equivalence_cycles=0;', 'always @(negedge clk) begin',
                  '  equivalence_cycles=equivalence_cycles+1;']
        for port in ports:
            guard = 'dut.valid && ' if port.startswith(('song_cover', 'song_audio')) else ''
            checks.append(f'  if ({guard}(dut.{port} !== reference_dut.{port})) '
                          f'$fatal(1,"FAIL {bench} cycle equivalence {port} at %0t",$time);')
        if module == 'fat32_media_loader':
            checks.append('  if (dut.index_mode && !dut.idx_valid) $fatal(1,"FAIL invalid index consumed");')
        checks += ['end']
        source = source[:instance.end()] + '\n' + reference + '\n' + '\n'.join(checks) + source[instance.end():]
        source = re.sub(r'(defparam\s+dut\.[^;]+;)',
                        lambda m: m[0] + '\n' + m[0].replace('dut.', 'reference_dut.'), source)
        if stalls:
            source = source.replace('    always #5 clk = ~clk;',
                                    '    reg [2:0] gap=0; always @(posedge clk) gap<=gap+1;\n'
                                    '    always #5 clk = ~clk;')
            source = source.replace('end else if (reading) begin',
                                    "end else if (reading && gap==3'd0) begin")
        if bench == 'tb_song_index_db':
            # Warm success after rejection is essential: no reset hides stale data.
            source = source.replace('        if (errors == 0)', '''
        restore; feed(32'd25, 8'h00);
        check(valid && cov0 == {32'd822,32'd3}, "warm recovery");
        if (errors == 0)''')
            source = source.replace('                in_valid  = 1\'b1;', '''
                if ((i % 7) == 0) begin
                    in_valid = 0; repeat (3) @(negedge clk);
                end
                in_valid  = 1'b1;''')
        source = source.replace('$finish;', '$display("Compared %0d cycles",equivalence_cycles); $finish;')
        generated = out / (case_name + '.v')
        generated.write_text(source, encoding='utf-8')
        binary = out / (case_name + '.vvp')
        cmd = ['iverilog', '-g2005', '-I.', '-Isrc', '-Isrc/include', '-Isrc/SD', '-s', bench, '-o', str(binary)]
        for directory in [ROOT / 'src', *[d for d in (ROOT / 'src').iterdir() if d.is_dir() and d.name != 'IP']]:
            cmd += ['-y', str(directory)]
        cmd += [str(generated), str(out / 'song_index_db_reference.v')]
        if module == 'fat32_media_loader':
            cmd += [str(out / 'fat32_media_loader_reference.v')]
        c = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=90)
        log = c.stdout + c.stderr
        ok = False
        if c.returncode == 0:
            r = subprocess.run(['vvp', str(binary)], cwd=ROOT, capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=150)
            log += r.stdout + r.stderr
            ok = r.returncode == 0 and 'PASS' in log and 'FAIL' not in log and 'Compared ' in log
        (out / (case_name + '.log')).write_text(log, encoding='utf-8')
        results[case_name] = ok
        print(case_name, 'PASS' if ok else 'FAIL', '\n'.join(line for line in log.splitlines() if 'PASS' in line or 'Compared ' in line), flush=True)
        if not ok:
            print(log[-5000:], flush=True)
    (out / 'results.json').write_text(json.dumps(results, indent=2), encoding='utf-8')
    raise SystemExit(0 if all(results.values()) else 1)


if __name__ == '__main__':
    main()

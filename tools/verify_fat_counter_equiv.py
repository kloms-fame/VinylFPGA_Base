"""Compare all FAT streamer outputs against the stable Git RTL on boundaries."""
import argparse
import hashlib
import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASE = '9fbbf5be75353debca4be674e1684dd315a50dfe'

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    source = 'src/SD/fat32_file_streamer.v'
    bench = 'sim/tb_fat32_streamer_boundaries.v'
    baseline = subprocess.check_output(['git', 'show', BASE + ':' + source], cwd=ROOT)
    ref = output / 'fat32_file_streamer_ref.v'
    ref.write_text(baseline.decode('utf-8').replace('module fat32_file_streamer', 'module fat32_file_streamer_ref'), encoding='utf-8')
    checker = '''
    wire ref_busy,ref_done,ref_valid,ref_req;
    wire [7:0] ref_data,ref_error;
    wire [31:0] ref_offset,ref_lba;
    fat32_file_streamer_ref #(.MAX_VISITED_CLUSTERS(4)) reference(
      .clk(clk),.rst_n(rst_n),.file_start(start),.first_cluster(first),.file_size(size),
      .sectors_per_cluster(spc),.fat_start_lba(32'd10),.data_start_lba(32'd100),
      .max_cluster(maximum),.file_busy(ref_busy),.file_done(ref_done),.file_valid(ref_valid),
      .file_byte(ref_data),.file_byte_offset(ref_offset),.fs_error(ref_error),.sector_req(ref_req),
      .sector_lba(ref_lba),.sector_busy(reading),.sector_valid(svalid),.sector_byte(sbyte),
      .sector_byte_index(cursor[8:0]),.sector_done(sdone),.sector_error(serror));
    always @(negedge clk) if(rst_n)begin
      if({busy,done,fvalid,req,data,error,offset,lba} !==
         {ref_busy,ref_done,ref_valid,ref_req,ref_data,ref_error,ref_offset,ref_lba})
        $fatal(1,"FAT stable cycle equivalence mismatch case=%0d",case_id);
    end
'''
    text = (ROOT / bench).read_text(encoding='utf-8')
    text = text.replace('\nendmodule', checker + '\nendmodule')
    expanded = output / 'tb_equivalence.v'
    expanded.write_text(text, encoding='utf-8')
    compiled = subprocess.run(['iverilog', '-g2012', '-s', 'tb_fat32_streamer_boundaries',
                               '-o', str(output / 'test.vvp'), source, str(ref), str(expanded)],
                              cwd=ROOT, capture_output=True, text=True)
    log,code = compiled.stdout+compiled.stderr,compiled.returncode
    if code == 0:
        run = subprocess.run(['vvp', str(output / 'test.vvp')], cwd=ROOT, capture_output=True, text=True, timeout=60)
        code = run.returncode
        log += run.stdout + run.stderr
    passed = code == 0 and 'PASS' in log and not re.search(r'\b(?:FAIL|FATAL|ERROR)\b', log)
    (output / 'console.log').write_text(log, encoding='utf-8')
    result = {'passed': passed, 'reference_commit': BASE,
              'reference_source_sha256': hashlib.sha256(baseline).hexdigest(),
              'inputs_sha256': {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in (source, bench)},
              'log': log.strip()}
    (output / 'results.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(result, indent=2))
    return 0 if passed else 1

if __name__ == '__main__':
    raise SystemExit(main())

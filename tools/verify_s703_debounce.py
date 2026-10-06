"""Compare debounce outputs to M0 at real timing and parameter boundaries."""
from pathlib import Path
import argparse
import subprocess

ROOT = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser()
p.add_argument('--label', default='current')
a = p.parse_args()
out = ROOT/'sim/resource_opt_verified'/('debounce_'+a.label)
out.mkdir(parents=True, exist_ok=True)
base = ROOT/'prj/resource_opt_verified_20261005/S703_M0_20261006/src/io/debounce_filter.v'
ref = base.read_text(encoding='utf-8').replace('EXP_DEBOUNCE_FILTER_V', 'S703_REF_DEBOUNCE_V')
ref = ref.replace('module debounce_filter #', 'module debounce_filter_reference #')
(out/'reference.v').write_text(ref, encoding='utf-8')
cases = [(n, 1) for n in (0, 1, 2, 3, 8, 9, 400000, 524288, 524289, 1048576, 1048577, -1)]
cases.append((400000, 0))
lines = ['`timescale 1ns/1ps', 'module tb_debounce;',
         'reg clk=0,rst_n=0,async_in=0; always #5 clk=~clk;',
         "reg[31:0] noise=32'h674db813; integer cycles=0,i;"]
for j, (n, initial) in enumerate(cases):
    for module, suffix in [('debounce_filter', 'dut'), ('debounce_filter_reference', 'ref')]:
        lines += [f'wire [2:0] outputs_{suffix}_{j};',
                  f'{module} #(.DEBOUNCE_CYCLES({n}),.INITIAL_LEVEL(1\'b{initial})) {suffix}_{j}'
                  f'(.clk(clk),.rst_n(rst_n),.async_in(async_in),.level(outputs_{suffix}_{j}[2]),'
                  f'.fall_pulse(outputs_{suffix}_{j}[1]),.rise_pulse(outputs_{suffix}_{j}[0]));']
lines += ['always @(negedge clk) begin #1; cycles=cycles+1;']
for j, (n, initial) in enumerate(cases):
    lines += [f'if(outputs_dut_{j} !== outputs_ref_{j}) '
              f'$fatal(1,"FAIL N={n} initial={initial} cycle=%0d",cycles);']
lines += ['end', 'initial begin',
          'repeat(3) @(posedge clk);#1;rst_n=1;async_in=1;',
          'repeat(1048600) @(posedge clk);#1;async_in=0;',
          'repeat(1048600) @(posedge clk);#1;async_in=1;',
          # Abort just before the production threshold, then exercise bounce.
          'repeat(399998) @(posedge clk);#1;async_in=0;',
          'repeat(8) @(posedge clk);#1;',
          'for(i=0;i<10000;i=i+1)begin @(posedge clk);#1;',
          'noise={noise[30:0],noise[31]^noise[21]^noise[1]^noise[0]};async_in=noise[0];end',
          '@(posedge clk);#1;async_in=1;',
          'repeat(1048600) @(posedge clk);#1;async_in=0;',
          'repeat(12001) @(posedge clk);#1;rst_n=0;',
          'repeat(5) @(posedge clk);#1;rst_n=1;',
          'repeat(1048600) @(posedge clk);#1;',
          '$display("PASS debounce 13 parameter/initial cases, stable transitions, bounce, reset; cycles=%0d",cycles);',
          '$finish;end endmodule']
bench = out/'tb_debounce.v'
bench.write_text('\n'.join(lines), encoding='utf-8')
binary = out/'test.vvp'
c = subprocess.run(['iverilog', '-g2005', '-y', 'src/io', '-s', 'tb_debounce', '-o', str(binary),
                    str(bench), str(ROOT/'src/io/debounce_filter.v'), str(out/'reference.v')],
                   cwd=ROOT, capture_output=True, text=True, timeout=30)
assert c.returncode == 0, c.stderr
r = subprocess.run(['vvp', str(binary)], cwd=ROOT, capture_output=True, text=True, timeout=180)
log = c.stdout+c.stderr+r.stdout+r.stderr
(out/'result.log').write_text(log, encoding='utf-8')
print(log)
raise SystemExit(0 if r.returncode == 0 and 'PASS' in log and 'FAIL' not in log else 1)

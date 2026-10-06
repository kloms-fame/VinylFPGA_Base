"""Cycle-equivalence stress for event arbitration and all IR/DIP router inputs."""
from pathlib import Path
import argparse
import json
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser()
p.add_argument('--baseline', default='S703_M0_20261006')
p.add_argument('--label', default='current')
a = p.parse_args()
out = ROOT/'sim/resource_opt_verified'/('controls_'+a.label)
out.mkdir(parents=True, exist_ok=True)
results = {}
for module in ('ui_event_bus', 'ui_command_router', 'exp_echo_reporter'):
    baseline = ROOT/'prj/resource_opt_verified_20261005'/a.baseline/'src/io'/f'{module}.v'
    ref = baseline.read_text(encoding='utf-8')
    ref = ref.replace(module, module+'_reference').replace('EXP_UI_EVENT_BUS_V','S703_REF_EVENT_BUS_V').replace('EXP_UI_COMMAND_ROUTER_V','S703_REF_ROUTER_V')
    ref = ref.replace('EXP_EXP_ECHO_REPORTER_V', 'S703_REF_ECHO_V')
    (out/f'{module}_reference.v').write_text(ref, encoding='utf-8')
    source = baseline.read_text(encoding='utf-8').split(');',1)[0]
    ports = re.findall(r'\b(input|output)\s+(?:wire|reg)\s*(\[[^\]]+\])?\s*(\w+)',source)
    lines = ['`timescale 1ns/1ps', 'module tb_controls;', 'localparam KEY_COUNT=12,DIP_COUNT=6;',
             'integer i,j,cycles=0; reg[31:0] random_state=32\'h13579bdf;']
    ins = [name for direction,width,name in ports if direction=='input' and name not in ('clk','rst_n')]
    for direction,width,name in ports:
        if direction=='input':
            lines.append(f'reg {width} {name}=0;')
    lines.append('always #5 clk=~clk;')
    params = '#(.CLK_FREQ_HZ(1000),.BLANK_TIMEOUT_MS(20),.RESTART_CONFIRM_MS(15))' if module=='ui_command_router' else ''
    if module=='exp_echo_reporter':
        params='#(.CLK_FREQ_HZ(100),.BAUD_RATE(100))'
    for variant,inst in [(module,'dut'),(module+'_reference','reference_dut')]:
        lines.append(f'{variant} {params} {inst}('+','.join(f'.{n}({n if d=="input" else ""})' for d,w,n in ports)+');')
    lines += ['always @(negedge clk) begin #1; cycles=cycles+1;']
    for d,w,n in ports:
        if d=='output':
            lines.append(f'if(dut.{n} !== reference_dut.{n}) $fatal(1,"FAIL {module}.{n} cycle %0d",cycles);')
    lines += ['end','initial begin', 'repeat(3) @(posedge clk); #1; rst_n=1;']
    if module=='ui_command_router':
        # All 256 frame command bytes include the full whitelist and unknowns.
        # Each is also tried with a bad inverse and with DIP5 disabled.
        lines += ["dip_level=6'b010001;", 'for(i=0;i<256;i=i+1) begin',
                  "@(posedge clk);#1;ev_valid=1;ev_code=6;ev_arg=16'h00ff;ev_aux={i[7:0],~i[7:0]};",
                  '@(posedge clk);#1;ev_arg=0;', '@(posedge clk);#1;ev_arg=16\'h00ff;dip_level[4]=0;',
                  '@(posedge clk);#1;ev_valid=0;dip_level[4]=1;', 'end',
                  # Repeat after volume lead-in, early repeats, timeout, no lead-in.
                  "ev_valid=1;ev_code=6;ev_aux=16'hbb44;",
                  '@(posedge clk);#1;ev_code=7;', 'repeat(160) @(posedge clk);#1;ev_valid=0;',
                  'repeat(260) @(posedge clk);#1;ev_valid=1;ev_code=7;',
                  '@(posedge clk);#1;ev_valid=0;',
                  'for(i=0;i<64;i=i+1) begin', '@(posedge clk);#1;dip_level=i;',
                  'repeat(25) @(posedge clk);#1;ev_valid=1;ev_code=1;ev_arg=0;',
                  '@(posedge clk);#1;ev_valid=0;', 'end']
    elif module=='ui_event_bus':
        lines += ['for(i=0;i<12;i=i+1) begin',
                  '@(posedge clk);#1;key_fall_pulse=1<<i;key_rise_pulse=1<<((i+1)%12);dip_change_pulse=63;',
                  '@(posedge clk);#1;key_fall_pulse=0;key_rise_pulse=0;dip_change_pulse=0;',
                  'repeat(32) @(posedge clk);', 'end']
    else:
        lines += ['io_ready=1;exp_present=1;repeat(500)@(posedge clk);',
                  'for(i=0;i<256;i=i+1) begin',
                  '@(posedge clk);#1;ev_code=1;ev_arg=i;ev_valid=1;',
                  '@(posedge clk);#1;ev_valid=0;repeat(400)@(posedge clk);', 'end']
    lines += ['for(i=0;i<10000;i=i+1) begin', '@(posedge clk);#1;',
              "random_state={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};"]
    for j,name in enumerate(ins):
        lines.append(f'{name} = (random_state >> {j%17}) ^ (random_state << {j%13});')
    lines += ['end', '@(posedge clk);#1;']
    for name in ins:
        lines.append(f'{name}=0;')
    lines += ['repeat(300) @(posedge clk);', f'$display("PASS {module} all outputs, %0d cycles",cycles);$finish;', 'end', 'endmodule']
    bench=out/f'{module}_tb.v';bench.write_text('\n'.join(lines),encoding='utf-8')
    binary=out/f'{module}.vvp'
    c=subprocess.run(['iverilog','-g2005','-Isrc/include','-y','src/io','-s','tb_controls','-o',str(binary),str(bench),str(ROOT/'src/io'/f'{module}.v'),str(out/f'{module}_reference.v')],cwd=ROOT,capture_output=True,text=True,timeout=30)
    log=c.stdout+c.stderr;ok=False
    if c.returncode==0:
        r=subprocess.run(['vvp',str(binary)],cwd=ROOT,capture_output=True,text=True,timeout=30)
        log+=r.stdout+r.stderr;ok=r.returncode==0 and 'PASS' in log and 'FAIL' not in log
    (out/f'{module}.log').write_text(log,encoding='utf-8');results[module]=ok
    print(log[-3000:],flush=True)
(out/'results.json').write_text(json.dumps(results,indent=2),encoding='utf-8')
raise SystemExit(0 if all(results.values()) else 1)

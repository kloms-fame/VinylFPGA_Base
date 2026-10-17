"""Compare R5 timer narrowing cycle-by-cycle against immutable commit 6ffce23 RTL."""
from pathlib import Path
import argparse
import json
import shutil
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--out', type=Path, default=ROOT / 'sim/counter_r5_results')
parser.add_argument('--ir-only', action='store_true', help='run only the IR decoder equivalence matrix')
ARGS = parser.parse_args()
OUT = (ARGS.out if ARGS.out.is_absolute() else ROOT / ARGS.out).resolve()
if OUT.exists() and any(OUT.iterdir()):
    raise SystemExit(f'Refusing to overwrite existing test evidence: {OUT}')
IR_SIGNALS = ['event_valid', 'code', 'command', 'repeat_event', 'state', 'low_cnt', 'high_cnt', 'low_width', 'bit_count', 'shift_reg', 'frame_active', 'last_code', 'last_command', 'last_valid', 'event_next', 'repeat_next']
BUZZ_SIGNALS = ['buzzer_n', 'busy', 'current_event', 'dip_target_latched', 'dip_second_phase', 'half_period_cycles', 'duration_cycles', 'half_period_count', 'duration_count', 'key_d', 'dip_d', 'step_d', 'switch_d', 'ir_d']


def checks(signals):
    return '\n'.join(f'if (dut.{s} !== refdut.{s}) $fatal(1, "FAIL {s} cycle=%0d dut=%0h ref=%0h", cycles, dut.{s}, refdut.{s});' for s in signals)


def instances(module, params, inputs, outputs):
    pp = '#(' + ','.join(f'.{key}({value})' for key, value in params.items()) + ')' if params else ''
    ppins = ','.join(f'.{p}({p})' for p in inputs)
    opins = ','.join(f'.{p}()' for p in outputs)
    return f'{module} {pp} dut({ppins},{opins});\n{module}_r4 {pp} refdut({ppins},{opins});'


def ir_bench(freq):
    inst = instances('ir_nec_decoder', {'CLK_FREQ_HZ': freq}, ['clk', 'rst_n', 'ir_async'], ['event_valid', 'code', 'command', 'repeat_event'])
    return f'''`timescale 1ns/1ps
module tb;
reg clk=0, rst_n=0, ir_async=1;
always #5 clk=~clk;
integer cycles=0, events=0, repeats=0, i, k;
integer seed=32'h267bcde1, noise;
localparam integer F={freq}, ML=(F*11)/1000, MS=(F*6)/1000;
localparam integer LEAD=((F*7)/1000+ML)/2;
localparam integer SPACE=((F*3)/1000+MS)/2;
localparam integer REP=((F*15)/10000+(F*30)/10000)/2;
localparam integer BITLEN=((F*3)/10000+(F*10)/10000)/2;
localparam integer ONE=((F*10)/10000+(F*22)/10000)/2;
{inst}
always @(posedge clk) begin
  #1; cycles=cycles+1;
  {checks(IR_SIGNALS)}
  if(dut.event_valid) begin events=events+1; if(dut.repeat_event) repeats=repeats+1; end
end
task ticks; input integer n; begin repeat(n) @(negedge clk); end endtask
task level; input value; input integer n; begin ir_async=value; ticks(n); end endtask
task frame; input [31:0] value; integer b; begin
 level(0,LEAD+1); level(1,SPACE+1);
 for(b=0;b<32;b=b+1) begin level(0,BITLEN+1); level(1,(value[b]?ONE:BITLEN)+1); end
 level(0,BITLEN+1); level(1,MS+10);
end endtask
initial begin
 ticks(3); rst_n=1; ticks(10);
 if(F>=10000) begin
 frame(32'h20df10ef); frame(32'hf00faa55);
 level(0,LEAD+1); level(1,REP+1); level(0,BITLEN+1); level(1,MS+10);
 if(events!=3 || repeats!=1 || dut.code!==32'hf00faa55) $fatal(1,"FAIL valid/repeat coverage events=%0d repeats=%0d code=%h",events,repeats,dut.code);
 end
 // Long intervals exercise actual saturation and recovery, not forced state.
 level(0,ML+20); level(1,MS+20);
 level(0,LEAD+1); level(1,MS+20);
 // Invalid mark and invalid data space while a frame is active.
 level(0,LEAD+1); level(1,SPACE+1); level(0,BITLEN+1); level(1,MS-1); level(0,BITLEN+1); level(1,MS+20);
 // All inclusive threshold boundaries and +/-1, including power-of-two values.
 for(k=0;k<3;k=k+1) begin
   level(0,ML+k); level(1,MS+k); level(0,BITLEN+1); level(1,MS+10);
 end
 for(i=0;i<2000;i=i+1) begin
   noise=$random(seed); ir_async=noise&1;
   if((noise&63)==3) rst_n=0; else rst_n=1;
   ticks((noise&15)+1);
 end
 rst_n=1; level(1,MS+20);
 $display("PASS IR freq=%0d cycles=%0d events=%0d repeats=%0d widths=%0d/%0d",F,cycles,events,repeats,$bits(dut.low_cnt),$bits(dut.high_cnt));
 $finish;
end
endmodule
'''


def buzzer_bench(params, mode):
    inputs = ['clk', 'rst_n', 'sound_enable', 'key_press', 'dip_change', 'dip_target', 'encoder_step', 'encoder_direction', 'encoder_source', 'encoder_switch', 'encoder_switch_source', 'ir_event', 'ir_action']
    inst = instances('buzzer_feedback', params, inputs, ['buzzer_n', 'busy'])
    return f'''`timescale 1ns/1ps
module tb;
reg clk=0, rst_n=0, sound_enable=1;
reg key_press=0, dip_change=0, dip_target=0, encoder_step=0;
reg encoder_direction=0, encoder_source=0, encoder_switch=0, encoder_switch_source=0, ir_event=0;
reg [1:0] ir_action=0;
integer cycles=0, i, j, seed=32'h3cc157af, noise;
always #5 clk=~clk;
{inst}
always @(posedge clk) begin #1; cycles=cycles+1; {checks(BUZZ_SIGNALS)} end
task ticks; input integer n; begin repeat(n) @(negedge clk); end endtask
task clear_inputs; begin key_press=0; dip_change=0; encoder_step=0; encoder_switch=0; ir_event=0; end endtask
task reset_all; begin rst_n=0; clear_inputs; ticks(2); rst_n=1; sound_enable=1; ticks(2); end endtask
task event_start; input integer kind; begin
 clear_inputs; ticks(1);
 case(kind)
 1:encoder_step=1; 2:key_press=1; 3:dip_change=1; 4:ir_event=1; 5:encoder_switch=1;
 endcase
 ticks(1); clear_inputs;
end endtask
task near_end; begin
 // Equal deposits reach huge parameter endpoints; subsequent evolution is real RTL.
 if(dut.duration_cycles>2) begin
   dut.duration_count=dut.duration_cycles-2; refdut.duration_count=refdut.duration_cycles-2;
 end
 if(dut.half_period_cycles>2) begin
   dut.half_period_count=dut.half_period_cycles-2; refdut.half_period_count=refdut.half_period_cycles-2;
 end
 ticks(4);
end endtask
initial begin
 reset_all;
 // Every event, both encoder sources/directions, every IR action and DIP direction.
 for(i=1;i<=5;i=i+1) for(j=0;j<4;j=j+1) begin
   reset_all; encoder_source=j&1; encoder_direction=(j>>1)&1;
   encoder_switch_source=j&1; ir_action=j; dip_target=j&1;
   event_start(i);
   if(!dut.busy || dut.current_event!=i) $fatal(1,"FAIL event load i=%0d",i);
   ticks(3); near_end; if(i==3) near_end;
   if(dut.busy) $fatal(1,"FAIL event completion i=%0d",i);
 end
 // Every pair of priorities, including equal-priority requests and interruption.
 for(i=1;i<=5;i=i+1) for(j=1;j<=5;j=j+1) begin
   reset_all; event_start(i); event_start(j); near_end; near_end;
 end
 reset_all;
 key_press=1; dip_change=1; encoder_step=1; encoder_switch=1; ir_event=1; ticks(1);
 if(dut.current_event!=5) $fatal(1,"FAIL simultaneous priority");
 clear_inputs; ticks(1); sound_enable=0; ticks(1);
 if(dut.busy || !dut.buzzer_n) $fatal(1,"FAIL disable");
 // Held inputs during disable do not become phantom rising edges on enable.
 key_press=1; ticks(2); sound_enable=1; ticks(2); clear_inputs; ticks(2);
 if(dut.busy) $fatal(1,"FAIL held input");
 if({mode}==1) begin
   reset_all; event_start(2); ticks(1500002); if(dut.busy) $fatal(1,"FAIL full key duration");
   reset_all; event_start(3); ticks(2500004); if(dut.busy) $fatal(1,"FAIL full DIP duration");
 end
 if({mode}==2) begin
   for(i=1;i<=5;i=i+1) begin reset_all; event_start(i); ticks(600); if(dut.busy) $fatal(1,"FAIL full scaled duration"); end
 end
 for(i=0;i<20000;i=i+1) begin
   noise=$random(seed); rst_n=((noise&255)!=3); sound_enable=((noise&31)!=7);
   key_press=noise&1; dip_change=(noise>>1)&1; dip_target=(noise>>2)&1;
   encoder_step=(noise>>3)&1; encoder_direction=(noise>>4)&1; encoder_source=(noise>>5)&1;
   encoder_switch=(noise>>6)&1; encoder_switch_source=(noise>>7)&1;
   ir_event=(noise>>8)&1; ir_action=(noise>>9)&3; ticks(1);
 end
 $display("PASS BUZZ cycles=%0d widths=%0d/%0d",cycles,$bits(dut.half_period_count),$bits(dut.duration_count));
 $finish;
end
endmodule
'''


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    iverilog = shutil.which('iverilog') or 'D:/iverilog/bin/iverilog.exe'
    vvp = shutil.which('vvp') or 'D:/iverilog/bin/vvp.exe'
    durations = ['KEY_DURATION_CYCLES', 'DIP_TONE_DURATION_CYCLES', 'ENCODER_STEP_DURATION_CYCLES', 'ENCODER_SWITCH_DURATION_CYCLES', 'IR_DURATION_CYCLES']
    halves = ['KEY_HALF_PERIOD_CYCLES', 'DIP_LOW_HALF_PERIOD_CYCLES', 'DIP_HIGH_HALF_PERIOD_CYCLES', 'EC1_POS_HALF_PERIOD_CYCLES', 'EC1_NEG_HALF_PERIOD_CYCLES', 'EC2_POS_HALF_PERIOD_CYCLES', 'EC2_NEG_HALF_PERIOD_CYCLES', 'EC1_SWITCH_HALF_PERIOD_CYCLES', 'EC2_SWITCH_HALF_PERIOD_CYCLES']
    jobs = [(f'ir_{freq}', ir_bench(freq), 'ir_nec_decoder') for freq in (50_000_000, 123_457, 10_000, 23_273, 42_667, 1000, 1, 0)]
    if not ARGS.ir_only:
        jobs.append(('buzz_default', buzzer_bench({}, 1), 'buzzer_feedback'))
        for limit in (0, 1, 2, 8, 257, 65_536, -1):
            params = {p: limit for p in durations+halves}
            jobs.append((f'buzz_bound_{limit}', buzzer_bench(params, 2 if 0 <= limit <= 257 else 0), 'buzzer_feedback'))
        # Individually make each configurable load the maximum, so omissions cannot hide.
        for index, param in enumerate(halves + durations):
            params = {p: 7 for p in durations+halves}
            params[param] = 131_072
            jobs.append((f'buzz_max_{index}_{param.lower()}', buzzer_bench(params, 0), 'buzzer_feedback'))
        for alias in ('ENCODER_POS_HALF_PERIOD_CYCLES', 'ENCODER_NEG_HALF_PERIOD_CYCLES', 'ENCODER_SWITCH_HALF_PERIOD_CYCLES'):
            params = {p: 7 for p in durations}
            params[alias] = 131_072
            jobs.append(('buzz_alias_'+alias.lower(), buzzer_bench(params, 0), 'buzzer_feedback'))
    results = []
    for name, bench, module in jobs:
        source = OUT / (name + '.v'); binary = OUT / (name + '.vvp')
        source.write_text(bench, encoding='utf-8')
        start=time.monotonic()
        cp=subprocess.run([iverilog, '-g2012', '-s', 'tb', '-o', str(binary), str(source), str(ROOT/f'src/io/{module}.v'), str(ROOT/f'sim/legacy/{module}_r4.v'), str(ROOT/'src/io/sync_bit.v')],capture_output=True,text=True,timeout=60)
        if cp.returncode: raise RuntimeError(cp.stderr)
        run=subprocess.run([vvp,str(binary)],capture_output=True,text=True,timeout=180)
        log=cp.stderr+run.stdout+run.stderr
        (OUT/(name+'.log')).write_text(log,encoding='utf-8')
        if run.returncode or 'FAIL' in log or 'PASS' not in log: raise RuntimeError(name+'\n'+log)
        print(name+': '+log.strip(),flush=True)
        results.append({'test':name,'pass':True,'elapsed_s':round(time.monotonic()-start,3),'log':str(OUT/(name+'.log'))})
    (OUT/'results.json').write_text(json.dumps(results,indent=2),encoding='utf-8')
    print(f'PASS {len(results)}/{len(results)} timer equivalence cases',flush=True)

if __name__=='__main__': main()

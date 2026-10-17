"""Cycle-compare buzzer RTL against the frozen pre-timing-change parent."""
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
BASELINE = "4c9664ed1f9fa7249344f60fd147a70b3e07ea82"
IVERILOG = shutil.which("iverilog") or "D:/iverilog/bin/iverilog.exe"
VVP = shutil.which("vvp") or "D:/iverilog/bin/vvp.exe"
PARAMS = [
    "KEY_HALF_PERIOD_CYCLES", "KEY_DURATION_CYCLES",
    "DIP_LOW_HALF_PERIOD_CYCLES", "DIP_HIGH_HALF_PERIOD_CYCLES",
    "DIP_TONE_DURATION_CYCLES", "ENCODER_POS_HALF_PERIOD_CYCLES",
    "ENCODER_NEG_HALF_PERIOD_CYCLES", "ENCODER_SWITCH_HALF_PERIOD_CYCLES",
    "EC1_POS_HALF_PERIOD_CYCLES", "EC1_NEG_HALF_PERIOD_CYCLES",
    "EC2_POS_HALF_PERIOD_CYCLES", "EC2_NEG_HALF_PERIOD_CYCLES",
    "ENCODER_STEP_DURATION_CYCLES", "EC1_SWITCH_HALF_PERIOD_CYCLES",
    "EC2_SWITCH_HALF_PERIOD_CYCLES", "ENCODER_SWITCH_DURATION_CYCLES",
    "IR_DURATION_CYCLES",
]


def bench(params):
    overrides = "" if not params else "#(" + ",".join(
        f".{key}({value})" for key, value in params.items()) + ")"
    inputs = ("clk,rst_n,sound_enable,key_press,dip_change,dip_target,"
              "encoder_step,encoder_direction,encoder_source,encoder_switch,"
              "encoder_switch_source,ir_event,ir_action,slideshow_event")
    return f'''`timescale 1ns/1ps
module tb;
reg clk=0, rst_n=0, sound_enable=1;
reg key_press=0, dip_change=0, dip_target=0, encoder_step=0;
reg encoder_direction=0, encoder_source=0, encoder_switch=0, encoder_switch_source=0, ir_event=0, slideshow_event=0;
reg [1:0] ir_action=0;
integer cycles=0, i, j, seed=32'h3cc157af, noise;
wire buzzer_n, busy, ref_buzzer_n, ref_busy;
always #5 clk=~clk;
buzzer_feedback {overrides} dut({inputs},buzzer_n,busy);
buzzer_feedback_o3_gold {overrides} refdut({inputs},ref_buzzer_n,ref_busy);
always @(posedge clk) begin
 #1; cycles=cycles+1;
 if(buzzer_n!==ref_buzzer_n || busy!==ref_busy)
   $fatal(1,"FAIL output mismatch cycle=%0d buzzer=%b/%b busy=%b/%b",cycles,buzzer_n,ref_buzzer_n,busy,ref_busy);
end
task ticks; input integer n; begin repeat(n) @(negedge clk); end endtask
task clear_inputs; begin key_press=0; dip_change=0; encoder_step=0; encoder_switch=0; ir_event=0; slideshow_event=0; end endtask
task reset_all; begin rst_n=0; clear_inputs; ticks(2); rst_n=1; sound_enable=1; ticks(2); end endtask
task event_start; input integer kind; begin
 clear_inputs; ticks(1);
 case(kind)
 1:encoder_step=1; 2:key_press=1; 3:dip_change=1; 4:ir_event=1; 5:encoder_switch=1; 6:slideshow_event=1;
 endcase
 ticks(1); clear_inputs;
end endtask
task near_end; begin
 if(dut.duration_cycles>2) begin
   dut.duration_count=dut.duration_cycles-1; refdut.duration_count=refdut.duration_cycles-2;
 end
 if(dut.half_period_cycles>2) begin
   dut.half_period_count=dut.half_period_cycles-1; refdut.half_period_count=refdut.half_period_cycles-2;
 end
 ticks(4);
end endtask
initial begin
 reset_all;
 for(i=1;i<=6;i=i+1) for(j=0;j<4;j=j+1) begin
   reset_all; encoder_source=j&1; encoder_direction=(j>>1)&1;
   encoder_switch_source=j&1; ir_action=j; dip_target=j&1;
   event_start(i);
   if(!busy || dut.current_event!=i) $fatal(1,"FAIL event load i=%0d",i);
   ticks(3); near_end; if(i==3) near_end;
 end
 for(i=1;i<=6;i=i+1) for(j=1;j<=6;j=j+1) begin
   reset_all; event_start(i); event_start(j); near_end; near_end;
 end
 reset_all;
 key_press=1; dip_change=1; encoder_step=1; encoder_switch=1; ir_event=1; ticks(1);
 if(dut.current_event!=5) $fatal(1,"FAIL simultaneous priority");
 clear_inputs; ticks(1); sound_enable=0; ticks(1);
 if(busy || !buzzer_n) $fatal(1,"FAIL disable");
 key_press=1; ticks(2); sound_enable=1; ticks(2); clear_inputs; ticks(2);
 if(busy) $fatal(1,"FAIL held input");
 for(i=0;i<20000;i=i+1) begin
   noise=$random(seed); rst_n=((noise&255)!=3); sound_enable=((noise&31)!=7);
   key_press=noise&1; dip_change=(noise>>1)&1; dip_target=(noise>>2)&1;
   encoder_step=(noise>>3)&1; encoder_direction=(noise>>4)&1; encoder_source=(noise>>5)&1;
   encoder_switch=(noise>>6)&1; encoder_switch_source=(noise>>7)&1;
   ir_event=(noise>>8)&1; ir_action=(noise>>9)&3; slideshow_event=(noise>>11)&1; ticks(1);
 end
 if({int(not params)}) begin
   reset_all; encoder_switch=1; ticks(1); encoder_switch=0;
   ticks(3000002);
   if(busy || !buzzer_n) $fatal(1,"FAIL full encoder-switch duration");
 end
 if($bits(dut.half_period_count)>$bits(refdut.half_period_count) ||
    $bits(dut.duration_count)>$bits(refdut.duration_count))
   $fatal(1,"FAIL narrowed counters exceed frozen reference widths");
 $display("PASS O3 buzzer cycle equivalence cycles=%0d widths=%0d/%0d ref=%0d/%0d",
          cycles,$bits(dut.half_period_count),$bits(dut.duration_count),
          $bits(refdut.half_period_count),$bits(refdut.duration_count));
 $finish;
end
initial begin #100000000;$fatal(1,"timeout");end
endmodule
'''


def main():
    source = subprocess.run(["git", "show", f"{BASELINE}:src/io/buzzer_feedback.v"],
                            cwd=ROOT, check=True, capture_output=True, text=True).stdout
    source, count = re.subn(r"module\s+buzzer_feedback\s*#\(",
                            "module buzzer_feedback_o3_gold #( ", source, count=1)
    if count != 1:
        raise RuntimeError("Could not rename frozen baseline module")
    source = source.replace("EXP_BUZZER_FEEDBACK_V", "EXP_BUZZER_FEEDBACK_O3_GOLD_V")
    jobs = [("default", {})]
    for value in (0, 1, 2, 8, 257, -1):
        jobs.append((f"all_params_{value}", {name: value for name in PARAMS}))
    for name in PARAMS:
        jobs.append((f"param_{name.lower()}_max", {name: 131072}))

    with tempfile.TemporaryDirectory(prefix="vinyl_o3_buzzer_") as tmp:
        tmp = Path(tmp)
        golden = tmp / "buzzer_feedback_o3_gold.v"
        golden.write_text(source, encoding="utf-8")
        rtl = ROOT / "src/io/buzzer_feedback.v"
        for name, params in jobs:
            tb = tmp / f"{name}.v"
            exe = tmp / f"{name}.vvp"
            tb.write_text(bench(params), encoding="utf-8")
            comp = subprocess.run([IVERILOG, "-g2012", "-s", "tb", "-o", str(exe),
                                   str(tb), str(rtl), str(golden)], capture_output=True, text=True)
            if comp.returncode:
                raise RuntimeError(f"{name} compile failed:\n{comp.stderr}")
            sim = subprocess.run([VVP, str(exe)], capture_output=True, text=True, timeout=90)
            if sim.returncode or "PASS O3" not in sim.stdout:
                raise RuntimeError(f"{name} failed:\n{sim.stdout}\n{sim.stderr}")
            print(name + ": " + sim.stdout.strip(), flush=True)
    print(f"PASS {len(jobs)}/{len(jobs)} frozen-reference buzzer checks")


if __name__ == "__main__":
    main()

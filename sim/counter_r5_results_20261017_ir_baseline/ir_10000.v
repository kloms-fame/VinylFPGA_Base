`timescale 1ns/1ps
module tb;
reg clk=0, rst_n=0, ir_async=1;
always #5 clk=~clk;
integer cycles=0, events=0, repeats=0, i, k;
integer seed=32'h267bcde1, noise;
localparam integer F=10000, ML=(F*11)/1000, MS=(F*6)/1000;
localparam integer LEAD=((F*7)/1000+ML)/2;
localparam integer SPACE=((F*3)/1000+MS)/2;
localparam integer REP=((F*15)/10000+(F*30)/10000)/2;
localparam integer BITLEN=((F*3)/10000+(F*10)/10000)/2;
localparam integer ONE=((F*10)/10000+(F*22)/10000)/2;
ir_nec_decoder #(.CLK_FREQ_HZ(10000)) dut(.clk(clk),.rst_n(rst_n),.ir_async(ir_async),.event_valid(),.code(),.command(),.repeat_event());
ir_nec_decoder_r4 #(.CLK_FREQ_HZ(10000)) refdut(.clk(clk),.rst_n(rst_n),.ir_async(ir_async),.event_valid(),.code(),.command(),.repeat_event());
always @(posedge clk) begin
  #1; cycles=cycles+1;
  if (dut.event_valid !== refdut.event_valid) $fatal(1, "FAIL event_valid cycle=%0d dut=%0h ref=%0h", cycles, dut.event_valid, refdut.event_valid);
if (dut.code !== refdut.code) $fatal(1, "FAIL code cycle=%0d dut=%0h ref=%0h", cycles, dut.code, refdut.code);
if (dut.command !== refdut.command) $fatal(1, "FAIL command cycle=%0d dut=%0h ref=%0h", cycles, dut.command, refdut.command);
if (dut.repeat_event !== refdut.repeat_event) $fatal(1, "FAIL repeat_event cycle=%0d dut=%0h ref=%0h", cycles, dut.repeat_event, refdut.repeat_event);
if (dut.state !== refdut.state) $fatal(1, "FAIL state cycle=%0d dut=%0h ref=%0h", cycles, dut.state, refdut.state);
if (dut.low_cnt !== refdut.low_cnt) $fatal(1, "FAIL low_cnt cycle=%0d dut=%0h ref=%0h", cycles, dut.low_cnt, refdut.low_cnt);
if (dut.high_cnt !== refdut.high_cnt) $fatal(1, "FAIL high_cnt cycle=%0d dut=%0h ref=%0h", cycles, dut.high_cnt, refdut.high_cnt);
if (dut.low_width !== refdut.low_width) $fatal(1, "FAIL low_width cycle=%0d dut=%0h ref=%0h", cycles, dut.low_width, refdut.low_width);
if (dut.bit_count !== refdut.bit_count) $fatal(1, "FAIL bit_count cycle=%0d dut=%0h ref=%0h", cycles, dut.bit_count, refdut.bit_count);
if (dut.shift_reg !== refdut.shift_reg) $fatal(1, "FAIL shift_reg cycle=%0d dut=%0h ref=%0h", cycles, dut.shift_reg, refdut.shift_reg);
if (dut.frame_active !== refdut.frame_active) $fatal(1, "FAIL frame_active cycle=%0d dut=%0h ref=%0h", cycles, dut.frame_active, refdut.frame_active);
if (dut.last_code !== refdut.last_code) $fatal(1, "FAIL last_code cycle=%0d dut=%0h ref=%0h", cycles, dut.last_code, refdut.last_code);
if (dut.last_command !== refdut.last_command) $fatal(1, "FAIL last_command cycle=%0d dut=%0h ref=%0h", cycles, dut.last_command, refdut.last_command);
if (dut.last_valid !== refdut.last_valid) $fatal(1, "FAIL last_valid cycle=%0d dut=%0h ref=%0h", cycles, dut.last_valid, refdut.last_valid);
if (dut.event_next !== refdut.event_next) $fatal(1, "FAIL event_next cycle=%0d dut=%0h ref=%0h", cycles, dut.event_next, refdut.event_next);
if (dut.repeat_next !== refdut.repeat_next) $fatal(1, "FAIL repeat_next cycle=%0d dut=%0h ref=%0h", cycles, dut.repeat_next, refdut.repeat_next);
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

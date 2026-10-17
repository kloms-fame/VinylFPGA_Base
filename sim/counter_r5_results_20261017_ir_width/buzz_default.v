`timescale 1ns/1ps
module tb;
reg clk=0, rst_n=0, sound_enable=1;
reg key_press=0, dip_change=0, dip_target=0, encoder_step=0;
reg encoder_direction=0, encoder_source=0, encoder_switch=0, encoder_switch_source=0, ir_event=0;
reg [1:0] ir_action=0;
integer cycles=0, i, j, seed=32'h3cc157af, noise;
always #5 clk=~clk;
buzzer_feedback  dut(.clk(clk),.rst_n(rst_n),.sound_enable(sound_enable),.key_press(key_press),.dip_change(dip_change),.dip_target(dip_target),.encoder_step(encoder_step),.encoder_direction(encoder_direction),.encoder_source(encoder_source),.encoder_switch(encoder_switch),.encoder_switch_source(encoder_switch_source),.ir_event(ir_event),.ir_action(ir_action),.buzzer_n(),.busy());
buzzer_feedback_r4  refdut(.clk(clk),.rst_n(rst_n),.sound_enable(sound_enable),.key_press(key_press),.dip_change(dip_change),.dip_target(dip_target),.encoder_step(encoder_step),.encoder_direction(encoder_direction),.encoder_source(encoder_source),.encoder_switch(encoder_switch),.encoder_switch_source(encoder_switch_source),.ir_event(ir_event),.ir_action(ir_action),.buzzer_n(),.busy());
always @(posedge clk) begin #1; cycles=cycles+1; if (dut.buzzer_n !== refdut.buzzer_n) $fatal(1, "FAIL buzzer_n cycle=%0d dut=%0h ref=%0h", cycles, dut.buzzer_n, refdut.buzzer_n);
if (dut.busy !== refdut.busy) $fatal(1, "FAIL busy cycle=%0d dut=%0h ref=%0h", cycles, dut.busy, refdut.busy);
if (dut.current_event !== refdut.current_event) $fatal(1, "FAIL current_event cycle=%0d dut=%0h ref=%0h", cycles, dut.current_event, refdut.current_event);
if (dut.dip_target_latched !== refdut.dip_target_latched) $fatal(1, "FAIL dip_target_latched cycle=%0d dut=%0h ref=%0h", cycles, dut.dip_target_latched, refdut.dip_target_latched);
if (dut.dip_second_phase !== refdut.dip_second_phase) $fatal(1, "FAIL dip_second_phase cycle=%0d dut=%0h ref=%0h", cycles, dut.dip_second_phase, refdut.dip_second_phase);
if (dut.half_period_cycles !== refdut.half_period_cycles) $fatal(1, "FAIL half_period_cycles cycle=%0d dut=%0h ref=%0h", cycles, dut.half_period_cycles, refdut.half_period_cycles);
if (dut.duration_cycles !== refdut.duration_cycles) $fatal(1, "FAIL duration_cycles cycle=%0d dut=%0h ref=%0h", cycles, dut.duration_cycles, refdut.duration_cycles);
if (dut.half_period_count !== refdut.half_period_count) $fatal(1, "FAIL half_period_count cycle=%0d dut=%0h ref=%0h", cycles, dut.half_period_count, refdut.half_period_count);
if (dut.duration_count !== refdut.duration_count) $fatal(1, "FAIL duration_count cycle=%0d dut=%0h ref=%0h", cycles, dut.duration_count, refdut.duration_count);
if (dut.key_d !== refdut.key_d) $fatal(1, "FAIL key_d cycle=%0d dut=%0h ref=%0h", cycles, dut.key_d, refdut.key_d);
if (dut.dip_d !== refdut.dip_d) $fatal(1, "FAIL dip_d cycle=%0d dut=%0h ref=%0h", cycles, dut.dip_d, refdut.dip_d);
if (dut.step_d !== refdut.step_d) $fatal(1, "FAIL step_d cycle=%0d dut=%0h ref=%0h", cycles, dut.step_d, refdut.step_d);
if (dut.switch_d !== refdut.switch_d) $fatal(1, "FAIL switch_d cycle=%0d dut=%0h ref=%0h", cycles, dut.switch_d, refdut.switch_d);
if (dut.ir_d !== refdut.ir_d) $fatal(1, "FAIL ir_d cycle=%0d dut=%0h ref=%0h", cycles, dut.ir_d, refdut.ir_d); end
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
 if(1==1) begin
   reset_all; event_start(2); ticks(1500002); if(dut.busy) $fatal(1,"FAIL full key duration");
   reset_all; event_start(3); ticks(2500004); if(dut.busy) $fatal(1,"FAIL full DIP duration");
 end
 if(1==2) begin
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

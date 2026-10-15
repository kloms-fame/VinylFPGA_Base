`timescale 1ns/1ps
module tb_io_startup_dip;
reg clk=0, rst_n=0;
always #5 clk=~clk;
reg [5:0] dips=6'b000001;
reg event_enable=1'b1;
reg [11:0] key_fall=12'd0;
wire [5:0] levels, changes;
wire [2:0] idx;
wire valid; wire [3:0] code; wire [15:0] arg,aux;
integer count=0, seen=0, key_count=0, errors=0;
key_dip_monitor #(.KEY_COUNT(1),.DEBOUNCE_CYCLES(4)) mon
(.clk(clk),.rst_n(rst_n),.key_async(1'b1),.dip_async(dips),
 .dip_level(levels),.dip_change_pulse(changes),.dip_change_index(idx));
ui_event_bus bus (.clk(clk),.rst_n(rst_n),.ev_enable(event_enable),.key_fall_pulse(key_fall),.key_rise_pulse(12'd0),
 .dip_level(levels),.dip_change_pulse(changes),.dip_change_index(idx),
 .enc1_step_pulse(1'b0),.enc1_direction(1'b0),.enc1_count(16'd0),.enc1_sw_fall_pulse(1'b0),.enc1_sw_rise_pulse(1'b0),
 .enc2_step_pulse(1'b0),.enc2_direction(1'b0),.enc2_count(16'd0),.enc2_sw_fall_pulse(1'b0),.enc2_sw_rise_pulse(1'b0),
 .ir_event(1'b0),.ir_repeat_event(1'b0),.ir_code(32'd0),.ev_valid(valid),.ev_code(code),.ev_arg(arg),.ev_aux(aux));
always @(negedge clk) if(rst_n && valid && code==3) begin
 count=count+1; seen=seen | (1<<arg[2:0]);
 if(arg[3] !== levels[arg[2:0]]) $fatal(1,"FAIL DIP level/index mismatch");
end
always @(negedge clk) if(rst_n && valid && code==1) key_count=key_count+1;
initial begin
 repeat(4) @(negedge clk); rst_n=1;
 repeat(24) @(negedge clk);
 if(count!=0) begin $display("FAIL startup DIP is not an operator event"); errors=errors+1; end
 event_enable=1'b0; key_fall=12'b1;
 repeat(8) @(negedge clk);
 if(valid) begin $display("FAIL disabled event bus emitted an event early"); errors=errors+1; end
 event_enable=1'b1; key_fall=12'd0;
 repeat(4) @(negedge clk);
 if(key_count!=1) begin $display("FAIL held startup key event was not delivered count=%0d",key_count); errors=errors+1; end
 count=0;seen=0;dips=6'b000110;
 repeat(24) @(negedge clk);
 if(count!=3 || seen!=7) begin $display("FAIL simultaneous DIP changes count=%0d mask=%h",count,seen);errors=errors+1; end
 if(errors==0) $display("PASS startup event held until ready; DIP startup silent and simultaneous changes preserved");
 $finish;
end
endmodule

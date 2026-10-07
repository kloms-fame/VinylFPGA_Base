`timescale 1ns/1ps
module tb_health_monitor;
reg clk=0,rst=0,u=0,b=0,s=0,v=0,e=0,o=0;reg[7:0]code=0;
wire[7:0]error;wire[3:0]flags;
always #5 clk=~clk;
health_monitor dut(.clk(clk),.rst_n(rst),.underrun_pulse(u),.buffer_low(b),.stream_active(s),
.video_failed(v),.osd_err_valid(e),.osd_err_code(code),.ev_overflow(o),.err_code(error),.fault_flags(flags));
task tick; begin @(negedge clk);end endtask
initial begin
 tick;tick;rst=1;b=1;tick;if(flags!=0)$fatal(1,"FAIL idle low buffer");
 s=1;tick;if(flags!=0)$fatal(1,"FAIL startup low buffer");
 b=0;tick;b=1;tick;if(flags!=2)$fatal(1,"FAIL active low buffer edge");
 u=1;v=1;o=1;e=1;code=8'h34;tick;
 if(flags!=15 || error!=8'h34)$fatal(1,"FAIL injected faults");
 u=0;v=0;o=0;b=0;s=0;e=0;code=0;tick;
 if(flags!=15 || error!=8'h34)$fatal(1,"FAIL hold without valid");
 e=1;tick;if(flags!=15 || error!=0)$fatal(1,"FAIL current error clear");
 rst=0;tick;if(flags!=0 || error!=0)$fatal(1,"FAIL reset");
 $display("PASS health current error, independent sticky flags, recovery/reset");$finish;
end
endmodule

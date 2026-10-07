`timescale 1ns/1ps
module tb_x1x2_timebase;
reg clk=0,rst=0,tick=0,load=0,restart=0,running=0;
reg [31:0] target=0;
wire [31:0] count,ms; wire [5:0] sub;
always #20 clk=~clk;
timebase_48k dut(.clk(clk),.rst_n(rst),.sample_tick(tick),.running(running),
 .restart(restart),.load(load),.load_sample(target),.sample_count(count),.cur_time_ms(ms),.sub_sample(sub));
task check_load; input [31:0] n; begin
 @(negedge clk);target=n;load=1;@(negedge clk);load=0;
 repeat(40) @(negedge clk);
 if(ms!==n/48 || sub!==n%48 || count!==n) $fatal(1,"FAIL exact seek n=%0d ms=%0d rem=%0d",n,ms,sub);
end endtask
integer i;
initial begin
 repeat(3)@(negedge clk);rst=1;
 check_load(240000);check_load(96001);check_load(32'hffffffff);
 check_load(47999); running=1;tick=1;@(negedge clk);tick=0;
 if(ms!=1000 || sub!=0) $fatal(1,"FAIL millisecond carry");
 running=0;repeat(100)@(negedge clk);if(ms!=1000)$fatal(1,"FAIL pause");
 restart=1;@(negedge clk);restart=0;repeat(40)@(negedge clk);
 if(ms!=0 || count!=0)$fatal(1,"FAIL restart");
 $display("PASS exact seek timebase, remainder, pause and replay");$finish;
end
endmodule

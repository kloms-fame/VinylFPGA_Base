`timescale 1ns/1ps
module tb_s7_session;
 reg clk=0,rst=0,requested=0,restart=0,busy=0,video_busy=0,idle=0;
 wire enable,toggle;
 always #5 clk=~clk;
 stream_session dut(.clk(clk),.rst_n(rst),.requested(requested),.restart(restart),
 .storage_busy(busy),.video_busy(video_busy),.reader_idle(idle),.enable(enable),.start_toggle(toggle));
 task cycles;input integer n;repeat(n) @(negedge clk);endtask
 initial begin
 cycles(4);rst=1;requested=1;cycles(50);
 if(enable) $fatal(1,"FAIL start before read-side reset ack");
 idle=1;busy=1;cycles(50);if(enable) $fatal(1,"FAIL old SD transaction ignored");
 busy=0;video_busy=1;cycles(50);if(enable) $fatal(1,"FAIL old MV writer ignored");
 video_busy=0;cycles(40);if(!enable || !toggle) $fatal(1,"FAIL start after drain");
 restart=1;cycles(1);restart=0;busy=1;cycles(80);
 if(enable) $fatal(1,"FAIL fixed short mute instead of held restart");
 busy=0;cycles(40);if(!enable || toggle) $fatal(1,"FAIL second generation");
 $display("PASS session waits for SD, MV, read-domain reset acknowledgement");$finish;
 end
endmodule

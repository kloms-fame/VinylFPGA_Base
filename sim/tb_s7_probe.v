`timescale 1ns/1ps
module tb_s7_probe;
 reg clk=0,rst=0,ready=0,req=0,busy=0,valid=0,done=0;
 wire cb,cv,cd,cr;wire[31:0]lba;
 always #5 clk=~clk;
 media_probe #(.IDLE_CYCLES(16)) dut(.clk(clk),.rst_n(rst),.ready(ready),
 .client_req(req),.client_lba(32'd1234),.client_busy(cb),.client_valid(cv),.client_done(cd),
 .card_req(cr),.card_lba(lba),.card_busy(busy),.card_valid(valid),.card_done(done));
 task cycles;input integer n;repeat(n) @(negedge clk);endtask
 initial begin
 cycles(4);rst=1;cycles(25);if(cr) $fatal(1,"FAIL probing before mount");
 ready=1;wait(cr);@(negedge clk);
 if(lba!=0 || !cb) $fatal(1,"FAIL probe ownership/address");
 busy=1;valid=1;cycles(6);if(cv) $fatal(1,"FAIL probe bytes leaked into audio");
 valid=0;done=1;#1;if(cd) $fatal(1,"FAIL probe done leaked into audio");
 cycles(1);done=0;busy=0;req=1;#1;
 if(!cr || lba!=1234 || cb) $fatal(1,"FAIL client grant after probe");
 busy=1;cycles(1);req=0;valid=1;cycles(2);if(!cv) $fatal(1,"FAIL client data masked");
 valid=0;done=1;#1;if(!cd) $fatal(1,"FAIL client done masked");
 cycles(1);done=0;busy=0;
 $display("PASS idle probe isolation and client priority");$finish;
 end
 initial begin #10000;$fatal(1,"FAIL watchdog");end
endmodule

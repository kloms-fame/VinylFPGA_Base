`timescale 1ns/1ps
module tb_closure_triple_buffer;
 reg clk=0;always #20 clk=~clk;
 reg rst_n=0,en=0,fs=0,pause=0,restart=0,done=0,failed=0;
 reg [31:0] ms=0;reg [15:0] seek=0;
 wire req,dv,busy;wire [31:0] lba;wire [1:0] wb,db;wire [15:0] frame;
 reg seen=0;integer commands=0;
 mv_frame_scheduler dut(.clk(clk),.rst_n(rst_n),.frame_start(fs),.enable(en),.paused(pause),
  .restart(restart),.time_ms(ms),.start_lba(32'd1000),.frame_count(16'd6500),.seek_frame(seek),
  .done_toggle(done),.failed(failed),.retain_display(1'b1),.request_toggle(req),.request_lba(lba),
  .request_bank(wb),.display_valid(dv),.display_bank(db),.display_frame(frame),.waiting(busy));
 always @(negedge clk) if(rst_n && req!=seen)begin
  seen=req;commands=commands+1;
  if(wb==db || (dut.pending_valid && wb==dut.pending_bank))$fatal(1,"writer reused display/ready bank");
 end
 task boundary;
 begin @(negedge clk);fs=1;@(negedge clk);fs=0;repeat(5)@(negedge clk);end endtask
 task complete;
 input integer expected;
 begin
  wait(busy && req!=done);@(negedge clk);
  if(lba!=1000+expected*300)$fatal(1,"request frame mismatch %0d expected %0d",lba,expected);
  done=req;repeat(9)@(negedge clk);
 end endtask
 initial begin
  #45;rst_n=1;en=1;boundary;
  complete(0);boundary;if(!dv || frame!=0)$fatal(1,"first frame missing");
  complete(1);complete(2);
  // Both future frames must remain protected until their respective deadlines.
  repeat(30)@(negedge clk);
  if(commands!=3)$fatal(1,"read-ahead escaped three-bank capacity commands=%0d",commands);
  ms=100;repeat(8)@(negedge clk);boundary;
  if(frame!=1)$fatal(1,"future completion overwrote frame 1, displayed=%0d",frame);
  ms=200;repeat(8)@(negedge clk);boundary;
  if(frame!=2)$fatal(1,"third bank did not present frame 2");
  pause=1;complete(3);ms=300;boundary;if(frame!=2)$fatal(1,"pause moved display");
  pause=0;repeat(8)@(negedge clk);boundary;if(frame!=3)$fatal(1,"resume lost ready frame");
  seek=1234;ms=123400;restart=1;boundary;
  if(frame!=3)$fatal(1,"restart committed stale pending frame");
  @(negedge clk);restart=0;
  // Drain the outstanding old request before accepting the new seek command.
  if(busy && req!=done)begin done=req;repeat(10)@(negedge clk);end
  boundary;complete(1234);boundary;
  if(frame!=1234)$fatal(1,"seek did not publish requested target");
  $display("TEST_PASS closure_triple_buffer future frames bank protection pause restart seek");$finish;
 end
 initial begin #1000000;$fatal(1,"triple buffer timeout");end
endmodule

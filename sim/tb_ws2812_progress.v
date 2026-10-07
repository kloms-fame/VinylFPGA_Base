`timescale 1ns/1ps
module tb_ws2812_progress;
 reg src_clk=0,dst_clk=0,src_rst=0,dst_rst=0;
 reg [31:0] position=0,total=0;
 wire [3:0] progress;
 always #5 src_clk=~src_clk;
 always #13 dst_clk=~dst_clk;
 ws2812_progress dut(.src_clk(src_clk),.src_rst_n(src_rst),.position(position),.total(total),
                    .dst_clk(dst_clk),.dst_rst_n(dst_rst),.progress(progress));
 integer checks=0,i,j,seed=32'h31abce78;
 reg [31:0] random_total,random_position;
 task check;
  input [31:0] p,t;
  reg [63:0] scaled;
  integer expected;
  begin
   @(negedge src_clk);position=p;total=t;
   scaled={32'd0,p}*8;
   expected=t==0 ? 0 : (p>=t ? 8 : scaled/t);
   repeat(45)@(negedge dst_clk);
   if(progress!==expected[3:0])$fatal(1,"FAIL progress position=%0d total=%0d expected=%0d got=%0d",p,t,expected,progress);
   checks=checks+1;
  end
 endtask
 initial begin
  repeat(3)@(negedge src_clk);src_rst=1;dst_rst=1;
  check(0,0);check(32'hffffffff,0);
  for(i=1;i<=17;i=i+1)for(j=0;j<=i+1;j=j+1)check(j,i);
  for(i=0;i<=8;i=i+1)begin
   if(i>0)check(i*6000-1,48000);
   check(i*6000,48000);check(i*6000+1,48000);
  end
  check(32'h7fffffff,32'hffffffff);check(32'hfffffffe,32'hffffffff);
  check(32'hffffffff,32'hffffffff);check(0,32'hffffffff);
  for(i=0;i<200;i=i+1)begin
   random_total=$random(seed);random_position=$random(seed);check(random_position,random_total);
  end
  // Backward seek / replay work without any audio update event.
  check(47000,48000);check(12000,48000);check(0,48000);
  // Independent reset recovery must not deadlock the toggle handshake.
  @(negedge dst_clk);dst_rst=0;repeat(5)@(negedge dst_clk);dst_rst=1;check(24000,48000);
  @(negedge src_clk);src_rst=0;repeat(5)@(negedge src_clk);src_rst=1;check(36000,48000);
  $display("PASS exact progress division, boundaries, seek/replay, asynchronous clocks and resets: %0d cases",checks);$finish;
 end
 initial begin #1000000;$fatal(1,"FAIL progress watchdog");end
endmodule

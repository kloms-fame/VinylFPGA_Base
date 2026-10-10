`timescale 1ns/1ps
module tb_frame_read_ack_cdc;
 reg mem_clk=0,video_clk=0,video_rst_n=0,ack_mem=0;
 wire ack_video;
 integer edges_after_assert;
 always #5 mem_clk=~mem_clk;
 always #7 video_clk=~video_clk;
 sync_2ff dut(.clk(video_clk),.rst_n(video_rst_n),.async_in(ack_mem),.sync_out(ack_video));
 task ack_roundtrip;
  input integer phase_ns;
  integer edges;
  begin
   @(posedge mem_clk);#(phase_ns) ack_mem=1;
   edges=0;
   while(ack_video!==1 && edges<5) begin
    @(posedge video_clk);#1;edges=edges+1;
    if(edges<2 && ack_video!==0) $fatal(1,"FAIL ACK visible before two video clocks at phase=%0d",phase_ns);
   end
   if(edges<2 || ack_video!==1) $fatal(1,"FAIL ACK did not synchronize at phase=%0d edges=%0d",phase_ns,edges);
   @(posedge mem_clk);#(phase_ns) ack_mem=0;
   edges=0;
   while(ack_video!==0 && edges<5) begin @(posedge video_clk);#1;edges=edges+1;end
   if(ack_video!==0) $fatal(1,"FAIL ACK deassert did not synchronize at phase=%0d",phase_ns);
  end
 endtask
 initial begin
  repeat(4) @(posedge video_clk);
  @(negedge video_clk);video_rst_n=1;
  repeat(4) @(posedge video_clk);
  // Exercise multiple source-to-destination phase offsets at a 10:14 clock
  // period ratio; every ACK transition must cross two destination flops.
  ack_roundtrip(0);ack_roundtrip(2);ack_roundtrip(4);ack_roundtrip(6);
  @(posedge mem_clk);ack_mem=1;
  repeat(2) @(posedge video_clk);#1;
  if(ack_video!==1) $fatal(1,"FAIL ACK setup before video reset");
  // A video-domain reset must asynchronously clear the consumer-visible ACK.
  #2;video_rst_n=0;#1;
  if(ack_video!==0) $fatal(1,"FAIL video reset did not clear synchronized ACK");
  // Source ACK may remain asserted through destination reset; it must be
  // reacquired through the synchronizer after synchronous release.
  repeat(3) @(posedge video_clk);
  @(negedge video_clk);video_rst_n=1;
  @(posedge video_clk);#1;if(ack_video!==0) $fatal(1,"FAIL reset release bypassed ACK synchronizer");
  @(posedge video_clk);#1;if(ack_video!==1) $fatal(1,"FAIL ACK did not recover after video reset");
  @(negedge mem_clk);ack_mem=0;
  repeat(2) @(posedge video_clk);#1;
  if(ack_video!==0) $fatal(1,"FAIL ACK deassertion did not cross back to video domain");
  $display("PASS frame read ACK phase offset, two-cycle return and video-reset recovery");
  $finish;
 end
 initial begin #2000;$fatal(1,"FAIL watchdog");end
endmodule

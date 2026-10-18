`timescale 1ns/1ps
module tb_background_sector_mux;
 reg clk=0; always #5 clk=~clk;
 reg rst_n=0,a=0,v=0,b=0,av_allow=0,bg_allow=0,busy=0,valid=0,done=0;
 wire req,ab,vb,bb,av,vv,bv,ad,vd,bd,bg_grant;
 wire [31:0] lba;
 background_sector_mux dut(.clk(clk),.rst_n(rst_n),
  .audio_req(a),.audio_lba(32'd11),.audio_urgent(1'b1),.video_req(v),.video_lba(32'd22),
  .background_req(b),.background_lba(32'd33),.background_start(1'b1),
  .allow_video(av_allow),.allow_background(bg_allow),
  .audio_busy(ab),.video_busy(vb),.background_busy(bb),.background_grant(bg_grant),
  .audio_valid(av),.video_valid(vv),.background_valid(bv),
  .audio_done(ad),.video_done(vd),.background_done(bd),
  .sector_req(req),.sector_lba(lba),.sector_busy(busy),.sector_valid(valid),.sector_done(done));
 task complete_sector;
 begin
  @(negedge clk); done=1;
  @(negedge clk); done=0;valid=0;busy=0;
 end endtask
 initial begin
  #22 rst_n=1; @(negedge clk); a=1;v=1;b=1;av_allow=1;bg_allow=1;
  @(posedge clk); #1;
  if(!req || lba!=11) $fatal(1,"audio must win triple request");
  @(negedge clk); a=0;
  @(posedge clk); #1 busy=1;valid=1; #1;
  if(!av||vv||bv||bg_grant) $fatal(1,"audio byte owner");
  complete_sector;
  @(posedge clk); #1; if(!req||lba!=22) $fatal(1,"MV precedes background");
  @(negedge clk); v=0;
  @(posedge clk); #1 busy=1;valid=1; #1;
  if(av||!vv||bv||bg_grant) $fatal(1,"video byte owner");
  complete_sector;
  @(posedge clk); #1; if(!req||lba!=33) $fatal(1,"background idle grant");
  @(posedge clk); #1 busy=1;valid=1;a=1;v=1;bg_allow=0; #1;
  if(av||vv||!bv||!bg_grant||!ab) $fatal(1,"in-flight background must not be preempted");
  complete_sector;
  @(posedge clk); #1; if(!req||lba!=11) $fatal(1,"audio resumes next sector");
  @(negedge clk); a=0;v=0;
  @(posedge clk); #1 busy=1;
  complete_sector;
  repeat(4) @(negedge clk); if(req||!bb) $fatal(1,"background watermark denial");
  $display("TEST_PASS background_sector_mux audio MV background priority ownership watermark"); $finish;
 end
 initial begin #10000; $fatal(1,"timeout"); end
endmodule

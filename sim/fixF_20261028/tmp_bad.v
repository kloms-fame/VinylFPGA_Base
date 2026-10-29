`timescale 1ns/1ps
// A background request waits behind audio; MV starts before audio releases.
// The background must wait until the complete MV write has retired.
module tb_background_mv_admission;
 reg clk=0,rst_n=0,audio_req=1,bg_req=1,mv_active=0,sector_busy=0,sector_done=0;
 wire grant,sector_req;
 always #5 clk=~clk;
 background_sector_mux dut(.clk(clk),.rst_n(rst_n),.audio_req(audio_req),.audio_lba(32'd1),
  .audio_urgent(1'b1),.video_req(1'b0),.video_lba(32'd0),
  .background_req(bg_req),.background_lba(32'd2),.background_start(1'b1),
  .allow_video(1'b0),
`ifdef LEGACY_ALLOW
  .allow_background(1'b1),
`else
  .allow_background(!mv_active),
`endif
  .audio_busy(),.video_busy(),.background_busy(),.background_grant(grant),
  .audio_valid(),.video_valid(),.background_valid(),.audio_done(),.video_done(),.background_done(),
  .sector_req(sector_req),.sector_lba(),.sector_busy(sector_busy),.sector_valid(1'b0),.sector_done(sector_done));
 initial begin
  repeat(2) @(negedge clk);rst_n=1;wait(sector_req);
  @(negedge clk);sector_busy=1;mv_active=1;audio_req=0;
  repeat(3) @(negedge clk);sector_done=1;sector_busy=0;
  @(negedge clk);sector_done=0;
  repeat(10) begin @(negedge clk);if(grant) $fatal(1,"background acquired while MV writer active");end
  mv_active=0;repeat(5) @(negedge clk);
  if(!grant) $fatal(1,"background not granted after MV retired owner=%b issued=%b audio=%b sector_req=%b",dut.owner_valid,dut.issued,audio_req,sector_req); //");
  $display("PASS background waits for MV writer");$finish;
 end
 initial begin repeat(1000) @(posedge clk);$fatal(1,"timeout");end
endmodule


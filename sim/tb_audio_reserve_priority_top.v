`timescale 1ns/1ps
// Exercise CMD17 audio priority and the current CMD18 MV reserve gate.
// SD owner arbitration and packet buffering have separate transaction benches.
module tb_audio_reserve_priority_top;
 reg clk=0;always #5 clk=~clk;
 reg low=0,critical=0,audio_req=1,video_req=1,playing=1;
 reg [1:0] fifo_levels=0;
 top dut(.clk(clk),.rst_n(1'b0),.key2(1'b1),.key3(1'b1),.key4(1'b1),
  .sw1(1'b1),.sw2(1'b1),.sw3(1'b0),.sw4(1'b1),.needle_sense_n(1'b1),
  .sd_miso(1'b1),.flash_miso(1'b1),.exp_key_n(12'hfff),.exp_dip_n(6'h37),
  .exp_enc1_a(1'b1),.exp_enc1_b(1'b1),.exp_enc1_sw_n(1'b1),
  .exp_enc2_a(1'b1),.exp_enc2_b(1'b1),.exp_enc2_sw_n(1'b1),.exp_ir_rx(1'b1));
 initial begin
  force dut.prefetch_sd_req=audio_req;
  force dut.mv_sec_req=video_req;
  force dut.cache_prefetch_low=low;
  force dut.cache_prefetch_critical=critical;
  force dut.audio_play_enable_gated=playing;
  force dut.mv_audio_low_sync=fifo_levels;
  force dut.media_sec_busy=1'b0;
  force dut.u_mv_sector_mux.owner_valid=1'b0;
  #1;
  if(!dut.u_mv_sector_mux.take_audio || dut.prefetch_sd_busy)
   $fatal(1,"CMD17 refill must be admitted even above LOW watermark");
  if(dut.u_mv_sector_mux.video_req || dut.u_mv_sector_mux.allow_video)
   $fatal(1,"MV must use the CMD18 owner, not the legacy CMD17 video input");
  audio_req=0;low=1;#1;
  if(dut.mv_cmd18_allowed)
   $fatal(1,"MV admitted with less than the stable five-second PCM reserve");
  low=0;#1;
  if(!dut.mv_cmd18_allowed)
   $fatal(1,"healthy cache did not release idle SD service to MV");
  fifo_levels=2'b11;#1;
  if(dut.mv_cmd18_allowed)$fatal(1,"output FIFO urgency lost");
  playing=0;#1;
  if(!dut.mv_cmd18_allowed)$fatal(1,"idle playback blocks MV");
  $display("TEST_PASS audio_reserve_priority_top CMD17 refill admission and CMD18 five-second guard");$finish;
 end
endmodule

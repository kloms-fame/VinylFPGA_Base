`timescale 1ns/1ps
// Real top selection -> media-loader metadata pipeline -> session enable.
// Only vendor clocks, scanned index entries and high-level controls are forced.
module tb_opt_metadata;
 reg clk=0,rst=0,playing=0,grid=0,requested=0,restart=0,index_done=0;
 reg [1:0] focus=0,selected=0,bank=0;
 integer i;
 always #5 clk=~clk;
 top dut(.clk(clk),.rst_n(rst),.key3(1'b1),
 .sw1(1'b1),.sw2(1'b1),.sw3(1'b0),.sw4(1'b1),.sd_miso(1'b1),
 .exp_key_n(12'hfff),.exp_dip_n(6'h37),
 .exp_enc1_a(1'b1),.exp_enc1_b(1'b1),.exp_enc1_sw_n(1'b1),
 .exp_enc2_a(1'b1),.exp_enc2_b(1'b1),.exp_enc2_sw_n(1'b1),.exp_ir_rx(1'b1));
 task tick; begin @(posedge clk); #1; end endtask
 task check_meta;
  input [1:0] song;
  integer timeout;
  begin
   timeout=0;
   while(dut.mv_metadata_video!==(64'h100000000+song) && timeout<128) begin tick();timeout=timeout+1;end
   if(dut.audio_file_valid!==1'b1 || dut.audio_start_lba!==(32'd1000+song*32'd80) ||
      dut.audio_size_bytes!==(32'd512*(song+1)) || dut.audio_total_sectors!==(song+1))
    $fatal(1,"FAIL song=%0d lba=%0d bytes=%0d sectors=%0d",song,dut.audio_start_lba,dut.audio_size_bytes,dut.audio_total_sectors);
   if(dut.mv_metadata_sd!==(64'h100000000+song)) $fatal(1,"FAIL MV song mismatch");
   if(dut.mv_metadata_video!==(64'h100000000+song)) $fatal(1,"FAIL MV metadata CDC did not settle source=%h video=%h song=%0d",dut.mv_metadata_sd,dut.mv_metadata_video,song);
  end
 endtask
 initial begin
  force dut.sd_card_clk=clk; force dut.ext_mem_clk=clk;force dut.video_clk=clk;
  force dut.sdcard_rst_n=rst;force dut.sd_media_rst_n=rst;
  force dut.mem_rst_n=rst;force dut.video_rst_n=rst;force dut.exp_rst_n=rst;
  force dut.play_active_sd=playing;force dut.play_sel_song_sd=selected;
  force dut.thumb_mode_sd=grid;force dut.thumb_focus_index_sd=focus;force dut.disp_buf_idx=bank;
  force dut.u_stream_session.requested=requested;force dut.u_stream_session.restart=restart;
  force dut.u_stream_session.storage_busy=1'b0;force dut.u_stream_session.video_busy=1'b0;
  force dut.u_stream_session.reader_idle=1'b1;
  force dut.sd_card_bmp_m0.fat32_media_loader_m0.scan_start=1'b0;
  force dut.sd_card_bmp_m0.fat32_media_loader_m0.scanner_done=1'b0;
  force dut.sd_card_bmp_m0.fat32_media_loader_m0.index_mode=1'b1;
  force dut.sd_card_bmp_m0.fat32_media_loader_m0.idx_valid=1'b1;
  force dut.sd_card_bmp_m0.fat32_media_loader_m0.idx_done=index_done;
  force dut.sd_card_bmp_m0.fat32_media_loader_m0.scanner_spc=8'd8;
  force dut.sd_card_bmp_m0.fat32_media_loader_m0.scanner_data_start=32'd1000;
  force dut.sd_card_bmp_m0.fat32_media_loader_m0.idx_audio0={32'd512,32'd2};
  force dut.sd_card_bmp_m0.fat32_media_loader_m0.idx_audio1={32'd1024,32'd12};
  force dut.sd_card_bmp_m0.fat32_media_loader_m0.idx_audio2={32'd1536,32'd22};
  force dut.sd_card_bmp_m0.fat32_media_loader_m0.idx_audio3={32'd2048,32'd32};
  force dut.sd_card_bmp_m0.fat32_media_loader_m0.idx_mv0=64'h100000000;
  force dut.sd_card_bmp_m0.fat32_media_loader_m0.idx_mv1=64'h100000001;
  force dut.sd_card_bmp_m0.fat32_media_loader_m0.idx_mv2=64'h100000002;
  force dut.sd_card_bmp_m0.fat32_media_loader_m0.idx_mv3=64'h100000003;
  repeat(3) tick(); @(negedge clk);rst=1;index_done=1;tick();
  @(negedge clk);index_done=0;repeat(8)tick();check_meta(0);
  // Rapid focus changes and immediate confirmation must settle to the chosen song.
  for(i=0;i<4;i=i+1) begin
   @(negedge clk);playing=0;grid=1;requested=0;focus=(i+1)%4;tick();
   @(negedge clk);focus=(i+2)%4;tick();
   @(negedge clk);focus=i;selected=i;playing=1;requested=1;restart=1;tick();
   if(dut.stream_enable_sd) $fatal(1,"FAIL restart did not stop generation");
   @(negedge clk);restart=0;repeat(10)tick();check_meta(i);
   if(dut.stream_enable_sd) $fatal(1,"FAIL metadata settle window bypassed");
   repeat(32)tick();if(!dut.stream_enable_sd)$fatal(1,"FAIL generation never started");check_meta(i);
  end
  // Stop/home switches to displayed bank, and cancels the running generation.
  @(negedge clk);requested=0;playing=0;grid=0;bank=2;tick();
  if(dut.stream_enable_sd)$fatal(1,"FAIL stop not immediate");repeat(10)tick();check_meta(2);
  // The physical mem-domain ACK must pass through the top-level synchronizer
  // before either video-domain consumer sees it.
  force dut.video_read_req_ack_mem=1'b0;repeat(5)tick();
  if(dut.video_read_req_ack!==1'b0)$fatal(1,"FAIL synchronized read ACK did not clear");
  force dut.video_read_req_ack_mem=1'b1;tick();
  if(dut.video_read_req_ack!==1'b0)$fatal(1,"FAIL read ACK bypassed first synchronizer stage");
  tick();if(dut.video_read_req_ack!==1'b1)$fatal(1,"FAIL read ACK missing after two video clocks");
  release dut.video_read_req_ack_mem;
  @(negedge clk);rst=0;#1;
  if(dut.metadata_song_sd!==0 || dut.stream_enable_sd!==0 || dut.mv_metadata_video!==0 || dut.play_volume_video!==0)$fatal(1,"FAIL reset");
  $display("PASS four-song WAV/MV metadata, rapid focus/confirm, session settle, stop and reset");$finish;
 end
 initial begin #100000;$fatal(1,"FAIL watchdog");end
endmodule

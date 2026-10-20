`timescale 1ns/1ps
// Exercise the actual production admission wiring with controlled idle SD IP.
module tb_final_audio_prefill_cadence;
 reg clk=0;always #5 clk=~clk;
 top dut(.clk(clk),.rst_n(1'b0),.key2(1'b1),.key3(1'b1),.key4(1'b1),
  .sw1(1'b1),.sw2(1'b1),.sw3(1'b0),.sw4(1'b1),.needle_sense_n(1'b1),
  .sd_miso(1'b1),.flash_miso(1'b1),.exp_key_n(12'hfff),.exp_dip_n(6'h37),
  .exp_enc1_a(1'b1),.exp_enc1_b(1'b1),.exp_enc1_sw_n(1'b1),
  .exp_enc2_a(1'b1),.exp_enc2_b(1'b1),.exp_enc2_sw_n(1'b1),.exp_ir_rx(1'b1));
 reg vclk=0;always #20 vclk=~vclk;
 reg run_reset=0,playing_now=0; reg [1:0] stream_state=0;
 reg cache_ready=0,response_busy=1,response_valid=0,response_done=0;
 reg [7:0] response_byte=8'h12;
 integer samples=0,acrs=0,phase=0,byte_index,sector;
 always @(posedge vclk) begin
  if (dut.audio_valid) begin
   samples=samples+1;
   if(phase==0 && (dut.audio_left_data!==24'd0 || dut.audio_right_data!==24'd0))
    $fatal(1,"prefill/browse output must be silent");
   if(phase==2 && (dut.audio_left_data!==24'h0e0f00 || dut.audio_right_data!==24'h0e0f00))
    $fatal(1,"resumed WAV data mismatch: %h/%h",dut.audio_left_data,dut.audio_right_data);
  end
  if (dut.acr_valid) acrs=acrs+1;
 end
 initial begin
  force dut.video_clk=vclk;
  force dut.sd_card_clk=clk;
  force dut.ext_mem_clk=clk;
  force dut.video_rst_n=run_reset;
  force dut.media_video_rst_n=run_reset;
  force dut.sdcard_rst_n=run_reset;
  force dut.sd_media_rst_n=run_reset;
  force dut.mem_rst_n=run_reset;
  force dut.boot_active=1'b0;
  force dut.play_active_v2=playing_now;
  force dut.paused_v2=1'b0;
  force dut.stream_enable_vid=stream_state;
  force dut.audio_play_enable_gated=playing_now;
  force dut.wav_start_lba_eff=32'd100;
  force dut.wav_total_sectors_eff=32'd2;
  force dut.wav_valid_samples=32'd512;
  force dut.wav_skip_samples=8'd0;
  force dut.play_seek_target_v2=32'd0;
  force dut.wav_sec_busy=response_busy;
  force dut.wav_sec_valid=response_valid;
  force dut.wav_sec_byte=response_byte;
  force dut.wav_sec_done=response_done;
  force dut.wav_sec_error=8'd0;
  force dut.cache_playback_ready_video=cache_ready;
  force dut.wav_fade_gain=8'd255;
  force dut.play_volume_video=8'd200;
  force dut.board_audio_mute_v2=1'b0;
  force dut.media_id=2'd0;
  #100;run_reset=1;
  #2000000;
  $display("IDLE 2ms audio_valid=%0d acr_valid=%0d",samples,acrs);
  if(samples<95 || samples>97 || acrs<1 || acrs>3) $fatal(1,"idle cadence setup invalid");
  playing_now=1;stream_state=3;
  #1000;samples=0;acrs=0;
  #2000000;
  $display("PREFILL 2ms audio_valid=%0d acr_valid=%0d wav_active=%b startup_ready=%b audio_silent=%b",samples,acrs,dut.wav_stream_active,dut.wav_startup_ready,dut.audio_silent);
  if(samples<95 || samples>97 || acrs<1 || acrs>3) $fatal(1,"prefill must retain 48k silent PCM/ACR cadence");
  if(dut.wav_sample_counter!==0) $fatal(1,"prefill consumed WAV samples");
  // A ready cache alone cannot start an empty decoder FIFO.
  cache_ready=1;#1000;
  if(!dut.audio_silent) $fatal(1,"empty decoder FIFO must retain silent cadence");
  phase=1;
  for(sector=0;sector<2;sector=sector+1) begin
   wait(dut.wav_sec_req);
   @(negedge clk);response_busy=0;
   @(negedge clk);response_busy=1;
   for(byte_index=0;byte_index<512;byte_index=byte_index+1) begin
    response_valid=1;@(negedge clk);
   end
   response_valid=0;response_done=1;@(negedge clk);response_done=0;
  end
  #100000;
  if(!dut.wav_startup_ready || dut.audio_silent || dut.wav_sample_counter==0)
   $fatal(1,"WAV failed to resume when both buffers became ready");
  phase=2;samples=0;acrs=0;
  #2000000;
  if(samples<95 || samples>97 || acrs<1 || acrs>3 || dut.wav_sample_counter<95)
   $fatal(1,"resumed WAV cadence/data consumption: samples=%0d acr=%0d position=%0d",samples,acrs,dut.wav_sample_counter);
  $display("PASS final actual-top silent prefill and resumed WAV data/cadence");
  $finish;
 end
 initial begin #10000000;$fatal(1,"prefill/resume watchdog");end
endmodule

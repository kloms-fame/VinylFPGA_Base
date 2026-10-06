`timescale 1ns/1ps
// Control integration only. Real UI bridge/browse/play/navigation/supervisor;
// vendor clocks, storage data and HDMI datapath are controlled boundaries.
module tb_s7_top;
 reg clk=0,sdclk=0,pix=0,rst=0,vs=1;
 reg event_valid=0;reg[3:0]event_code=1;reg[15:0]event_arg=0,event_aux=0;
 reg[7:0]error=0;reg[23:0]status=24'hFF0000;
 reg sector_done=0;reg[7:0]sector_error=0;reg eof=0;
 integer f=0,i;
 always #10 clk=~clk;always #5 sdclk=~sdclk;always #20 pix=~pix;
 always @(negedge pix) begin f=f+1;vs=(f%30!=0);end
 top #(.BUZZER_FEEDBACK_ENABLE(0),.ECHO_TEST_ENABLE(0),.S2_BOOT_ENABLE(0)) dut
 (.clk(clk),.rst_n(rst),.key1(1'b1),.key2(1'b1),.key3(1'b1),
 .sw1(1'b1),.sw2(1'b1),.sw3(1'b1),.sw4(1'b1),.sd_miso(1'b1),
 .exp_key_n(12'hfff),.exp_dip_n(6'h11),.exp_enc1_a(1'b1),.exp_enc1_b(1'b1),.exp_enc1_sw_n(1'b1),
 .exp_enc2_a(1'b1),.exp_enc2_b(1'b1),.exp_enc2_sw_n(1'b1),.exp_ir_rx(1'b1));
 defparam dut.u_media_supervisor.CLK_FREQ_HZ=2000;
 defparam dut.u_media_supervisor.MOUNT_TIMEOUT_MS=100;
 defparam dut.u_media_supervisor.REMOUNT_COOLDOWN_MS=20;
 defparam dut.u_media_supervisor.RESET_PULSE_CYCLES=20;
 task cycles;input integer n;repeat(n) @(negedge clk);endtask
 task key;input[15:0]k;begin
  @(negedge clk);event_valid=1;event_code=1;event_arg=k;
  @(negedge clk);event_valid=0;cycles(10);
 end endtask
 task settled;begin cycles(1500);if(dut.cover_busy || dut.fade_busy) $fatal(1,"FAIL transition stuck");end endtask
 initial begin
 force dut.sd_card_clk=sdclk;force dut.ext_mem_clk=sdclk;force dut.video_clk=pix;
 force dut.sdcard_rst_n=rst;force dut.mem_rst_n=rst;force dut.video_rst_n=rst;force dut.exp_rst_n=rst;
 force dut.vs=vs;
 force dut.ui_event_valid=event_valid;force dut.ui_event_code=event_code;
 force dut.ui_event_arg=event_arg;force dut.ui_event_aux=event_aux;
 force dut.osd_error_code=error;force dut.media_status_sd=status;
 force dut.storage_done=sector_done;force dut.storage_error=sector_error;
 force dut.sd_card_bmp_m0.sd_init_done=1'b1;force dut.sd_card_bmp_m0.scan_done=1'b1;
 force dut.sd_card_bmp_m0.scan_kicked=1'b1;force dut.sd_card_bmp_m0.img_found_count=3'd4;
 force dut.sd_card_bmp_m0.image_ready=4'hf;force dut.sd_card_bmp_m0.preload_idx=3'd4;
 force dut.sd_card_bmp_m0.display_valid=1'b1;force dut.sd_card_bmp_m0.load_busy=1'b0;
 force dut.audio_play_enable=1'b1;force dut.wav_sec_busy=1'b0;force dut.mv_writer_active=1'b0;
 force dut.wav_stream_end=eof;
 cycles(8);rst=1;cycles(30);
 key(1);cycles(60);
 if(!dut.play_active_sd || dut.thumb_mode_sd || !dut.stream_enable_sd) $fatal(1,"FAIL home confirmation did not play directly");
 if(!dut.waveform_enable_frame) $fatal(1,"FAIL PLAY waveform missing");
 key(6);cycles(30);
 if(!dut.thumb_mode_sd || dut.play_active_sd) $fatal(1,"FAIL KEY7 PLAY must directly open grid and stop");
 cycles(60);if(dut.waveform_enable_frame) $fatal(1,"FAIL grid waveform still enabled");
 key(2);key(1);settled();
 if(!dut.play_active_sd || dut.thumb_mode_sd || dut.play_sel_song_sd!=1 || dut.disp_buf_idx!=1)
  $fatal(1,"FAIL grid focus/display/audio mismatch");
 key(10);cycles(30);if(dut.play_active_sd || dut.thumb_mode_sd) $fatal(1,"FAIL KEY11 global home");
 cycles(60);
 if(dut.waveform_enable_frame) $fatal(1,"FAIL home waveform still enabled");
 // Even retained nonzero history and a pixel in the baseline must be transparent.
 force dut.u_promax_audio_waveform.display_valid=1'b1;
 force dut.u_promax_audio_waveform.line_y=12'd471;
 force dut.adjusted_de=1'b1;force dut.adjusted_pixel_x=10'd80;
 force dut.osd_rgb_out=24'h123456;
 cycles(2);
 if(dut.waveform_active || dut.waveform_rgb_out!==24'h123456)
  $fatal(1,"FAIL home retains spectrum pixels");
 release dut.u_promax_audio_waveform.display_valid;release dut.u_promax_audio_waveform.line_y;
 release dut.adjusted_de;release dut.adjusted_pixel_x;release dut.osd_rgb_out;
 key(1);cycles(60);eof=1;cycles(25);if(!dut.paused_sd) $fatal(1,"FAIL drained EOF pause");
 key(1);eof=0;cycles(60);if(dut.paused_sd || !dut.stream_enable_sd) $fatal(1,"FAIL EOF replay");
 key(11);if(dut.play_end_mode!=1) $fatal(1,"FAIL KEY12 repeat");
 key(11);if(dut.play_end_mode!=2) $fatal(1,"FAIL KEY12 next");
 key(8);if(dut.effect_mode!=1) $fatal(1,"FAIL KEY9 page");
 key(0);settled();
 if(dut.cover_direction!=0 || dut.disp_buf_idx!=0) $fatal(1,"FAIL PLAY previous page direction/bank");
 key(2);settled();
 if(dut.cover_direction!=1 || dut.disp_buf_idx!=1) $fatal(1,"FAIL PLAY next page direction/bank");
 key(8);if(dut.effect_mode!=2) $fatal(1,"FAIL KEY9 fade");
 key(8);if(dut.effect_mode!=0) $fatal(1,"FAIL KEY9 cut");
 error=8'h34;status=24'hff3400;cycles(20);
 if(dut.play_active_sd || dut.media_err_code!=8'h34) $fatal(1,"FAIL bad index treated as mounted");
 wait(!dut.media_sd_rst_n);wait(dut.media_sd_rst_n);
 error=0;status=24'hff0000;cycles(100);
 if(dut.media_err_code!=0 || dut.osd_err_code_frame_eff!=0) $fatal(1,"FAIL CRC recovery did not clear OSD");
 key(1);cycles(60);sector_error=5;sector_done=1;cycles(1);sector_done=0;sector_error=0;
 cycles(100);
 if(dut.play_active_sd || dut.thumb_mode_sd || dut.media_err_code!=0) $fatal(1,"FAIL remove/remount UI lifecycle");
 if(!dut.audio_silent) $fatal(1,"FAIL media removal produced fallback tone");
 key(1);cycles(60);if(!dut.stream_enable_sd) $fatal(1,"FAIL playback cannot restart after remount");
 $display("PASS top UI keys, EOF replay, CRC remount, media fault silence and recovery");$finish;
 end
 initial begin #2000000;$fatal(1,"FAIL top watchdog");end
endmodule

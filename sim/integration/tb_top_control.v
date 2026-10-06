`timescale 1ns/1ps
// Full top control wiring; vendor PLL/HDMI/SDRAM primitives are black boxes.
// Force only clock/reset, video frame boundaries, and storage/audio data boundaries.
module tb_top_control;
reg clk=0, sdclk=0, pixclk=0, reset=0;
always #10 clk=~clk;
always #5 sdclk=~sdclk;
always #20 pixclk=~pixclk;
reg vs=1;
integer frames=0;
always @(negedge pixclk) begin
 frames=frames+1;
 vs=(frames%30!=0);
end
reg confirm=0, mode=0, right=0;
reg stop_tgl=0, cf_tgl=0;
reg [23:0] status=24'hFF0000;
reg wav_active=0;
reg skip=0;
top #(.BUZZER_FEEDBACK_ENABLE(1'b0),.ECHO_TEST_ENABLE(1'b0)) dut
(.clk(clk),.rst_n(reset),.key1(1'b1),.key2(1'b1),.key3(1'b1),
 .sw1(1'b1),.sw2(1'b1),.sw3(1'b1),.sw4(1'b1),.sd_miso(1'b1),
 .exp_key_n(12'hFFF),.exp_dip_n(6'h01),.exp_enc1_a(1'b1),.exp_enc1_b(1'b1),.exp_enc1_sw_n(1'b1),
 .exp_enc2_a(1'b1),.exp_enc2_b(1'b1),.exp_enc2_sw_n(1'b1),.exp_ir_rx(1'b1));
defparam dut.u_boot_layer.CLK_FREQ_HZ=1000;
initial begin
 force dut.sd_card_clk=sdclk; force dut.ext_mem_clk=sdclk; force dut.video_clk=pixclk;
 force dut.sdcard_rst_n=reset; force dut.mem_rst_n=reset; force dut.video_rst_n=reset;
 force dut.exp_rst_n=reset;
 force dut.vs=vs;
 force dut.brw_thumb_confirm=confirm; force dut.brw_thumb_right=right;
 force dut.brw_ev_mode_tgl=stop_tgl; force dut.brw_ev_confirm_tgl=cf_tgl;
 force dut.boot_skip_toggle_clk=skip;
 force dut.media_status_sd=status;
 force dut.sd_card_bmp_m0.sd_init_done=1'b1;
 force dut.sd_card_bmp_m0.scan_done=1'b1;
 force dut.sd_card_bmp_m0.scan_kicked=1'b1;
 force dut.sd_card_bmp_m0.img_found_count=3'd4;
 force dut.sd_card_bmp_m0.image_ready=4'hF;
 force dut.sd_card_bmp_m0.preload_idx=3'd4;
 force dut.sd_card_bmp_m0.display_valid=1'b1;
 force dut.sd_card_bmp_m0.load_busy=1'b0;
 force dut.wav_stream_active=wav_active;
 force dut.arp_sample_valid=1'b1;
 force dut.arp_sample_left=16'sd1234; force dut.arp_sample_right=16'sd1234;
 force dut.wav_scaled_valid=1'b1;
 force dut.wav_scaled_left=16'sd2345; force dut.wav_scaled_right=16'sd2345;
 repeat(8) @(negedge clk); reset=1;
 repeat(100) @(negedge pixclk); skip=1;
 repeat(3800) @(negedge pixclk);
 if(!dut.boot_active) $fatal(1,"FAIL early skip hid logo before acquisition window");
 repeat(180) @(negedge pixclk);
 if(dut.boot_active) $fatal(1,"FAIL latched skip did not leave boot after 4s");
 if(dut.mix_sample_left!==16'd0 || !dut.mix_sample_valid) $fatal(1,"FAIL startup/browse audible or no cadence");
 $display("PASS logo 4s skip guard and startup silence");
 // Enter the grid through the real mode toggle and confirm current bank 0.
 @(negedge sdclk); stop_tgl=1;
 repeat(12) @(negedge sdclk);
 if(!dut.thumb_mode_sd) $fatal(1,"FAIL enter grid");
 confirm=1; @(negedge sdclk); confirm=0;
 repeat(150) @(negedge pixclk);
 if(dut.thumb_mode_sd || dut.thumb_select_pending_sd || dut.fade_busy || !dut.play_active_sd)
   $fatal(1,"FAIL same-bank confirm did not exit cleanly");
 wav_active=1; repeat(12) @(negedge pixclk);
 if(dut.mix_sample_left!==16'd2345) $fatal(1,"FAIL song did not resume");
 cf_tgl=1; repeat(20) @(negedge pixclk);
 if(!dut.paused_sd || dut.wav_sample_tick_eff || dut.mix_sample_left!==16'd0)
   $fatal(1,"FAIL pause must freeze and send zero samples");
 cf_tgl=0; repeat(20) @(negedge pixclk);
 if(dut.paused_sd || dut.mix_sample_left!==16'd2345) $fatal(1,"FAIL resume");
 stop_tgl=0; repeat(150) @(negedge pixclk);
 if(dut.play_active_sd || !dut.thumb_mode_sd || dut.mix_sample_left!==16'd0)
   $fatal(1,"FAIL single KEY7 must stop/open grid/silence");
 confirm=1; @(negedge sdclk); confirm=0;
 repeat(150) @(negedge pixclk);
 if(!dut.play_active_sd || dut.thumb_mode_sd || dut.fade_busy || dut.mix_sample_left!==16'd2345)
   $fatal(1,"FAIL same-song reselect after KEY7");
 $display("PASS same-bank exit/re-entry, EC1 pause/resume and single KEY7 silent grid");
 // Select a different bank through the real fade -> held select -> ack chain.
 stop_tgl=1; repeat(150) @(negedge pixclk);
 right=1; @(negedge sdclk); right=0;
 repeat(5) @(negedge sdclk);
 confirm=1; @(negedge sdclk); confirm=0;
 repeat(1800) @(negedge pixclk);
 if(dut.disp_buf_idx!==2'd1 || dut.fade_busy || dut.fade_alpha!==8'd255 || dut.thumb_select_hold_sd)
   $fatal(1,"FAIL cross-bank select/ack/fade completion bank=%d busy=%b",dut.disp_buf_idx,dut.fade_busy);
 stop_tgl=0; repeat(150) @(negedge pixclk);
 confirm=1; @(negedge sdclk); confirm=0;
 repeat(150) @(negedge pixclk);
 if(dut.disp_buf_idx!==2'd1 || dut.fade_busy || dut.thumb_mode_sd || dut.thumb_select_pending_sd)
   $fatal(1,"FAIL current nonzero bank reselect");
 $display("PASS different-bank fade handshake and current bank1 reselect");
 // Metadata absent after boot: retain documented no-card tone.
 status=24'd0; wav_active=0;
 repeat(15) @(negedge pixclk);
 if(dut.mix_sample_left!==16'd1234) $fatal(1,"FAIL no-card fallback tone lost");
 $display("PASS no-card fallback; TEST_PASS top_control");
 $finish;
end
initial begin #2000000; $fatal(1,"FAIL top control watchdog"); end
endmodule

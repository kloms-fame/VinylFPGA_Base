`timescale 1ns/1ps
module tb_navigation_readiness;
 reg clk=0, rst_n=0;
 always #5 clk=~clk;
 integer cycles=0;
 always @(posedge clk) cycles=cycles+1;

 reg clk50=0, rst50_n=0, key_n=1;
 always #10 clk50=~clk50;
 integer key_cycles=0, key_start_cycle=0, key_latency=-1;
 integer key_event_latency=-1;
 wire key_tick, key_fall;
 wire [0:0] key_level;
 debounce_tick #(.TICK_CYCLES(5000)) key_tick_gen(
  .clk(clk50),.rst_n(rst50_n),.tick_ce(key_tick));
 key_dip_monitor #(.KEY_COUNT(1),.DIP_COUNT(1),.DEBOUNCE_CYCLES(400000),
  .DEBOUNCE_TICK_CYCLES(5000),.USE_EXTERNAL_TICK(1)) key_path(
  .clk(clk50),.rst_n(rst50_n),.debounce_ce(key_tick),.key_async(key_n),
  .dip_async(1'b1),.key_level(key_level),.key_fall_pulse(key_fall),
  .key_rise_pulse(),.dip_level(),.dip_change_pulse(),.dip_change_index());
 always @(posedge clk50) begin
  key_cycles=key_cycles+1;
  if (key_fall && key_latency<0) key_latency=key_cycles-key_start_cycle;
 end
 localparam integer PRESENT_SETTLE_CYCLES = 455016;
 reg [19:0] startup_count=0;
 reg startup_ready=0;
 always @(posedge clk50 or negedge rst50_n) begin
  if (!rst50_n) begin startup_count<=0; startup_ready<=0; end
  else if (!startup_ready) begin
   if (startup_count==PRESENT_SETTLE_CYCLES-1) startup_ready<=1;
   else startup_count<=startup_count+1'b1;
  end
 end
 wire boot_ev_valid;
 wire [3:0] boot_ev_code;
 wire [15:0] boot_ev_arg, boot_ev_aux;
 ui_event_bus startup_event_bus(.clk(clk50),.rst_n(rst50_n),
  .ev_enable(startup_ready),.key_fall_pulse({11'd0,key_fall}),
  .key_rise_pulse(12'd0),.dip_level(6'd1),.dip_change_pulse(6'd0),
  .dip_change_index(3'd0),.enc1_step_pulse(1'b0),.enc1_direction(1'b0),
  .enc1_count(16'd0),.enc1_sw_fall_pulse(1'b0),.enc1_sw_rise_pulse(1'b0),
  .enc2_step_pulse(1'b0),.enc2_direction(1'b0),.enc2_count(16'd0),
  .enc2_sw_fall_pulse(1'b0),.enc2_sw_rise_pulse(1'b0),.ir_event(1'b0),
  .ir_repeat_event(1'b0),.ir_code(32'd0),.ev_valid(boot_ev_valid),
  .ev_code(boot_ev_code),.ev_arg(boot_ev_arg),.ev_aux(boot_ev_aux));
 always @(posedge clk50) begin
  if (boot_ev_valid && boot_ev_code==4'd1 && key_event_latency<0)
   key_event_latency=key_cycles-key_start_cycle;
 end

 reg scan_done=0, media_mounted=0, audio_file_valid=0;
 reg [3:0] source_valid=0;
 reg [15:0] scan_error=0;
 reg [31:0] audio_total_sectors=0;
 wire browse_ready, playback_ready;
 wire [2:0] browse_count;
 navigation_readiness readiness(
  .scan_done(scan_done),.source_valid(source_valid),.scan_error(scan_error),
  .media_mounted(media_mounted),.audio_file_valid(audio_file_valid),
  .audio_total_sectors(audio_total_sectors),.browse_ready(browse_ready),
  .browse_count(browse_count),.playback_ready(playback_ready));

 reg next_toggle=0, confirm_request=0, transition_commit=0, image_ready=0;
 reg [1:0] displayed=0;
 wire fs_next, fs_prev, play_start, play_stop;
 wire transition_start, direction, select_req, busy, auto_ack;
 wire [1:0] select_index;
 wire select_ack=select_req && image_ready;
 wire play_active, paused, restart_request, seek_clear;
 wire [1:0] selected_song, end_mode;
 wire volume_valid, volume_up, track_step, track_dir;

 browse_fsm browse(.clk(clk),.rst_n(rst_n),.ev_prev_tgl(1'b0),
  .ev_next_tgl(next_toggle),.ev_confirm_tgl(1'b0),.ev_mode_tgl(1'b0),
  .ev_home_tgl(1'b0),.mode_play(play_active),.fs_next(fs_next),
  .fs_prev(fs_prev),.play_start(play_start),.play_stop(play_stop));

 cover_navigation nav(.clk(clk),.rst_n(rst_n),.ready(browse_ready),
  .count(browse_count),.displayed(displayed),.next_step(fs_next),
  .prev_step(fs_prev),.auto_next(1'b0),.choose(track_step),
  .chosen(selected_song),.chosen_direction(track_dir),.transition_busy(1'b0),
  .transition_commit(transition_commit),.select_ack(select_ack),
  .transition_start(transition_start),.direction(direction),
  .select_req(select_req),.select_index(select_index),.busy(busy),
  .auto_switch_ack(auto_ack));

 play_ctrl player(.clk(clk),.rst_n(rst_n),.song_total(3'd2),
  .song_confirm(confirm_request && playback_ready),.focus_index(displayed),
  .enc_cw_tgl(1'b0),.enc_ccw_tgl(1'b0),.confirm_tgl(1'b0),
  .key_up_tgl(1'b0),.key_down_tgl(1'b0),.stop_request(1'b0),
  .media_lost(1'b0),.stream_end(1'b0),.end_mode_tgl(1'b0),
  .restart_request(restart_request),.stop_tgl(1'b0),.seek_restart_in(1'b0),
  .seek_clear(seek_clear),.play_active(play_active),.paused(paused),
  .sel_song(selected_song),.volume_intent_valid(volume_valid),
  .volume_intent_up(volume_up),.track_step(track_step),.track_dir(track_dir),
  .end_mode(end_mode));

 always @(posedge clk) begin
  if (rst_n && select_req && select_ack)
   displayed <= select_index;
 end

 integer event_cycle, pulse_latency, nav_latency;
 initial begin
  repeat(4) @(negedge clk);
  rst_n=1;
  scan_done=1;
  source_valid=4'b0011;
  audio_file_valid=1;
  audio_total_sectors=32'd900;
  @(negedge clk50); rst50_n=1; key_n=0; key_start_cycle=key_cycles;
  #1;
  if (!browse_ready || browse_count!=3'd2 || playback_ready)
   $fatal(1,"browse must be ready before preload/mount; playback must remain blocked");

  @(negedge clk); event_cycle=cycles; next_toggle=1;
  wait(fs_next); pulse_latency=cycles-event_cycle;
  wait(transition_start); nav_latency=cycles-event_cycle;
  if (pulse_latency>4 || nav_latency>6)
   $fatal(1,"slow browse path pulse=%0d navigation=%0d cycles",pulse_latency,nav_latency);
  @(negedge clk); transition_commit=1;
  @(negedge clk); transition_commit=0;
  wait(select_req);
  repeat(4) @(posedge clk);
  if (!select_req || displayed!=0)
   $fatal(1,"browse selection must stay pending while its image is not ready");
  image_ready=1;
  wait(!busy);
  if (displayed!=1) $fatal(1,"pending browse selection did not commit after image became ready");

  @(negedge clk); confirm_request=1;
  @(negedge clk); confirm_request=0;
  repeat(2) @(posedge clk);
  if (play_active) $fatal(1,"playback started while media was not mounted");
  media_mounted=1; audio_file_valid=0;
  @(negedge clk); confirm_request=1;
  @(negedge clk); confirm_request=0;
  repeat(2) @(posedge clk);
  if (play_active) $fatal(1,"playback started without valid audio metadata");
  audio_file_valid=1;
  @(negedge clk); confirm_request=1;
  @(negedge clk); confirm_request=0;
  repeat(2) @(posedge clk);
  if (!play_active) $fatal(1,"playback did not start after media/audio became ready");
  wait(key_latency>=0);
  if (key_latency<405000 || key_latency>410010)
   $fatal(1,"raw key debounce latency outside expected range: %0d cycles",key_latency);
  wait(key_event_latency>=0);
  if (key_event_latency<PRESENT_SETTLE_CYCLES || key_event_latency>PRESENT_SETTLE_CYCLES+8)
   $fatal(1,"startup key event was not held until readiness: %0d cycles",key_event_latency);
  $display("PASS navigation readiness: key debounce=%0d cycles, startup press delivered=%0d cycles (50 MHz); browse_toggle_to_pulse=%0d cycles, to_transition=%0d cycles; image-wait browsing and mount/audio playback gates",key_latency,key_event_latency,pulse_latency,nav_latency);
  $finish;
 end
 initial begin #10000000; $fatal(1,"navigation readiness timeout"); end
endmodule

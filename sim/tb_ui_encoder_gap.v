`timescale 1ns/1ps
module tb_ui_encoder_gap;
 reg clk=0,rst_n=0,ev_valid=0;
 reg [3:0] ev_code=0;
 reg [15:0] ev_arg=0,ev_aux=0;
 wire prev_tgl,next_tgl,confirm_tgl,mode_tgl,home_tgl,effect_tgl,end_mode_tgl;
 wire lyric_focus_tgl;
 wire enc_cw_tgl,enc_ccw_tgl,key_up_tgl,visual_tgl,key_down_tgl,ws_mode_tgl;
 wire seek_fwd5_tgl,seek_bwd5_tgl,replay_tgl,seek_fwd2_tgl,seek_bwd2_tgl;
 integer cycles=0,last_toggle=-1,toggle_count=0,i;
 reg next_tgl_q=0;
 always #10 clk=~clk;
 ui_event_bridge dut(.*);
 always @(posedge clk) begin
  cycles<=cycles+1;
  if(rst_n && next_tgl !== next_tgl_q) begin
   if(last_toggle>=0 && cycles-last_toggle<8)
    $fatal(1,"FAIL encoder toggle gap %0d clocks; required >=8",cycles-last_toggle);
   last_toggle=cycles;
   toggle_count=toggle_count+1;
  end
 end
 always @(posedge clk) next_tgl_q<=next_tgl;
 initial begin
  repeat(4) @(negedge clk);rst_n=1;
  // A burst of queued encoder counts exercises coalescing and the exact
  // source-clock spacing of the emitted toggle CDC events.
  for(i=1;i<=16;i=i+1) begin
   @(negedge clk);ev_valid=1;ev_code=4'd4;ev_arg=i;ev_aux=0;
  end
  @(negedge clk);ev_valid=0;ev_code=0;
  repeat(300) @(negedge clk);
  if(toggle_count!=16) $fatal(1,"FAIL delivered encoder events=%0d expected=16",toggle_count);
  $display("PASS ui encoder toggle spacing >=8 source clocks (%0d events)",toggle_count);
  $finish;
 end
 initial begin #10000;$fatal(1,"FAIL watchdog");end
endmodule

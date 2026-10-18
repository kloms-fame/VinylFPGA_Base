`timescale 1ns/1ps
// Test actual production pixel wiring; vendor hard-IP boundaries are stubs.
module tb_closure_top_handoff;
 reg clk=0;always #5 clk=~clk;
 reg play=1,mv=0,wipe=0;reg [7:0] alpha=255;
 reg [23:0] source=24'h80c040;
 integer a;
 top dut(.clk(clk),.rst_n(1'b0),.key3(1'b1),.sw1(1'b1),.sw2(1'b1),.sw3(1'b0),.sw4(1'b1),
 .sd_miso(1'b1),.exp_key_n(12'hfff),.exp_dip_n(6'h37),
 .exp_enc1_a(1'b1),.exp_enc1_b(1'b1),.exp_enc1_sw_n(1'b1),
 .exp_enc2_a(1'b1),.exp_enc2_b(1'b1),.exp_enc2_sw_n(1'b1),.exp_ir_rx(1'b1));
 initial begin
  force dut.vout_data=source;
  force dut.playback_page_mode_frame=play;
  force dut.mv_read_active=mv;
  force dut.mv_window_visible=1'b1;
  force dut.background_image_active=1'b1;
  force dut.fade_alpha=alpha;
  force dut.brightness_frame=8'd255;
  force dut.wipe_active=wipe;
  force dut.wipe_ramp=5'd0;
  force dut.transition_kind=2'd0;
  force dut.osd_pixel_x=10'd176;
  for(a=0;a<256;a=a+1)begin
   alpha=a;wipe=a[0];mv=a[1];#1;
   if(dut.view_rgb!==source || dut.transition_rgb!==24'h7fbf3f)
    $fatal(1,"actual top blanked cover/MV during PLAY alpha=%0d mv=%b rgb=%h",a,mv,dut.transition_rgb);
  end
  play=0;alpha=0;wipe=0;#1;
  if(dut.transition_rgb!==0)$fatal(1,"actual top lost browse fade");
  $display("PASS closure_top_handoff actual top cover-to-MV fallback and PLAY fade/wipe bypass");$finish;
 end
endmodule

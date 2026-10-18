`timescale 1ns/1ps
module tb_closure_no_blackflash;
 reg [7:0] alpha=255,brightness=255;
 reg preserve=0,wipe=0;reg [4:0] ramp=0;
 wire [23:0] rgb;
 integer a,r;
 video_transition_apply dut(.rgb_in(24'h80c040),.alpha(alpha),.brightness(brightness),
  .preserve_media(preserve),.wipe_active(wipe),.wipe_reverse(1'b0),.wipe_ramp(ramp),
  .pixel_x(10'd176),.rgb_out(rgb));
 initial begin
  #1;alpha=0;#1;if(rgb!=0)$fatal(1,"browse fade no longer reaches black");
  preserve=1;
  for(a=0;a<256;a=a+1)begin
   alpha=a;
   for(r=0;r<=16;r=r+1)begin
    ramp=r;wipe=r[0];#1;
    if(rgb!==24'h7fbf3f)$fatal(1,"PLAY cover/MV black flash alpha=%0d ramp=%0d rgb=%h",a,r,rgb);
   end
  end
  brightness=127;#1;if(rgb!==24'h3f5f1f)$fatal(1,"PLAY bypass lost brightness control");
  brightness=0;#1;if(rgb!==0)$fatal(1,"intentional zero brightness not honored");
  preserve=0;brightness=255;alpha=255;wipe=1;ramp=0;#1;
  if(rgb!==0)$fatal(1,"browse wipe rollback changed");
  $display("TEST_PASS closure_no_blackflash PLAY cover/MV visible across all fade/wipe phases brightness retained");$finish;
 end
endmodule

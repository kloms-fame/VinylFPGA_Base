`timescale 1ns/1ps
// Controlled pixel boundary checks the production top's actual overlay wiring.
module tb_opt_osd_bypass;
 reg clk=0,rst=0,de=0,vs=0,ready=0;
 reg [23:0] rgb=0;reg [7:0] error=0;
 integer x,y,frame;
 top dut(.clk(clk),.rst_n(rst),.key3(1'b1),.sw1(1'b1),.sw2(1'b1),.sw3(1'b0),.sw4(1'b1),
 .sd_miso(1'b1),.exp_key_n(12'hfff),.exp_dip_n(6'h37),
 .exp_enc1_a(1'b1),.exp_enc1_b(1'b1),.exp_enc1_sw_n(1'b1),
 .exp_enc2_a(1'b1),.exp_enc2_b(1'b1),.exp_enc2_sw_n(1'b1),.exp_ir_rx(1'b1));
 always #5 clk=~clk;
 initial begin
  force dut.adjusted_rgb=rgb;force dut.adjusted_de=de;force dut.vs=vs;
  force dut.display_valid_sync2=ready;force dut.media_err_code_frame=error;
  for(frame=0;frame<3;frame=frame+1) begin
   ready=(frame!=1);error=(frame==1)?8'h34:0;vs=~vs;
   for(y=0;y<480;y=y+1) for(x=0;x<642;x=x+1) begin
    de=(x<640);rgb={x[7:0],y[7:0],x[7:0]^y[7:0]};#1;
    if(dut.osd_rgb_out !== ((!ready && error!=0)?24'h201018:rgb))
     $fatal(1,"FAIL overlay bypass at %0d,%0d frame %0d",x,y,frame);
   end
  end
  if(dut.brightness_frame!=255 || dut.contrast_frame!=128)$fatal(1,"FAIL default picture controls");
  $display("PASS complete-frame OSD bypass, blanking, error and recovery");$finish;
 end
endmodule

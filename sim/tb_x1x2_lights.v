`timescale 1ns/1ps
module tb_x1x2_lights;
reg clk=0,rst=0,en=1,mode=0,ir=0,biz=0,fault=0,mv=0,mute=0;reg[7:0] level=255;reg[3:0] progress=3;
wire ws;wire[3:0] led;
always #10 clk=~clk;
ws2812_effects #(.CLK_FREQ_HZ(1000),.REFRESH_MS(20),.BIT_CYCLES(4),.T0H_CYCLES(1),.T1H_CYCLES(2),.RESET_CYCLES(4)) dut
 (.clk(clk),.rst_n(rst),.enable(en),.mode_tgl(mode),.level(level),.progress(progress),.mute(mute),.ws_data(ws));
led_business_driver #(.CLK_FREQ_HZ(1000)) leds(.clk(clk),.rst_n(rst),.en(en),.ir_accepted(ir),.biz_accepted(biz),.fault(fault),.mv_active(mv),.led_n(led));
integer i,j;reg[191:0] first;reg[7:0] chan;
initial begin
 repeat(4)@(negedge clk);rst=1;mode=1;repeat(8)@(negedge clk);
 if(led!==4'b0111)$fatal(1,"FAIL RUN silk mapping");
 ir=1;biz=1;mv=1;@(negedge clk);ir=0;biz=0;
 if(led!==0)$fatal(1,"FAIL IR/MV/ACTION silk mapping");
 first=dut.frame_grb;
 for(j=0;j<2000;j=j+1)begin
  @(negedge clk);
  for(i=0;i<24;i=i+1)begin chan=dut.frame_grb[i*8+:8];if(chan>80)$fatal(1,"FAIL brightness cap");end
 end
 if(first===dut.frame_grb)$fatal(1,"FAIL RGB colour animation");
 mute=1;#1;if(dut.frame_grb!==0)$fatal(1,"FAIL mute");mute=0;
 mode=0;repeat(8)@(negedge clk);
 for(j=0;j<8;j=j+1)begin
  repeat(250)@(negedge clk);
  for(i=0;i<8;i=i+1)begin
   if((i<progress || i==dut.runner) && dut.frame_rgb[i]==0)$fatal(1,"FAIL progress/runner missing");
   if(i>=progress && i!=dut.runner && dut.frame_rgb[i]!=0)$fatal(1,"FAIL spurious progress light");
  end
 end
 en=0;repeat(2500)@(negedge clk);
 if(led!==15 || !dut.black_sent || dut.busy || ws)$fatal(1,"FAIL DIP off black frame and idle");
 for(i=0;i<8;i=i+1)if(dut.u_ws2812_driver.pixel_mem[i]!==0)$fatal(1,"FAIL black frame payload");
 $display("PASS silk mapping RGB brightness travelling progress and DIP6 black frame");$finish;
end
endmodule

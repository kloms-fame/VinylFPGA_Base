`timescale 1ns/1ps
module tb_x1x2_lights;
reg clk=0,rst=0,en=1,mode=0,ir=0,biz=0,fault=0,mv=0,mute=0;reg[7:0] level=255;reg[3:0] progress=3;
wire ws;wire[3:0] led;
always #10 clk=~clk;
ws2812_effects #(.CLK_FREQ_HZ(1000),.REFRESH_MS(20),.BIT_CYCLES(4),.T0H_CYCLES(1),.T1H_CYCLES(2),.RESET_CYCLES(4)) dut
 (.clk(clk),.rst_n(rst),.enable(en),.mode_tgl(mode),.level(level),.progress(progress),.mute(mute),.ws_data(ws));
led_business_driver #(.CLK_FREQ_HZ(1000)) leds(.clk(clk),.rst_n(rst),.en(en),.ir_accepted(ir),.biz_accepted(biz),.fault(fault),.mv_active(mv),.led_n(led));
integer i,j,bit_count=0,high_count=0,frames=0;
reg [191:0] first, captured=0, frozen=0, expected=0;
reg [23:0] rgb;
reg [7:0] r,g,b,amp,chan;
reg was_high=0;
// Independently render the accepted frame, then check actual physical pulse widths.
// Tests follow the public serialized output instead of the implementation's frame storage.
always @(posedge clk) begin
 if(rst && dut.load_req && !dut.busy) begin
  expected=0;bit_count=0;
  amp=(mute || level<8) ? 0 : level[7:2];
  for(i=0;i<8;i=i+1) begin
   rgb=0;
   if(en && dut.mode==1) begin
    r=dut.wheel_r<amp ? dut.wheel_r : amp;
    g=dut.wheel_g<amp ? dut.wheel_g : amp;
    b=dut.wheel_b<amp ? dut.wheel_b : amp;
    rgb={r,g,b};
   end else if(en && dut.mode==2) begin
    if(i<progress) rgb={4'b0,dut.wheel_r[5:2],4'b0,dut.wheel_g[5:2],4'b0,dut.wheel_b[5:2]};
    if(i==dut.runner) rgb={2'b0,dut.wheel_r,2'b0,dut.wheel_g,2'b0,dut.wheel_b};
   end
   expected[i*24+:24]={rgb[15:8],rgb[23:16],rgb[7:0]};
  end
 end
 #1;
 if(!rst) begin high_count=0;was_high=0;bit_count=0;end
 else begin
  if(ws) high_count=high_count+1;
  else if(was_high) begin
   if(high_count!=1 && high_count!=2) $fatal(1,"FAIL WS pulse width");
   captured[(bit_count/24)*24+23-(bit_count%24)]=(high_count==2);
   bit_count=bit_count+1;
   high_count=0;
   if(bit_count==192) begin
    frozen=captured;frames=frames+1;
    if(captured!==expected) $fatal(1,"FAIL serialized frame RGB/progress/mute/black");
    for(i=0;i<24;i=i+1) begin
     chan=captured[i*8+:8];if(chan>80)$fatal(1,"FAIL brightness cap");
    end
   end
  end
  was_high=ws;
 end
end
task next_frame;
 integer before_frame,timeout;
 begin
  before_frame=frames;timeout=0;
  while(frames==before_frame && timeout<2000) begin @(negedge clk);timeout=timeout+1;end
  if(frames==before_frame)$fatal(1,"FAIL no physical WS frame");
 end
endtask
initial begin
 repeat(4)@(negedge clk);rst=1;mode=1;repeat(8)@(negedge clk);
 if(led!==4'b0111)$fatal(1,"FAIL RUN silk mapping");
 ir=1;biz=1;mv=1;@(negedge clk);ir=0;biz=0;
 if(led!==0)$fatal(1,"FAIL IR/MV/ACTION silk mapping");
 next_frame;first=frozen;next_frame;next_frame;
 if(first===frozen)$fatal(1,"FAIL RGB colour animation");
 mute=1;next_frame;next_frame;
 if(frozen!==0)$fatal(1,"FAIL mute");mute=0;
 mode=0;repeat(8)@(negedge clk);
 // Each captured progress frame is checked against its load-edge runner and progress.
 for(j=0;j<8;j=j+1)next_frame;
 en=0;repeat(2500)@(negedge clk);
 if(led!==15 || !dut.black_sent || dut.busy || ws)$fatal(1,"FAIL DIP off black frame and idle");
 if(frozen!==0)$fatal(1,"FAIL black frame payload");
 $display("PASS silk mapping RGB brightness travelling progress and DIP6 black frame");$finish;
end
endmodule

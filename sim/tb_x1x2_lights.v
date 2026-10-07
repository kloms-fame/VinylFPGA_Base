`timescale 1ns/1ps
module tb_x1x2_lights #(parameter REAL_TIMING=0);
localparam T0=REAL_TIMING ? 18 : 1, T1=REAL_TIMING ? 35 : 2;
reg clk=0,rst=0,en=1,mode=0,ir=0,biz=0,fault=0,mv=0,mute=0;reg[7:0] level=255;reg[3:0] progress=3;
wire ws;wire[3:0] led;
always #10 clk=~clk;
ws2812_effects #(.CLK_FREQ_HZ(REAL_TIMING ? 50000000 : 1000),.REFRESH_MS(REAL_TIMING ? 1 : 20),.BIT_CYCLES(REAL_TIMING ? 63 : 4),.T0H_CYCLES(T0),.T1H_CYCLES(T1),.RESET_CYCLES(REAL_TIMING ? 3000 : 4)) dut
 (.clk(clk),.rst_n(rst),.enable(en),.mode_tgl(mode),.level(level),.progress(progress),.mute(mute),.ws_data(ws));
led_business_driver #(.CLK_FREQ_HZ(1000)) leds(.clk(clk),.rst_n(rst),.en(en),.ir_accepted(ir),.biz_accepted(biz),.fault(fault),.mv_active(mv),.led_n(led));
integer i,j,bit_count=0,high_count=0,frames=0;
reg [191:0] first, captured=0, frozen=0, expected=0;
reg [23:0] rgb;
reg [7:0] r,g,b,amp,chan;
integer model_mode=0, model_div=0, model_head=0, model_phase=0;
integer history[0:7];
integer bright, distance, colour, k;
reg [7:0] model_level;
reg [7:0] lit_mask;
integer colourful_frames=0, long_pulses=0, shift_checks=0;
reg was_high=0;
// Independently render the accepted frame, then check actual physical pulse widths.
// Tests follow the public serialized output instead of the implementation's frame storage.
always @(posedge clk) begin
 if(rst && dut.load_req && !dut.busy) begin
  expected=0;bit_count=0;
  amp=(mute || level<8) ? 0 : level/4;
  if(en) model_phase=(model_phase+1)%64;
  if(!en || dut.mode!=2 || dut.mode!=model_mode) model_head=0;
  else if(model_div==3) model_head=(model_head+1)%11;
  if(!en || dut.mode!=1 || mute) begin
   for(k=0;k<8;k=k+1)history[k]=0;
  end else if(dut.mode!=model_mode) begin
   for(k=0;k<8;k=k+1)history[k]=0;
   history[0]=amp;
  end else if(model_div==2) begin
   for(k=7;k>0;k=k-1)history[k]=history[k-1];
   history[0]=amp;shift_checks=shift_checks+1;
  end
  if(!en || dut.mode!=model_mode || dut.mode==0 ||
     (dut.mode==1 && model_div==2) || (dut.mode==2 && model_div==3))model_div=0;
  else model_div=model_div+1;
  model_mode=en ? dut.mode : 0;
  lit_mask=0;
  for(i=0;i<8;i=i+1) begin
   bright=0;
   if(model_mode==1)bright=history[i];
   if(model_mode==2)begin
    if(i<progress)bright=12;
    distance=model_head-i;
    if(distance>=0 && distance<4)begin
     case(distance)0:bright=63;1:bright=48;2:bright=32;3:bright=16;endcase
    end
   end
   r=0;g=0;b=0;colour=(i+8-model_phase/8)%8;
   case(colour)
    0:r=bright;1:begin r=bright;g=bright/2;end
    2:begin r=bright;g=bright;end 3:g=bright;
    4:begin g=bright;b=bright;end 5:b=bright;
    6:begin r=bright/2;b=bright;end 7:begin r=bright;b=bright;end
   endcase
   expected[i*24+:24]={g,r,b};
   if(bright!=0)lit_mask[i]=1;
  end
  if(model_mode==1 && expected[23:0]!=0 && expected[47:24]!=0 && expected[23:0]!=expected[47:24])colourful_frames=colourful_frames+1;
  if(model_mode==2 && progress==0 && model_head==3 && lit_mask==8'h0f)long_pulses=long_pulses+1;
 end
 #1;
 if(!rst) begin high_count=0;was_high=0;bit_count=0;end
 else begin
  if(ws) high_count=high_count+1;
  else if(was_high) begin
   if(high_count!=T0 && high_count!=T1) $fatal(1,"FAIL WS pulse width");
   captured[(bit_count/24)*24+23-(bit_count%24)]=(high_count==T1);
   bit_count=bit_count+1;
   high_count=0;
   if(bit_count==192) begin
    frozen=captured;frames=frames+1;
    if(captured!==expected) $fatal(1,"FAIL serialized frame RGB/progress/mute/black");
    for(i=0;i<24;i=i+1) begin
     chan=captured[i*8+:8];if(chan>63)$fatal(1,"FAIL brightness cap");
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
  while(frames==before_frame && timeout<(REAL_TIMING ? 120000 : 2000)) begin @(negedge clk);timeout=timeout+1;end
  if(frames==before_frame)$fatal(1,"FAIL no physical WS frame");
 end
endtask
initial begin
 for(k=0;k<8;k=k+1)history[k]=0;
 repeat(4)@(negedge clk);rst=1;mode=1;repeat(8)@(negedge clk);
 if(led!==4'b0111)$fatal(1,"FAIL RUN silk mapping");
 ir=1;biz=1;mv=1;@(negedge clk);ir=0;biz=0;
 if(led!==0)$fatal(1,"FAIL IR/MV/ACTION silk mapping");
 next_frame;first=frozen;repeat(30)next_frame;
 if(first===frozen)$fatal(1,"FAIL RGB colour animation");
 if(REAL_TIMING)begin
  mode=0;repeat(8)@(negedge clk);progress=0;repeat(16)next_frame;
  if(long_pulses==0)$fatal(1,"FAIL real timing long pulse");
  en=0;repeat(60000)@(negedge clk);
  if(frozen!==0 || dut.busy || ws)$fatal(1,"FAIL real timing shutdown");
  $display("PASS real 50MHz 63/18/35/3000 WS frames, RGB flow and long pulse (1ms refresh)");$finish;
 end
 for(j=0;j<30;j=j+1)begin level=(j*43)%256;next_frame;end
 level=0;repeat(27)next_frame;
 if(frozen!==0)$fatal(1,"FAIL silence must flow off strip");
 level=255;repeat(27)next_frame;
 mute=1;next_frame;next_frame;
 if(frozen!==0)$fatal(1,"FAIL mute");mute=0;
 mode=0;repeat(8)@(negedge clk);
 // Verify every fill count and pulse passage, including 0% and full-scale.
 progress=0;repeat(48)next_frame;
 for(j=0;j<=8;j=j+1)begin progress=j;repeat(48)next_frame;end
 if(colourful_frames==0 || long_pulses==0 || shift_checks<16)$fatal(1,"FAIL missing animation coverage");
 // Changes during serialization must not affect the accepted frame.
 @(posedge dut.busy);repeat(100)@(negedge clk);progress=0;level=0;
 next_frame;next_frame;
 en=0;repeat(2500)@(negedge clk);
 if(led!==15 || !dut.black_sent || dut.busy || ws)$fatal(1,"FAIL DIP off black frame and idle");
 if(frozen!==0)$fatal(1,"FAIL black frame payload");
 // Re-enable must send live frames again; mode 2 -> 0 must go black.
 en=1;next_frame;next_frame;mode=1;repeat(8)@(negedge clk);next_frame;next_frame;
 if(frozen!==0 || dut.mode!==0)$fatal(1,"FAIL mode cycle/off");
 if(frames<500)$fatal(1,"FAIL insufficient frame coverage");
 $display("PASS RGB right-flow history, four-pixel pulse, fill 0..8, mute, busy snapshot and black/resume; frames=%0d",frames);$finish;
end
initial begin #100000000;$fatal(1,"FAIL lights watchdog");end
endmodule

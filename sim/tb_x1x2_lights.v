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
reg [191:0] captured=0,frozen=0,expected=0;
integer model_mode=0,model_level=0,model_progress=0,age=0;
integer count,phase,head,energy,r,g,b,distance,flight,span;
integer absorption_frames=0,long_pulses=0,base_frames=0;
reg [255:0] vu_seen=0;
reg [8:0] progress_seen=0;
reg was_high=0;
// Reference uses an elapsed-frame timeline instead of DUT animation registers.
// Decode physical NRZ data and compare every pixel of every accepted frame.
always @(posedge clk) begin
 if(!rst)begin
  model_mode=0;model_level=0;model_progress=0;age=0;
 end else if(dut.load_req && !dut.busy)begin
  bit_count=0;expected=0;
  span=progress>8 ? 8 : progress;
  if(!en || dut.mode!=2 || dut.mode!=model_mode || span==0 || span!=model_progress)age=0;
  else age=(age+1)%(span*3+12);
  if(!en || dut.mode!=1 || mute)model_level=0;
  else if(dut.mode!=model_mode || level>=model_level)model_level=level;
  else if(model_level-level<=8)model_level=level;
  else model_level=model_level-8;
  model_mode=en ? dut.mode : 0;model_progress=span;
  count=(model_level*8)/255;
  flight=span*3;
  phase=age<flight ? 0 : (age<flight+8 ? 1 : 2);
  head=phase==0 ? age/3 : span-1;
  energy=63-8*(age-flight);
  if(model_mode==1 && model_level==level && !mute)vu_seen[level]=1;
  if(model_mode==2)begin
   progress_seen[span]=1;
   if(span>0 && phase==1)absorption_frames=absorption_frames+1;
   if(span>=4 && phase==0 && head>=3)long_pulses=long_pulses+1;
   if(span>0 && phase==2)base_frames=base_frames+1;
  end
  for(i=0;i<8;i=i+1)begin
   r=0;g=0;b=0;
   if(model_mode==1 && i<count)begin
    if(i<4)g=48;else if(i<6)begin r=56;g=32;end else r=63;
   end
   if(model_mode==2 && i<span)begin
    r=5;g=8;b=10;distance=head-i;
    if(phase==0 && distance>=0 && distance<4)begin
     case(distance)
      0:begin r=32;g=63;b=63;end 1:begin r=12;g=40;b=56;end
      2:begin r=6;g=22;b=36;end 3:begin r=5;g=12;b=20;end
     endcase
    end else if(phase==1 && i==span-1)begin
     r=energy>5 ? energy : 5;g=energy>8 ? energy : 8;b=energy>10 ? energy : 10;
    end
   end
   expected[i*24+:24]={g[7:0],r[7:0],b[7:0]};
  end
 end
 #1;
 if(!rst)begin high_count=0;was_high=0;bit_count=0;end
 else begin
  if(ws)high_count=high_count+1;
  else if(was_high)begin
   if(high_count!=T0 && high_count!=T1)$fatal(1,"FAIL WS pulse width");
   captured[(bit_count/24)*24+23-(bit_count%24)]=(high_count==T1);
   bit_count=bit_count+1;high_count=0;
   if(bit_count==192)begin
    frozen=captured;frames=frames+1;
    if(captured!==expected)$fatal(1,"FAIL frame=%0d mode=%0d age=%0d level=%0d progress=%0d got=%h want=%h",frames,model_mode,age,model_level,model_progress,captured,expected);
    for(i=0;i<24;i=i+1)if(captured[i*8+:8]>63)$fatal(1,"FAIL brightness cap");
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
 level=0;
 repeat(4)@(negedge clk);rst=1;mode=1;repeat(8)@(negedge clk);
 if(led!==4'b0111)$fatal(1,"FAIL RUN silk mapping");
 ir=1;biz=1;mv=1;@(negedge clk);ir=0;biz=0;
 if(led!==0)$fatal(1,"FAIL IR/MV/ACTION silk mapping");
 if(REAL_TIMING)begin
  level=255;next_frame;next_frame;
  mode=0;repeat(8)@(negedge clk);progress=8;repeat(40)next_frame;
  if(absorption_frames==0 || long_pulses==0 || base_frames==0)$fatal(1,"FAIL real charge coverage");
  en=0;repeat(60000)@(negedge clk);
  if(frozen!==0 || dut.busy || ws)$fatal(1,"FAIL real shutdown");
  $display("PASS real 50MHz 63/18/35/3000 VU and bounded charge/absorption (1ms refresh)");$finish;
 end
 // Exhaust all 256 input levels while increasing: next frame must attack directly.
 for(j=0;j<256;j=j+1)begin level=j;next_frame;end
 next_frame;next_frame;
 if(vu_seen!=={256{1'b1}})$fatal(1,"FAIL missing VU input level");
 level=0;next_frame;next_frame;
 if(frozen===0)$fatal(1,"FAIL no smooth decay");
 repeat(33)next_frame;if(frozen!==0)$fatal(1,"FAIL release to silence");
 level=255;next_frame;next_frame;mute=1;next_frame;next_frame;
 if(frozen!==0)$fatal(1,"FAIL mute");mute=0;
 mode=0;repeat(8)@(negedge clk);
 for(j=0;j<=8;j=j+1)begin progress=j;repeat(48)next_frame;end
 if(progress_seen!==9'h1ff || absorption_frames==0 || long_pulses==0 || base_frames==0)$fatal(1,"FAIL charge coverage");
 // Seek backward while transmitting: current frame must stay frozen, next must clip.
 @(posedge dut.busy);repeat(100)@(negedge clk);progress=1;
 repeat(20)next_frame;progress=0;next_frame;next_frame;
 if(frozen!==0)$fatal(1,"FAIL zero progress must be entirely black");
 progress=15;repeat(45)next_frame; // invalid input clamps to eight
 en=0;repeat(2500)@(negedge clk);
 if(led!==15 || !dut.black_sent || dut.busy || ws || frozen!==0)$fatal(1,"FAIL DIP off black frame");
 en=1;next_frame;next_frame;mode=1;repeat(8)@(negedge clk);next_frame;next_frame;
 if(frozen!==0 || dut.mode!==0)$fatal(1,"FAIL mode cycle/off");
 mode=0;next_frame;@(posedge dut.busy);repeat(100)@(negedge clk);rst=0;
 repeat(4)@(negedge clk);rst=1;mode=0;repeat(8)@(negedge clk);next_frame;next_frame;
 if(frozen!==0)$fatal(1,"FAIL reset during frame");
 $display("PASS VU 256 levels/fast attack/smooth decay; fill 0..8, bounded comet, endpoint absorption, seek/mute/off/reset; frames=%0d",frames);$finish;
end
initial begin #100000000;$fatal(1,"FAIL lights watchdog");end
endmodule

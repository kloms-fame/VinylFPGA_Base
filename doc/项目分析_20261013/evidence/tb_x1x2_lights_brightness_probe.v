`timescale 1ns/1ps
module tb_x1x2_lights #(parameter REAL_TIMING=0);
localparam T0=REAL_TIMING ? 18 : 1, T1=REAL_TIMING ? 35 : 2;
reg clk=0,rst=0,en=1,mode=0,ir=0,biz=0,fault=0,mv=0,mute=0;
reg [7:0] level=0;
wire ws; wire [3:0] led;
always #10 clk=~clk;
ws2812_effects #(.CLK_FREQ_HZ(REAL_TIMING ? 50000000 : 1000),
 .REFRESH_MS(REAL_TIMING ? 1 : 20),.BIT_CYCLES(REAL_TIMING ? 63 : 4),
 .T0H_CYCLES(T0),.T1H_CYCLES(T1),.RESET_CYCLES(REAL_TIMING ? 3000 : 4)) dut
 (.clk(clk),.rst_n(rst),.enable(en),.mode_tgl(mode),.brightness_level(3'd4),.level(level),.mute(mute),.ws_data(ws));
led_business_driver #(.CLK_FREQ_HZ(1000)) leds(.clk(clk),.rst_n(rst),.en(en),
 .ir_accepted(ir),.biz_accepted(biz),.fault(fault),.mv_active(mv),.led_n(led));

integer i,j,bit_count=0,high_count=0,frames=0,timeout;
reg [191:0] captured=0,frozen=0,expected=0;
integer model_mode=0,model_level=0,count,r,g,b;
reg was_high=0;

// Decode the actual WS2812 waveform and check each captured GRB pixel against
// an independent frame-boundary VU model.
always @(posedge clk) begin
 if(!rst) begin model_mode=0;model_level=0;end
 else if(dut.load_req && !dut.busy) begin
  bit_count=0;expected=0;
  if(!en || !dut.mode || mute) model_level=0;
  else if(dut.mode!=model_mode || level>=model_level) model_level=level;
  else if(model_level-level<=8) model_level=level;
  else model_level=model_level-8;
  model_mode=en ? dut.mode : 0;
  count=(model_level==255) ? 8 : model_level/32;
  for(i=0;i<8;i=i+1) begin
   r=0;g=0;b=0;
   if(model_mode && i<count) begin
    if(i<4)g=48;else if(i<6)begin r=56;g=32;end else r=63;
   end
   expected[i*24+:24]={g[7:0],r[7:0],b[7:0]};
  end
 end
 #1;
 if(!rst) begin high_count=0;was_high=0;bit_count=0;end
 else begin
  if(ws) high_count=high_count+1;
  else if(was_high) begin
   if(high_count!=T0 && high_count!=T1)$fatal(1,"FAIL WS pulse width %0d",high_count);
   captured[(bit_count/24)*24+23-(bit_count%24)]=(high_count==T1);
   bit_count=bit_count+1;high_count=0;
   if(bit_count==192) begin
    frozen=captured;frames=frames+1;
    if(captured!==expected)$fatal(1,"FAIL VU frame=%0d mode=%0d level=%0d got=%h want=%h",frames,model_mode,model_level,captured,expected);
    for(i=0;i<24;i=i+1)if(captured[i*8+:8]>63)$fatal(1,"FAIL brightness cap");
   end
  end
  was_high=ws;
 end
end

task next_frame;
 integer before_frame,guard;
 begin
  before_frame=frames;guard=0;
  while(frames==before_frame && guard<(REAL_TIMING ? 120000 : 4000)) begin @(negedge clk);guard=guard+1;end
  if(frames==before_frame)$fatal(1,"FAIL no physical WS frame");
 end
endtask
task key10;
 begin mode=~mode;repeat(8)@(negedge clk);end
endtask

initial begin
 repeat(4)@(negedge clk);rst=1;
 if(led!==4'b0111)$fatal(1,"FAIL RUN silk mapping");
 ir=1;biz=1;mv=1;@(negedge clk);ir=0;biz=0;
 if(led!==0)$fatal(1,"FAIL IR/MV/ACTION silk mapping");
 if(REAL_TIMING) begin
  level=255;key10;next_frame;next_frame;
  if(frozen===0)$fatal(1,"FAIL real VU output");
  key10;next_frame;
  if(frozen!==0)$fatal(1,"FAIL real all-off mode");
  en=0;repeat(60000)@(negedge clk);
  if(frozen!==0 || dut.busy || ws)$fatal(1,"FAIL real DIP shutdown");
  $display("PASS real 50MHz WS protocol, two-state VU/off, DIP shutdown");$finish;
 end

 // Exhaustively exercise all input levels and the original VU brightness cap.
 key10;
 for(j=0;j<256;j=j+1)begin level=j;next_frame;end
 if(model_level!==255 || frozen===0)$fatal(1,"FAIL VU full scale");
 level=0;next_frame;next_frame;
 if(frozen===0)$fatal(1,"FAIL VU release starts");
 repeat(34)next_frame;
 if(frozen!==0)$fatal(1,"FAIL VU natural decay to black");

 // KEY10 is a strict two-state toggle; DIP disable emits a full black frame,
 // suppresses refresh, and enabling again restores the selected VU mode.
 level=255;next_frame;next_frame;
 en=0;next_frame;
 if(frozen!==0 || !dut.black_sent)$fatal(1,"FAIL DIP-off black frame");
 repeat(100)@(negedge clk);
 if(dut.busy || ws)$fatal(1,"FAIL DIP-off stopped after black frame");
 en=1;next_frame;
 if(frozen===0)$fatal(1,"FAIL VU did not resume after DIP enable");
 key10;next_frame;
 if(frozen!==0 || dut.mode!==1'b0)$fatal(1,"FAIL second KEY10 press did not select off");
 key10;next_frame;
 if(frozen===0 || dut.mode!==1'b1)$fatal(1,"FAIL repeated KEY10 press did not select VU");
 $display("PASS VU level sweep, brightness cap, natural decay, KEY10 off/VU, DIP black frame/resume; frames=%0d",frames);
 $finish;
end
initial begin #100000000;$fatal(1,"FAIL lights watchdog");end
endmodule

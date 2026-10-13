`timescale 1ns/1ps
module tb_ws_vu_only;
reg clk=0,rst_n=0,enable=1,mode_tgl=0;
reg [7:0] level=0;
wire ws_data;
always #10 clk=~clk;

ws2812_effects #(.CLK_FREQ_HZ(1000),.REFRESH_MS(5),.BIT_CYCLES(4),
 .T0H_CYCLES(1),.T1H_CYCLES(2),.RESET_CYCLES(4)) dut
 (.clk(clk),.rst_n(rst_n),.enable(enable),.mode_tgl(mode_tgl),
  .brightness_level(3'd4),.level(level),.mute(1'b0),.ws_data(ws_data));

integer frames=0,bit_count=0,high_count=0,timeout;
reg was_high=0,frame_nonzero=0,last_frame_nonzero=0;
always @(posedge clk) begin
 #1;
 if(!rst_n)begin bit_count=0;high_count=0;was_high=0;frame_nonzero=0;end
 else begin
  if(ws_data)high_count=high_count+1;
  else if(was_high)begin
   if(high_count!=1 && high_count!=2)$fatal(1,"FAIL invalid WS pulse width=%0d",high_count);
   if(high_count==2)frame_nonzero=1;
   bit_count=bit_count+1;high_count=0;
   if(bit_count==192)begin
    frames=frames+1;last_frame_nonzero=frame_nonzero;
    bit_count=0;frame_nonzero=0;
   end
  end
  was_high=ws_data;
 end
end

task wait_frame;
 integer start_frame,guard;
 begin
  start_frame=frames;guard=0;
  while(frames==start_frame && guard<4000)begin @(negedge clk);guard=guard+1;end
  if(frames==start_frame)$fatal(1,"FAIL WS frame timeout");
 end
endtask
task press_key10;
 begin
  mode_tgl=~mode_tgl;repeat(8)@(negedge clk);
 end
endtask

initial begin
 repeat(4)@(negedge clk);rst_n=1;
 wait_frame;
 if(last_frame_nonzero || dut.mode!==1'b0)$fatal(1,"FAIL reset default is not black/off");

 // One press selects VU. Full-scale input must generate a legal nonblack frame.
 level=255;press_key10;
 if(dut.mode!==1'b1)$fatal(1,"FAIL KEY10 did not select VU");
 wait_frame;wait_frame;
 if(!last_frame_nonzero || dut.vu_envelope!==8'hff)$fatal(1,"FAIL full-scale VU frame");

 // Silence naturally decays through the retained envelope to an all-black frame.
 level=0;timeout=0;
 while(dut.vu_envelope!=0 && timeout<40)begin wait_frame;timeout=timeout+1;end
 wait_frame;
 if(dut.vu_envelope!==0 || last_frame_nonzero)$fatal(1,"FAIL zero-input VU decay");

 // DIP6 shutdown must serialize one complete black frame and then go idle.
 level=255;wait_frame;wait_frame;
 if(!last_frame_nonzero)$fatal(1,"FAIL VU did not recover after silence");
 enable=0;wait_frame;
 if(last_frame_nonzero || !dut.black_sent)$fatal(1,"FAIL DIP6 did not send black frame");
 repeat(40)@(negedge clk);
 if(dut.busy || ws_data)$fatal(1,"FAIL DIP6 did not stop after black frame");

 // DIP6 re-enable restores the VU mode; consecutive presses alternate only
 // between VU and off (no third charge/progress state).
 enable=1;wait_frame;
 if(!last_frame_nonzero)$fatal(1,"FAIL VU not restored after DIP6 enable");
 press_key10;wait_frame;
 if(dut.mode!==1'b0 || last_frame_nonzero)$fatal(1,"FAIL KEY10 VU-to-off transition");
 press_key10;wait_frame;
 if(dut.mode!==1'b1 || !last_frame_nonzero)$fatal(1,"FAIL KEY10 off-to-VU transition");
 $display("PASS WS VU-only: reset black, key toggles, full-scale, natural decay, DIP6 black/idle/resume");
 $finish;
end
initial begin #100000000;$fatal(1,"FAIL WS VU-only watchdog");end
endmodule

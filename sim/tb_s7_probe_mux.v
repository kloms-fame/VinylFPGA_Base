`timescale 1ns/1ps
module tb_s7_probe_mux;
 reg clk=0,rst=0,ready=0,audio_req=0;
 reg card_busy=0,card_done=0,card_valid=0;
 wire audio_busy,audio_done,audio_valid,req,busy,valid,done,card_req;
 wire [31:0] lba,card_lba;
 integer probes=0,reads=0,received=0;
 always #5 clk=~clk;
 mv_sector_mux mux(.clk(clk),.rst_n(rst),.audio_req(audio_req),.audio_lba(32'd1234),
  .video_req(1'b0),.video_lba(32'd0),.allow_video(1'b0),
  .audio_busy(audio_busy),.audio_done(audio_done),.audio_valid(audio_valid),
  .sector_req(req),.sector_lba(lba),.sector_busy(busy),.sector_valid(valid),.sector_done(done));
 media_probe #(.IDLE_CYCLES(8)) probe(.clk(clk),.rst_n(rst),.ready(ready),
  .client_req(req),.client_lba(lba),.client_busy(busy),.client_valid(valid),.client_done(done),
  .card_req(card_req),.card_lba(card_lba),.card_busy(card_busy),.card_valid(card_valid),.card_done(card_done));
 always @(posedge clk) if(audio_valid) received=received+1;
 task sector;
  input [31:0] expected;
  begin
   wait(card_req);@(negedge clk);
   if(card_lba!==expected) $fatal(1,"FAIL sector priority got=%d expected=%d",card_lba,expected);
   card_busy=1;card_valid=1;repeat(4) @(negedge clk);
   card_valid=0;card_done=1;@(negedge clk);card_done=0;card_busy=0;
  end
 endtask
 initial begin
  repeat(3) @(negedge clk);rst=1;ready=1;
  // Capture upstream audio ownership on exactly the probe acquisition edge.
  wait(probe.count==7);@(negedge clk);audio_req=1;
  @(negedge clk);audio_req=0;
  sector(0);
  if(received!=0) $fatal(1,"FAIL probe payload reached WAV");
  sector(1234);
  repeat(2) @(negedge clk);
  if(received!=4 || audio_busy) $fatal(1,"FAIL audio request lost after probe");
  // Pending upstream owner immediately before probe threshold wins normally.
  ready=0;@(negedge clk);ready=1;
  wait(probe.count==6);@(negedge clk);audio_req=1;
  @(negedge clk);audio_req=0;
  sector(1234);
  if(received!=8) $fatal(1,"FAIL second audio payload lost");
  $display("PASS mux/probe boundary arbitration and payload isolation");$finish;
 end
 initial begin #10000;$fatal(1,"FAIL mux/probe watchdog");end
endmodule

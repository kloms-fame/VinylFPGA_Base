`timescale 1ns/1ps
// Digital protocol model supplied by sim/tb_mic_adc_capture.v.
module tb_mic_pipeline;
 reg clk=0,rst_n=0, source_valid=0, mute=0;
 wire [11:0] code; wire code_valid; wire signed [15:0] mic;
 wire mic_valid, ready, valid; wire signed [15:0] left,right;
 integer count=0, changed=0, muted=0, timer=0;
 always #20 clk=~clk;
 mic_adc_capture a(clk,rst_n,code,code_valid);
 mic_signal_condition b(clk,rst_n,code,code_valid,mic,mic_valid);
 mic_pcm_mixer #(.RAMP_INTERVAL(1)) c(
      .clk(clk), .rst_n(rst_n), .in_valid(source_valid), .in_ready(ready),
      .in_left(16'sd1000), .in_right(16'sd1000), .mic_sample(mic),
      .mic_valid(mic_valid), .mic_enable(1'b1), .mic_gain_max(8'd128),
      .mute(mute), .out_valid(valid), .out_ready(1'b1),
      .out_left(left), .out_right(right));
 always @(negedge clk) if(rst_n) begin
   timer=timer+1;
   source_valid = timer%521 == 0;
   if(valid) begin
     count=count+1;
     if(!mute && left != 1000 && right == left) changed=changed+1;
     if(mute && left == 0 && right == 0) muted=muted+1;
   end
 end
 initial begin
   repeat(4) @(negedge clk); rst_n=1;
   repeat(100000) @(negedge clk);
   if(changed < 20) $fatal(1,"no microphone contribution: %d",changed);
   mute=1;
   repeat(2000) @(negedge clk);
   if(muted < 2) $fatal(1,"global mute missing");
   $display("PASS digital ADC to mixer path: frames=%0d changed=%0d muted=%0d",count,changed,muted);
   $finish;
 end
endmodule

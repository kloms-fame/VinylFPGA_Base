`timescale 1ns/1ps
module tb_mic_signal_condition;
 reg clk=0,rst_n=0,valid=0; reg [11:0] code=2048;
 wire signed [15:0] sample; wire ready;
 mic_signal_condition d(clk,rst_n,code,valid,sample,ready);
 always #5 clk=~clk;
 task push(input [11:0] value);
 begin @(negedge clk); code=value; valid=1; @(negedge clk); valid=0; end endtask
 initial begin
   repeat(2) @(negedge clk); rst_n=1;
   push(2048); push(2048); if(ready) $fatal(1,"early output");
   push(2048); if(!ready || sample != 0) $fatal(1,"zero center");
   push(3072); push(3072); push(3072);
   if(sample < 11000 || sample > 13000) $fatal(1,"positive sample %d",sample);
   repeat(39999) push(3072);
   if(sample > 40 || sample < -40) $fatal(1,"DC not removed %d",sample);
   push(1024); push(1024); push(1024);
   if(sample > -20000) $fatal(1,"negative response %d",sample);
   repeat(39999) push(4095);
   push(0); push(0); push(0);
   if(sample !== -16'sd32768) $fatal(1,"negative clipping %d",sample);
   repeat(4100) @(negedge clk);
   if(ready || sample) $fatal(1,"ADC timeout must mute stale data");
   rst_n=0; @(negedge clk); if(ready || sample) $fatal(1,"reset");
   $display("PASS mic conditioning: decimation, DC rejection, polarity, reset"); $finish;
 end
endmodule

`timescale 1ns/1ps
module tb_audit_progress;
reg clk=0; always #20 clk=~clk;
reg rst_n=0,vs=1; reg [31:0] elapsed=0,total=480000;
wire [7:0] fill; wire [103:0] time_ascii;wire known;
playback_progress dut(clk,rst_n,vs,elapsed,total,fill,time_ascii,known);
task probe; input [31:0] value;input [7:0] expected; begin
@(negedge clk);elapsed=value;vs=1;repeat(2) @(negedge clk);vs=0;
repeat(300) @(negedge clk);
$display("elapsed=%0d total=%0d fill=%0d intended=%0d",elapsed,total,fill,expected);
end endtask
initial begin repeat(5) @(negedge clk);rst_n=1;probe(0,0);probe(240000,120);probe(480000,240);$finish;end
endmodule

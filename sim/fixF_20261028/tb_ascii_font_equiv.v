`timescale 1ns/1ps
module tb_ascii_font_equiv;
reg clk=0;reg [9:0] addr=0;wire [7:0] actual,expected;
always #5 clk=~clk;
ascii_font_rom dut(.clk(clk),.addr(addr),.dout(actual));
ascii_font_ref refrom(.clk(clk),.addr(addr),.dout(expected));
integer i;
initial begin
 for(i=0;i<1024;i=i+1) begin
  @(negedge clk);addr=i;@(posedge clk);#1;
  if(actual!==expected) $fatal(1,"font mismatch address=%0d got=%h expected=%h",i,actual,expected);
 end
 $display("PASS all 1024 font addresses and synchronous latency");$finish;
end
endmodule

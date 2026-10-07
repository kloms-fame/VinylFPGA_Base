`timescale 1ns/1ps
module tb_x1x2_display;
reg clk=0,rst=0,en=1;reg [31:0] samples=0;reg[1:0] song=0;
reg debug_enable=0;reg[3:0]flags=0;reg[7:0]error_code=0;
wire [7:0] d0,d1,d2,d3,d4,d5,d6,d7,sel,data;
always #5 clk=~clk;
seg_business_mux dut(.debug_enable(debug_enable),.fault_flags(flags),.error_code(error_code),.clk(clk),.rst_n(rst),.display_enable(en),.sample_position(samples),.song_index(song),
 .seg_data_0(d0),.seg_data_1(d1),.seg_data_2(d2),.seg_data_3(d3),.seg_data_4(d4),.seg_data_5(d5),.seg_data_6(d6),.seg_data_7(d7));
seg_scan #(.SCAN_COUNT(10)) scan(.clk(clk),.rst_n(rst),.seg_sel(sel),.seg_data(data),
 .seg_data_0(d0),.seg_data_1(d1),.seg_data_2(d2),.seg_data_3(d3),.seg_data_4(d4),.seg_data_5(d5),.seg_data_6(d6),.seg_data_7(d7));
function [7:0] digit;input integer n;begin
 case(n) 0:digit=8'hc0;1:digit=8'hf9;2:digit=8'ha4;3:digit=8'hb0;4:digit=8'h99;
 5:digit=8'h92;6:digit=8'h82;7:digit=8'hf8;8:digit=8'h80;9:digit=8'h90;default:digit=8'hff;endcase
end endfunction
task check;input integer seconds,index;reg[63:0] expected;begin
 @(negedge clk);samples=seconds*48000;song=index;repeat(600)@(negedge clk);
 expected={digit((seconds/60)/10),digit((seconds/60)%10),8'hbf,digit((seconds%60)/10),digit(seconds%10),8'hff,8'hc0,digit(index+1)};
 if({d0,d1,d2,d3,d4,d5,d6,d7}!==expected)$fatal(1,"FAIL display sec=%0d got=%h expected=%h",seconds,{d0,d1,d2,d3,d4,d5,d6,d7},expected);
end endtask
integer i;reg[7:0] seen=0;
initial begin
 repeat(4)@(negedge clk);rst=1;check(0,0);check(125,2);check(127,2);check(122,2);check(0,2);check(5999,3);
 samples=32'hffffffff;repeat(600)@(negedge clk);if({d0,d1,d3,d4}!==32'h90909290)$fatal(1,"FAIL saturation");
 for(i=0;i<100;i=i+1)begin @(negedge clk);seen=seen|~sel;if(sel!=255 && ((~sel & ((~sel)-8'd1)) & 8'hff)!=0)$fatal(1,"FAIL multiple selected");end
 if(seen!=255)$fatal(1,"FAIL missing physical digits");
 debug_enable=1;error_code=8'h34;flags=4'h7;#1;
 if({d0,d1,d2,d3,d4}!==40'h86b0998ef8)$fatal(1,"FAIL diagnostic error/flags display %h",{d0,d1,d2,d3,d4});
 error_code=0;flags=0;#1;
 if({d0,d1,d2,d3,d4}!==40'h86c0c08ec0)$fatal(1,"FAIL diagnostic clear");
 en=0;#1;if({d0,d1,d2,d3,d4,d5,d6,d7}!==64'hffffffffffffffff)$fatal(1,"FAIL display off");
 $display("PASS eight digits MM-SS blank NN, seek/replay/saturation and full scan");$finish;
end
endmodule

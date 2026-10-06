`timescale 1ns/1ps
module tb_s7_browse_semantics;
 reg clk=0,rst=0,cf=0,md=0,playing=0;
 wire grid;
 always #5 clk=~clk;
 browse_fsm dut(.clk(clk),.rst_n(rst),.ev_prev_tgl(1'b0),.ev_next_tgl(1'b0),
 .ev_home_tgl(1'b0),.ev_confirm_tgl(cf),.ev_mode_tgl(md),.mb_next(1'b0),.mb_mode(1'b0),
 .mb_left(1'b0),.mb_confirm(1'b0),.view_mode(1'b0),.mode_play(playing),.thumb_mode(grid));
 always @(negedge clk) if(rst && grid) $fatal(1,"FAIL confirm/home or PLAY mode event must not open grid");
 initial begin
 repeat(4) @(negedge clk); rst=1; cf=1;
 repeat(10) @(negedge clk); playing=1; md=1;
 repeat(10) @(negedge clk);
 $display("PASS browse confirms without grid and PLAY KEY7 single consumer"); $finish;
 end
endmodule

`timescale 1ns/1ps
module tb_s7_encoder;
 reg clk=0,rst=0,valid=0;reg[15:0]count=0,aux=0;
 wire cw,ccw;reg oldcw=0,oldccw=0;integer net=0;
 always #10 clk=~clk;
 ui_event_bridge dut(.clk(clk),.rst_n(rst),.ev_valid(valid),.ev_code(4'd4),
 .ev_arg(count),.ev_aux(aux),.next_tgl(cw),.prev_tgl(ccw));
 always @(negedge clk) if(rst) begin
 if(cw!=oldcw)net=net+1;if(ccw!=oldccw)net=net-1;oldcw=cw;oldccw=ccw;
 end
 task send;input[15:0]v;input d;begin
 @(negedge clk);valid=1;count=v;aux={15'd0,d};
 @(negedge clk);valid=0;repeat(100)@(negedge clk);
 end endtask
 initial begin
 repeat(4)@(negedge clk);rst=1;send(1,0);send(5,0);
 if(net!=5)$fatal(1,"FAIL coalesced encoder count lost steps net=%d",net);
 send(1,1);send(16'hffff,1);
 if(net!=-1)$fatal(1,"FAIL signed encoder reverse/wrap net=%d",net);
 $display("PASS coalesced encoder delta, reversal and 16-bit wrap");$finish;
 end
endmodule

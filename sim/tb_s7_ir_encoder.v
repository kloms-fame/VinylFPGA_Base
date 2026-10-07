`timescale 1ns/1ps
module tb_s7_ir_encoder;
 reg clk=0,rst=0,valid=0;reg [3:0]code=0;reg[15:0]arg=0,aux=0;
 reg[5:0]dip=6'b010001;
 wire cv;wire[3:0]cc;wire[15:0]ca,cx;wire cw,ccw;
 reg oldcw=0,oldccw=0;integer net=0;
 always #10 clk=~clk;
 ui_command_router router(.clk(clk),.rst_n(rst),.ev_valid(valid),.ev_code(code),
  .ev_arg(arg),.ev_aux(aux),.dip_level(dip),.cmd_valid(cv),.cmd_code(cc),.cmd_arg(ca),.cmd_aux(cx));
 ui_event_bridge bridge(.clk(clk),.rst_n(rst),.ev_valid(cv),.ev_code(cc),
  .ev_arg(ca),.ev_aux(cx),.next_tgl(cw),.prev_tgl(ccw));
 always @(negedge clk) if(rst) begin
  if(cw!=oldcw)net=net+1;if(ccw!=oldccw)net=net-1;oldcw=cw;oldccw=ccw;
 end
 task send;input[3:0]c;input[15:0]a,x;begin
  @(negedge clk);valid=1;code=c;arg=a;aux=x;
  @(negedge clk);valid=0;repeat(100)@(negedge clk);
 end endtask
 initial begin
  repeat(4)@(negedge clk);rst=1;
  send(6,16'h00ff,16'hb946);send(6,16'h00ff,16'hb946);
  if(net!=2)$fatal(1,"FAIL repeated IR next");
  send(4,1,0);send(4,5,0);
  if(net!=7)$fatal(1,"FAIL encoder count after IR");
  send(6,16'h00ff,16'hb946);
  if(net!=8)$fatal(1,"FAIL IR next reversed encoder");
  send(6,16'h00ff,16'hba45);send(6,16'h00ff,16'hba45);
  if(net!=6)$fatal(1,"FAIL repeated IR previous");
  send(4,4,1);if(net!=5)$fatal(1,"FAIL IR modified encoder origin");
  dip[4]=0;send(6,16'h00ff,16'hb946);
  if(net!=5)$fatal(1,"FAIL DIP5 off");
  dip[4]=1;send(6,16'h00fe,16'hb946);
  if(net!=5)$fatal(1,"FAIL invalid IR complement accepted");
  $display("PASS repeated IR/encoder mixing, DIP5 and complement filtering");$finish;
 end
endmodule

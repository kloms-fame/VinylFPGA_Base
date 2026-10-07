`timescale 1ns/1ps
module tb_x1x2_input_repair;
reg clk=0,rst=0,valid=0;reg[3:0]code=0;reg[15:0]arg=0,aux=0;
wire cv;wire[3:0]cc;wire[15:0]ca,cx;wire cw,ccw,f2,b2,f5,b5;
always #10 clk=~clk;
ui_command_router router(.clk(clk),.rst_n(rst),.ev_valid(valid),.ev_code(code),
 .ev_arg(arg),.ev_aux(aux),.dip_level(6'b010001),.cmd_valid(cv),.cmd_code(cc),.cmd_arg(ca),.cmd_aux(cx));
ui_event_bridge bridge(.clk(clk),.rst_n(rst),.ev_valid(cv),.ev_code(cc),.ev_arg(ca),.ev_aux(cx),
 .enc_cw_tgl(cw),.enc_ccw_tgl(ccw),.seek_fwd2_tgl(f2),.seek_bwd2_tgl(b2),.seek_fwd5_tgl(f5),.seek_bwd5_tgl(b5));
task send;input[3:0]c;input[15:0]a,x;begin
 @(negedge clk);valid=1;code=c;arg=a;aux=x;@(negedge clk);valid=0;repeat(40)@(negedge clk);
end endtask
initial begin
 repeat(4)@(negedge clk);rst=1;
 send(4,1,0);
 if(cw!==0 || f2!==1)$fatal(1,"FAIL EC1 must seek, not change track");
 send(4,0,1);if(ccw!==0 || b2!==1)$fatal(1,"FAIL EC1 reverse seek");
 send(4,1,2);if(f2!==1)$fatal(1,"FAIL EC2 reserved");
 send(1,2,0);if(cw!==1)$fatal(1,"FAIL KEY03 next track");
 send(1,0,0);if(ccw!==1)$fatal(1,"FAIL KEY01 previous track");
 send(6,16'h00ff,16'hea15);if(f5!==1 || b5!==0)$fatal(1,"FAIL IR plus EA");
 send(6,16'h00ff,16'hf807);if(b5!==1)$fatal(1,"FAIL IR minus F8");
 $display("PASS EC1 seek EC2 reserved and IR polarity");$finish;
end
endmodule

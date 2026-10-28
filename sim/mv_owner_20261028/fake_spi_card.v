`timescale 1ns/1ps
// Byte-level replacement for spi_master, not a replacement for the real
// sd_card_top/CMD17/CMD18/command engines. Models init, tokens, CRC, CMD12
// stuff byte and R1b. No force of DUT states or acknowledgments.
module spi_master(input sys_clk,rst,input [15:0] clk_div,input CPOL,CPHA,
 input nCS_ctrl,wr_req,input [7:0] data_in,input MISO,
 output nCS,DCLK,MOSI,output reg wr_ack,output reg [7:0] data_out);
 assign nCS=nCS_ctrl;
 assign DCLK=CPOL;
 assign MOSI=1'b1;
 integer cooldown=0,cmd_idx=0,op=0,mode=0,idx=0,sec=0;
 integer cmd17_count=0,cmd18_count=0,cmd12_count=0;
 integer busy_left=0,token_delay=0;
 integer byte_delay=2,stall_op=-1,hold_busy=0;
 reg [31:0] address=0;
 reg strict_stop=0,stop_stuff=0;
 always @(posedge sys_clk) begin
  if(rst) begin
   wr_ack<=0; data_out<=8'hff; cooldown<=0;cmd_idx<=0;op<=0;
   mode<=0;idx<=0;sec<=0;address<=0;busy_left<=0;
   cmd17_count<=0;cmd18_count<=0;cmd12_count<=0;stop_stuff<=0;
  end else begin
   wr_ack<=0;
   if(cooldown!=0) cooldown<=cooldown-1;
   else if(wr_req && !wr_ack) begin
    wr_ack<=1;cooldown<=byte_delay;data_out<=8'hff;
    if(nCS_ctrl) begin
     cmd_idx<=0;mode<=0;
    end else if(cmd_idx==0 && data_in[7:6]==2'b01) begin
     op<=data_in[5:0];cmd_idx<=1;address<=0;mode<=0;
     // On CMD12 MISO still carries data while the command is sent.
     if(strict_stop && data_in[5:0]==12) data_out<=8'h23;
    end else if(cmd_idx!=0) begin
     if(cmd_idx<=5) begin
      if(cmd_idx<5) address<={address[23:0],data_in};
      cmd_idx<=cmd_idx+1;
      if(strict_stop && op==12) data_out<=8'h23;
     end else if(op==stall_op) begin
      data_out<=8'hff;
     end else if(op==12 && strict_stop && !stop_stuff) begin
      data_out<=8'h04;stop_stuff<=1;
     end else begin
      cmd_idx<=0;idx<=0;sec<=0;stop_stuff<=0;
      case(op)
       0,8,55: data_out<=8'h01;
       default: data_out<=8'h00;
      endcase
      case(op)
       8: mode<=4;
       17: begin mode<=1;cmd17_count<=cmd17_count+1;end
       18: begin mode<=1;cmd18_count<=cmd18_count+1;end
       12: begin mode<=3;busy_left<=3;cmd12_count<=cmd12_count+1;end
       default: mode<=0;
      endcase
     end
    end else case(mode)
     1: if(token_delay>0) token_delay<=token_delay-1;
        else begin data_out<=8'hfe;mode<=2;idx<=0;end
     2: begin
      if(idx<512) begin data_out<=(address[7:0]+sec[7:0])^idx[7:0];idx<=idx+1;end
      else if(idx<514) begin data_out<=0;idx<=idx+1;end
      else begin sec<=sec+1;idx<=0;mode<=(op==18)?1:0;end
     end
     3: if(hold_busy!=0) data_out<=0;
        else if(busy_left>0) begin data_out<=0;busy_left<=busy_left-1;end
        else begin data_out<=8'hff;mode<=0;end
     4: begin idx<=idx+1;if(idx==3) mode<=0;end
    endcase
   end
  end
 end
endmodule

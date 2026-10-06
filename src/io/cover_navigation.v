`ifndef VINYL_COVER_NAVIGATION_V
`define VINYL_COVER_NAVIGATION_V
// SD-domain target accumulator. User steps during a transition update desired;
// each in-flight bank is held until select_ack, never overwritten or dropped.
module cover_navigation (
 input wire clk,rst_n,ready,
 input wire [2:0] count, input wire [1:0] displayed,
 input wire next_step,prev_step,choose,
 input wire [1:0] chosen, input wire chosen_direction,
 input wire transition_busy,transition_commit,select_ack,
 output reg transition_start,output reg direction,
 output reg select_req,output reg [1:0] select_index,
 output wire busy
);
 reg [1:0] desired,displayed_prev;
 reg active,committed,desired_dir;
 wire external_change=!active && !transition_busy && displayed!=displayed_prev;
 wire [1:0] last_index=(count==0)?2'd0:count-1'b1;
 wire [1:0] next_index=(desired>=last_index)?2'd0:desired+1'b1;
 wire [1:0] prev_index=(desired==0)?last_index:desired-1'b1;
 assign busy=active || transition_busy || desired!=displayed;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   desired<=0; displayed_prev<=0; active<=0; committed<=0; transition_start<=0;
   select_req<=0; select_index<=0; direction<=1; desired_dir<=1;
  end else begin
   transition_start<=0;
   displayed_prev<=displayed;
   if(!ready) begin
    desired<=displayed; active<=0; committed<=0; select_req<=0;
   end else begin
    if(external_change) desired<=displayed;
    if(choose) begin desired<=chosen; desired_dir<=chosen_direction; end
    else if(next_step) begin desired<=next_index; desired_dir<=1; end
    else if(prev_step) begin desired<=prev_index; desired_dir<=0; end
    if(!active && !transition_busy && desired!=displayed && !external_change) begin
     select_index<=desired; transition_start<=1; active<=1; committed<=0;
     direction<=desired_dir;
    end
    if(active && transition_commit && !committed) begin select_req<=1; committed<=1; end
    if(select_req && select_ack) select_req<=0;
    if(active && committed && !select_req && !transition_busy && displayed==select_index)
     active<=0;
   end
  end
 end
endmodule
`endif

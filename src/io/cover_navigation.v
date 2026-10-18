`ifndef VINYL_COVER_NAVIGATION_V
`define VINYL_COVER_NAVIGATION_V
// SD-domain target accumulator. User steps during a transition update desired;
// each in-flight bank is held until select_ack, never overwritten or dropped.
module cover_navigation (
 input wire clk,rst_n,ready,
 input wire [2:0] count, input wire [1:0] displayed,
 input wire next_step,prev_step,auto_next,choose,
 input wire [1:0] chosen, input wire chosen_direction,
 input wire transition_busy,transition_commit,select_ack,
 output reg transition_start,output reg direction,
 output reg select_req,output reg [1:0] select_index,
 output wire busy,output wire auto_switch_ack
);
 reg [1:0] desired,displayed_prev;
 reg active,committed,desired_dir,auto_pending,auto_transition,manual_pending;
 wire external_change=!active && !transition_busy && displayed!=displayed_prev;
 wire transaction_launch=ready && !active && !transition_busy && desired!=displayed && !external_change;
 wire transaction_done=active && committed && !select_req && !transition_busy && displayed==select_index;
 wire [1:0] last_index=(count==0)?2'd0:count-1'b1;
 wire [1:0] next_index=(desired>=last_index)?2'd0:desired+1'b1;
 wire [1:0] prev_index=(desired==0)?last_index:desired-1'b1;
 wire [1:0] displayed_next=(displayed>=last_index)?2'd0:displayed+1'b1;
 wire [1:0] displayed_prev_index=(displayed==0)?last_index:displayed-1'b1;
 assign busy=active || transition_busy || desired!=displayed;
 assign auto_switch_ack=select_req && select_ack && auto_transition;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   desired<=0; displayed_prev<=0; active<=0; committed<=0; transition_start<=0;
   select_req<=0; select_index<=0; direction<=1; desired_dir<=1;
   auto_pending<=0; auto_transition<=0; manual_pending<=0;
  end else begin
   transition_start<=0;
   displayed_prev<=displayed;
   if(!ready) begin
    desired<=displayed; active<=0; committed<=0; select_req<=0;
    auto_pending<=0; auto_transition<=0;
    // Keep one early manual browse step until the scan supplies a valid count.
    if(next_step || prev_step) begin
     manual_pending<=1;
     desired_dir<=next_step;
    end
   end else begin
    if(external_change) desired<=displayed;
    if(choose) begin desired<=chosen; desired_dir<=chosen_direction; manual_pending<=0; end
    else if(manual_pending) begin
     desired<=desired_dir ? displayed_next : displayed_prev_index;
     if(next_step || prev_step) begin
      manual_pending<=1;
      desired_dir<=next_step;
     end else manual_pending<=0;
    end
    else if(next_step) begin desired<=next_index; desired_dir<=1; end
    else if(prev_step) begin desired<=prev_index; desired_dir<=0; end
    else if(auto_next) begin desired<=next_index; desired_dir<=1; end
    if(choose || next_step || prev_step) auto_pending<=0;
    else if(auto_next) auto_pending<=1;
    else if(transaction_launch) auto_pending<=0;
    if(!active && !transition_busy && desired!=displayed && !external_change) begin
     select_index<=desired; transition_start<=1; active<=1; committed<=0;
     direction<=desired_dir; auto_transition<=auto_pending;
    end
    if(active && transition_commit && !committed) begin select_req<=1; committed<=1; end
    if(select_req && select_ack) select_req<=0;
    if(transaction_done) begin active<=0; auto_transition<=0; end
   end
  end
 end
endmodule
`endif

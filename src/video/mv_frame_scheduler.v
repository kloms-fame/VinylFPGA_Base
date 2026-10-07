`ifndef VINYL_MV_FRAME_SCHEDULER_V
`define VINYL_MV_FRAME_SCHEDULER_V
// video_clk. One held-data request/ack mailbox, cyclic SDRAM slots 0/1/2.
// May prefetch one frame; only an acknowledged, due frame can be displayed.
// Slow storage freezes the displayed slot and then skips to the audio timeline.
module mv_frame_scheduler (
 input wire clk, rst_n, frame_start, enable, paused, restart,
 input wire [31:0] time_ms, start_lba,
 input wire [15:0] frame_count,
 input wire [15:0] seek_frame,      // X2：Seek 定位目标帧（顶层按样本换算）
 input wire done_toggle, failed,
 output reg request_toggle, output reg [31:0] request_lba,
 output reg [1:0] request_bank,
 output reg display_valid, output reg [1:0] display_bank,
 output reg [15:0] display_frame,
 output wire waiting
);
 reg [2:0] done_sync;
 reg [1:0] fail_sync;
 reg busy, discard, first_frame;
 reg clear_pending;
 wire show_ready;
 reg [15:0] requested_frame, target_frame;
 reg [31:0] next_time;
 reg [3:0] settle;
 // X2：restart/invalidate 期间把播放位置直接落到目标帧，而不是从 0 重新数。
 wire [15:0] rst_frame = (frame_count == 16'd0) ? 16'd0 :
                         ((seek_frame >= frame_count) ? (frame_count - 16'd1) : seek_frame);
 wire [31:0] rst_next_time = ({16'd0, rst_frame} * 32'd100) + 32'd100;
 wire completed = busy && (done_sync[2]==request_toggle);
 wire invalidating = !enable || restart;
 wire can_issue = enable && !paused && !restart && settle==4'd15 && !busy &&
                  frame_count!=0 && (first_frame || display_frame+16'd1<frame_count);
 wire [15:0] next_frame = first_frame ? target_frame :
                         ((target_frame>display_frame) ? target_frame : display_frame+16'd1);
 assign waiting = busy;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) done_sync<=0; else done_sync<={done_sync[1:0],done_toggle};
 end
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) fail_sync<=0; else fail_sync<={fail_sync[0],failed};
 end
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) settle<=0;
  else if(invalidating) settle<=0;
  else if(settle!=15) settle<=settle+1'b1;
 end
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) target_frame<=0;
  else if(invalidating) target_frame<=rst_frame;
  else if(!paused && time_ms>=next_time && target_frame+16'd1<frame_count) target_frame<=target_frame+1'b1;
 end
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) next_time<=100;
  else if(invalidating) next_time<=rst_next_time;
  else if(!paused && time_ms>=next_time && target_frame+16'd1<frame_count) next_time<=next_time+32'd100;
 end
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) busy<=0;
  else if(completed && (discard || invalidating || fail_sync[1] ||
          (frame_start && show_ready))) busy<=0;
  else if(can_issue) busy<=1;
 end
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) discard<=0;
  else if(busy && invalidating) discard<=1;
  else if(!busy) discard<=0;
 end
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) request_toggle<=0;
  else if(can_issue) request_toggle<=~request_toggle;
 end
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) request_lba<=0;
  else if(can_issue) request_lba<=start_lba + (next_frame * 32'd300);
 end
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) request_bank<=0;
  else if(can_issue) request_bank<=(display_bank==2) ? 0 : display_bank+1'b1;
 end
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) requested_frame<=0;
  else if(can_issue) requested_frame<=next_frame;
 end
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) first_frame<=1;
  else if(invalidating) first_frame<=1;
  else if(frame_start && show_ready) first_frame<=0;
 end
 // The visible bank, valid and frame number ONLY change in vertical blank.
 // A restart between frame boundaries invalidates in-flight data via discard.
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) clear_pending<=0;
  else if(invalidating) clear_pending<=1;
  else if(frame_start) clear_pending<=0;
 end
 assign show_ready = completed && !discard && !invalidating && !clear_pending &&
                   !paused && !fail_sync[1] && requested_frame<=target_frame;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) display_valid<=0;
  else if(frame_start) begin
   if(invalidating || clear_pending) display_valid<=0;
   else if(show_ready) display_valid<=1;
  end
 end
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) display_bank<=0;
  else if(frame_start && show_ready) display_bank<=request_bank;
 end
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) display_frame<=0;
  else if(frame_start && show_ready) display_frame<=requested_frame;
 end
endmodule
`endif

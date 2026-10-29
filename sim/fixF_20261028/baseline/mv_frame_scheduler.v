`ifndef VINYL_MV_FRAME_SCHEDULER_V
`define VINYL_MV_FRAME_SCHEDULER_V
// video_clk. One bank is displayed, one completed bank may wait for vblank,
// and the third bank can be written concurrently. Display commits only at
// frame_start; stale completed frames are skipped to the audio timeline.
module mv_frame_scheduler (
 input wire clk, rst_n, frame_start, enable, paused, restart,
 input wire [31:0] time_ms, start_lba,
 input wire [15:0] frame_count,
 input wire [15:0] seek_frame,
 input wire done_toggle, failed,
 input wire retain_display,
 output reg request_toggle, output reg [31:0] request_lba,
 output reg [1:0] request_bank,
 output reg display_valid, output reg [1:0] display_bank,
 output reg [15:0] display_frame,
 output wire waiting
);
 reg [2:0] done_sync;
 reg [1:0] fail_sync;
 reg busy, discard, first_frame, pending_valid;
 reg [1:0] pending_bank;
 reg [15:0] pending_frame;
 reg clear_pending;
 reg [15:0] requested_frame, target_frame;
 reg [31:0] next_time;
 reg [3:0] settle;
 wire [15:0] rst_frame = (frame_count == 16'd0) ? 16'd0 :
                         ((seek_frame >= frame_count) ? (frame_count - 16'd1) : seek_frame);
 wire [31:0] rst_frame_x100 = {10'd0, rst_frame, 6'b0} +
                              {11'd0, rst_frame, 5'b0} + {14'd0, rst_frame, 2'b0};
 wire [31:0] rst_next_time = rst_frame_x100 + 32'd100;
 wire completed = busy && (done_sync[2]==request_toggle);
 wire invalidating = !enable || restart;
 wire [15:0] next_frame = first_frame ?
     ((pending_valid && target_frame<=pending_frame) ? pending_frame+16'd1 : target_frame) :
     ((pending_valid && pending_frame>display_frame) ?
       ((target_frame>pending_frame) ? target_frame : pending_frame+16'd1) :
       ((target_frame>display_frame) ? target_frame : display_frame+16'd1));
 wire bank0_free = display_bank!=2'd0 && (!pending_valid || pending_bank!=2'd0);
 wire bank1_free = display_bank!=2'd1 && (!pending_valid || pending_bank!=2'd1);
 wire [1:0] next_bank = bank0_free ? 2'd0 : (bank1_free ? 2'd1 : 2'd2);
 wire pending_due = pending_valid && pending_frame<=target_frame;
 wire completed_due = completed && !discard && !invalidating && !fail_sync[1] &&
                      requested_frame<=target_frame;
 wire show_pending = pending_due && !completed_due;
 wire show_ready = !invalidating && !discard && !clear_pending &&
                   (!paused || first_frame) &&
                   (pending_due || completed_due);
 // The completed writer is the third occupied bank. Keep its mailbox parked
 // while an older future frame is pending; it may be retired only when there
 // is queue room or the newer completion is already due on the audio clock.
 wire retire_complete = completed && (discard || invalidating || fail_sync[1] ||
                         !pending_valid || completed_due || (frame_start && show_ready));
 wire can_issue = enable && (!paused || first_frame) && !restart && settle==4'd15 &&
                  !busy && !(first_frame && pending_valid) &&
                  frame_count!=0 && next_frame<frame_count &&
                  (bank0_free || bank1_free ||
                   (display_bank!=2'd2 && (!pending_valid || pending_bank!=2'd2)));
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
  else if(!paused && time_ms>=next_time && target_frame+16'd1<frame_count)
   target_frame<=target_frame+1'b1;
 end
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) next_time<=100;
  else if(invalidating) next_time<=rst_next_time;
  else if(!paused && time_ms>=next_time && target_frame+16'd1<frame_count)
   next_time<=next_time+32'd100;
 end
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) busy<=0;
  else if(retire_complete) busy<=0;
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
  else if(can_issue) request_bank<=next_bank;
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
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) clear_pending<=0;
  else if(invalidating) clear_pending<=1;
  else if(frame_start) clear_pending<=0;
 end
 // Completed writes release the SD/SDRAM writer immediately. Their bank stays
 // reserved until either selected for display or superseded by a newer frame.
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin pending_valid<=0;pending_bank<=0;pending_frame<=0;end
  else if(invalidating) pending_valid<=0;
  else if(retire_complete && !discard && !fail_sync[1]) begin
   if(frame_start && show_ready && completed_due && !show_pending)
    pending_valid<=0;
   else begin
    pending_valid<=1;pending_bank<=request_bank;pending_frame<=requested_frame;
   end
  end else if(frame_start && show_ready) pending_valid<=0;
 end
 // The visible bank, valid and frame number change only in vertical blank.
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) display_valid<=0;
  else if(frame_start) begin
   if((invalidating || clear_pending) && !retain_display) display_valid<=0;
   else if(show_ready) display_valid<=1;
  end
 end
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) display_bank<=0;
  else if(frame_start && show_ready)
   display_bank<=completed_due && !show_pending ? request_bank : pending_bank;
 end
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) display_frame<=0;
  else if(frame_start && show_ready)
   display_frame<=completed_due && !show_pending ? requested_frame : pending_frame;
 end
endmodule
`endif

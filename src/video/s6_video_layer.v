`ifndef VINYL_S6_VIDEO_LAYER_V
`define VINYL_S6_VIDEO_LAYER_V
// Pixel-domain S6 binding. All visible choices and phase commit at frame_start.
module s6_video_layer #(
 parameter ENABLE=1
)(
 input wire clk,rst_n,frame_start,play_active,paused,restart,diagnostic,
 input wire covers_ready, input wire [63:0] metadata_async,
 input wire [31:0] time_ms, input wire visual_toggle,
 input wire raw_read_en, out_de, input wire [9:0] out_x,
 input wire adjusted_de, input wire [9:0] adjusted_x,
 input wire [23:0] rgb_in, output wire [23:0] rgb_out,
 output reg mv_read_active, output wire [1:0] mv_read_bank,
 output wire fifo_read_allowed, output wire mv_window_visible,
 output wire request_toggle, output wire [31:0] request_lba,
 output wire [1:0] request_bank, input wire done_toggle,failed
);
 reg [63:0] meta1,meta2;
 reg [2:0] visual_sync;
 reg visual_pending,prefer_vinyl,play_frame;
 reg [7:0] phase_frame;
 reg [9:0] raw_x,raw_y,out_y,adj_y;
 reg raw_q,out_q,adj_q;
 wire visual_event=visual_sync[2]^visual_sync[1];
 wire [32:0] mv_end_lba={1'b0,meta2[31:0]} + (meta2[47:32]*33'd300);
 wire mv_meta_valid=(meta2[63:56]==8'd1 && meta2[55:48]==8'd10 &&
                     meta2[47:32]!=0 && meta2[31:0]!=0 && !mv_end_lba[32]);
 wire schedule_enable=ENABLE && play_active && covers_ready && mv_meta_valid && !diagnostic;
 wire display_valid;
 wire [15:0] display_frame;
 wire waiting;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) meta1<=0; else meta1<=metadata_async;
 end
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) meta2<=0; else meta2<=meta1;
 end
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) visual_sync<=0; else visual_sync<={visual_sync[1:0],visual_toggle};
 end
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) visual_pending<=0;
  else if(!play_active) visual_pending<=0;
  else if(frame_start) visual_pending<=0;
  else if(visual_event) visual_pending<=~visual_pending;
 end
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) prefer_vinyl<=0;
  else if(frame_start && play_active && (visual_pending^visual_event)) prefer_vinyl<=~prefer_vinyl;
 end
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) play_frame<=0;
  else if(frame_start) play_frame<=ENABLE && play_active && !diagnostic;
 end
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) phase_frame<=0;
  else if(frame_start) phase_frame<=time_ms[10:3];
 end
 // Scheduler display bank changes on this same edge; use the previous ready
 // bank for one extra video frame on first acquisition only (no torn frame).
 // Bank selection itself is wired from scheduler and settles before read_req.
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) mv_read_active<=0;
  else if(frame_start) mv_read_active<=schedule_enable && !restart && display_valid &&
       !(prefer_vinyl ^ (play_active && (visual_pending^visual_event)));
 end
 mv_frame_scheduler scheduler(
  .clk(clk),.rst_n(rst_n),.frame_start(frame_start),.enable(schedule_enable),
  .paused(paused),.restart(restart),.time_ms(time_ms),.start_lba(meta2[31:0]),
  .frame_count(meta2[47:32]),.done_toggle(done_toggle),.failed(failed),
  .request_toggle(request_toggle),.request_lba(request_lba),.request_bank(request_bank),
  .display_valid(display_valid),.display_bank(mv_read_bank),.display_frame(display_frame),.waiting(waiting));
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) raw_q<=0; else raw_q<=raw_read_en;
 end
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) out_q<=0; else out_q<=out_de;
 end
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) adj_q<=0; else adj_q<=adjusted_de;
 end
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) raw_x<=0;
  else if(!raw_read_en) raw_x<=0;
  else raw_x<=raw_x+1'b1;
 end
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) raw_y<=0;
  else if(frame_start) raw_y<=0;
  else if(raw_q && !raw_read_en) raw_y<=raw_y+1'b1;
 end
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) out_y<=0;
  else if(frame_start) out_y<=0;
  else if(out_q && !out_de) out_y<=out_y+1'b1;
 end
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) adj_y<=0;
  else if(frame_start) adj_y<=0;
  else if(adj_q && !adjusted_de) adj_y<=adj_y+1'b1;
 end
 assign fifo_read_allowed=!mv_read_active || (raw_x>=16 && raw_x<336 && raw_y>=64 && raw_y<304);
 assign mv_window_visible=out_x>=16 && out_x<336 && out_y>=64 && out_y<304;
 vinyl_renderer #(.VINYL_CX(176),.VINYL_CY(184),.VINYL_R(112),.LABEL_R(34)) renderer(
  .clk(clk),.rst_n(rst_n),.de(adjusted_de),.pixel_x(adjusted_x),.pixel_y(adj_y),
  .phase(phase_frame),.enable(play_frame && !mv_read_active),.rgb_in(rgb_in),.rgb_out(rgb_out),.hit());
endmodule
`endif

`timescale 1ns/1ps
// One held request per bank transaction. Mode 0 cuts at frame boundary,
// mode 1 reveals in sixteen frames (~0.27 s at 60 Hz) without darkening,
// mode 2 fades out/in. Page speed is independent of fade speed.
module video_fade_transition #(parameter integer FADE_FRAMES=0)(
 input wire ctrl_clk,ctrl_rst_n,next_event_in,direction_in,
 input wire [1:0] effect_mode,
 output wire next_event_out,fade_busy,
 input wire pix_clk,pix_rst_n,player_active,frame_start,index_commit,
 input wire [1:0] active_index,
 output wire [7:0] alpha_out,
 output wire fade_active,wipe_active,
 output wire [4:0] ramp_out,
 output wire [1:0] transition_kind
);
 generate if(FADE_FRAMES==0) begin:g_bypass
  assign next_event_out=next_event_in;
  assign fade_busy=0; assign alpha_out=255; assign fade_active=0;
  assign wipe_active=0; assign ramp_out=0; assign transition_kind=0;
 end else begin:g_fade
  localparam integer FADE_STEP=(FADE_FRAMES<=1)?16:((16+FADE_FRAMES-1)/FADE_FRAMES);
  localparam IDLE=3'd0,ALIGN=3'd1,OUT=3'd2,HOLD=3'd3,IN=3'd4;
  reg req, direction_hold, inflight;
  reg [1:0] mode_hold;
  reg [2:0] commit_sync,done_sync;
  reg [2:0] request_sync;
  reg [1:0] mode1,mode2,mode;
  reg dir1,dir2;
  reg seen,commit_toggle,done_toggle;
  reg [2:0] state;
  reg [4:0] ramp;
  reg [5:0] wait_frames;
  reg [1:0] kind;
  wire accept=next_event_in && !inflight;
  assign next_event_out=commit_sync[2]^commit_sync[1];
  assign fade_busy=inflight;
  assign fade_active=state!=IDLE && mode!=0;
  assign wipe_active=state==IN && mode==1;
  assign transition_kind=kind;
  assign ramp_out=ramp;
  assign alpha_out=(mode!=2 || state==IDLE || state==ALIGN) ? 8'd255 :
                   (state==HOLD) ? 8'd0 : (ramp>=16) ? 8'd255 : {ramp[3:0],4'b0000};
  always @(posedge ctrl_clk or negedge ctrl_rst_n) begin
   if(!ctrl_rst_n) begin
    req<=0; direction_hold<=0; mode_hold<=0; inflight<=0; commit_sync<=0; done_sync<=0;
   end else begin
    commit_sync<={commit_sync[1:0],commit_toggle};
    done_sync<={done_sync[1:0],done_toggle};
    if(accept) begin
     req<=~req; direction_hold<=direction_in; mode_hold<=effect_mode; inflight<=1;
    end else if(done_sync[2]^done_sync[1]) inflight<=0;
   end
  end
  always @(posedge pix_clk or negedge pix_rst_n) begin
   if(!pix_rst_n) begin
    request_sync<=0; mode1<=0; mode2<=0; dir1<=0; dir2<=0;
    seen<=0; commit_toggle<=0; done_toggle<=0; state<=IDLE;
    mode<=0; ramp<=0; wait_frames<=0; kind<=0;
   end else begin
    request_sync<={request_sync[1:0],req};
    mode1<=mode_hold; mode2<=mode1; dir1<=direction_hold; dir2<=dir1;
    case(state)
     IDLE: if(request_sync[2]!=seen) begin
      seen<=request_sync[2]; mode<=mode2; kind<={1'b0,dir2};
      ramp<=16; state<=ALIGN;
     end
     ALIGN: if(frame_start) begin
      if(mode==2 && player_active) state<=OUT;
      else begin commit_toggle<=~commit_toggle; state<=HOLD; wait_frames<=0; end
     end
     OUT: if(frame_start) begin
      if(ramp==0) begin commit_toggle<=~commit_toggle; state<=HOLD; wait_frames<=0; end
      else ramp<=(ramp<=FADE_STEP)?0:ramp-FADE_STEP;
     end
     HOLD: begin
      // Abort/return paths also produce index_commit. Bound missing commits so
      // an unavailable bank can never leave the screen permanently black.
      if(index_commit || (frame_start && wait_frames==63)) begin
       if(mode==0 || !player_active) begin state<=IDLE; done_toggle<=~done_toggle; end
       else begin state<=IN; ramp<=(mode==1)?5'd1:5'd0; end
      end else if(frame_start) wait_frames<=wait_frames+1'b1;
     end
     IN: if(frame_start) begin
      if(ramp>=16) begin state<=IDLE; done_toggle<=~done_toggle; end
      else if(mode==1) ramp<=ramp+5'd1;
      else ramp<=((ramp+FADE_STEP)>=16)?16:ramp+FADE_STEP;
     end
     default: begin state<=IDLE; done_toggle<=~done_toggle; end
    endcase
   end
  end
 end endgenerate
endmodule

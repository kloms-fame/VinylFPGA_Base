`ifndef VINYL_BACKGROUND_CACHE_LOADER_V
`define VINYL_BACKGROUND_CACHE_LOADER_V
// SD clock domain. A writer owns one 256-word chunk from ACK until SDRAM
// completion. Short/error sectors are padded before releasing ownership.
// Song invalidation is a persistent epoch handshake with the memory reader;
// further song changes coalesce while the reader drains the old frame.
module background_cache_loader #(
 parameter integer FRAME_SECTORS = 1200
)(
 input wire clk, rst_n, enable,
 input wire [31:0] base_lba,
 input wire [1:0] song_id,
 input wire mv_writer_active, invalidate_ack_async,
 input wire write_ack, write_finish_toggle,
 output wire [4:0] ready_info,
 output wire invalidate_toggle, writer_active, write_req,
 output reg [20:0] write_address,
 output wire pixel_valid, output wire [31:0] pixel_data,
 output wire sector_req, output reg [31:0] sector_lba,
 input wire sector_busy, sector_valid,
 input wire [7:0] sector_byte,
 input wire [8:0] sector_byte_index,
 input wire sector_done,
 input wire [7:0] sector_error
);
 localparam [3:0] IDLE=4'd0, WAIT_CHUNK=4'd1, ACK=4'd2, CLEAR=4'd3,
     REQ=4'd4, READ=4'd5, PAD=4'd6, DRAIN=4'd7, NEXT=4'd8;
 localparam [20:0] SONG_ADDRESS=21'd1459200, ART_ADDRESS=21'd1766400;
 reg [3:0] state;
 (* async_reg = "true" *) reg [1:0] invalidation_ack_sync;
 (* async_reg = "true" *) reg [1:0] write_ack_sync;
 (* async_reg = "true" *) reg [1:0] finish_sync;
 reg epoch;
 reg [1:0] target_song;
 reg [1:0] cached_song;
 reg art_ready, song_ready;
 reg art_failed, song_failed;
 reg job_art;
 reg [1:0] job_song;
 reg [10:0] chunk;
 reg [9:0] byte_count;
 reg [8:0] word_count;
 reg [7:0] low_byte;
 reg failed;
 reg finish_mark;
 reg [31:0] source_base = 32'd0;
 reg source_base_valid = 1'b0;
 reg source_enabled = 1'b0;
 always @(posedge clk or negedge rst_n) begin
  if (!rst_n) source_enabled <= 1'b0;
  else source_enabled <= enable;
 end
 always @(posedge clk or negedge rst_n) begin
  if (!rst_n) source_base <= 32'd0;
  else source_base <= base_lba;
 end
 always @(posedge clk or negedge rst_n) begin
  if (!rst_n) source_base_valid <= 1'b0;
  else source_base_valid <= source_base != 32'd0 && source_base <= 32'hFFFFE88F;
 end
 wire source_valid = source_enabled && source_base_valid;
 wire song_changed = song_id != target_song;
 wire invalidate_pending = invalidation_ack_sync[1] != epoch;
 wire job_obsolete = !source_valid || (!job_art && (job_song != song_id || song_changed));
 wire start_art = state == IDLE && source_valid && !art_ready && !art_failed;
 wire start_song = state == IDLE && source_valid && (art_ready || art_failed) &&
     !song_ready && !song_failed && !song_changed && !invalidate_pending;
 wire byte_bad = sector_valid && (byte_count >= 10'd512 || sector_byte_index != byte_count[8:0]);
 wire read_pixel = state == READ && sector_valid && sector_byte_index[0] && !failed && !byte_bad;
 wire [10:0] byte_count_with_valid = {1'b0,byte_count} + (sector_valid ? 11'd1 : 11'd0);
 wire sector_bad = sector_error != 8'd0 || byte_count_with_valid != 11'd512 || byte_bad;
 wire frame_finished = state == NEXT && !failed && !job_obsolete && chunk == FRAME_SECTORS-1;
 wire [15:0] rgb565 = {sector_byte,low_byte};
 assign ready_info = {epoch,art_ready,song_ready,cached_song};
 assign invalidate_toggle = epoch;
 assign writer_active = state >= ACK && state <= DRAIN;
 assign write_req = state == ACK;
 assign sector_req = state == REQ && !sector_busy && !job_obsolete;
 assign pixel_valid = read_pixel || (state == PAD && word_count < 9'd256);
 assign pixel_data = state == PAD ? 32'd0 :
     {rgb565[15:11],rgb565[15:13],rgb565[10:5],rgb565[10:9],rgb565[4:0],rgb565[4:2],8'd0};
 initial state=IDLE;
 initial invalidation_ack_sync=2'd0;
 initial write_ack_sync=2'd0;
 initial finish_sync=2'd0;
 initial epoch=1'b0;
 initial target_song=2'd0;
 initial cached_song=2'd0;
 initial art_ready=1'b0;
 initial song_ready=1'b0;
 initial art_failed=1'b0;
 initial song_failed=1'b0;
 initial job_art=1'b0;
 initial job_song=2'd0;
 initial chunk=11'd0;
 initial byte_count=10'd0;
 initial word_count=9'd0;
 initial low_byte=8'd0;
 initial failed=1'b0;
 initial finish_mark=1'b0;
 initial write_address=21'd0;
 initial sector_lba=32'd0;
 always @(posedge clk or negedge rst_n) begin
  if (!rst_n) invalidation_ack_sync<=2'd0;
  else invalidation_ack_sync<={invalidation_ack_sync[0],invalidate_ack_async};
 end
 always @(posedge clk or negedge rst_n) begin
  if (!rst_n) write_ack_sync<=2'd0;
  else write_ack_sync<={write_ack_sync[0],write_ack};
 end
 always @(posedge clk or negedge rst_n) begin
  if (!rst_n) finish_sync<=2'd0;
  else finish_sync<={finish_sync[0],write_finish_toggle};
 end
 always @(posedge clk or negedge rst_n) begin
  if (!rst_n) target_song<=2'd0;
  else target_song<=song_id;
 end
 always @(posedge clk or negedge rst_n) begin
  if (!rst_n) epoch<=1'b0;
  else if (song_changed && !invalidate_pending) epoch<=!epoch;
 end
 always @(posedge clk or negedge rst_n) begin
  if (!rst_n) state<=IDLE;
  else case (state)
   IDLE: if (start_art || start_song) state<=WAIT_CHUNK;
   WAIT_CHUNK: if (job_obsolete) state<=IDLE;
               else if (!mv_writer_active && (job_art || (!invalidate_pending && !song_changed))) state<=ACK;
   ACK: if (write_ack_sync[1]) state<=CLEAR;
   CLEAR: if (!write_ack_sync[1]) state<=REQ;
   REQ: if (job_obsolete) state<=PAD;
        else if (!sector_busy) state<=READ;
   READ: if (sector_done) state<=PAD;
   PAD: if (word_count == 9'd256) state<=DRAIN;
   DRAIN: if (finish_sync[1] != finish_mark) state<=NEXT;
   NEXT: if (failed || job_obsolete || chunk == FRAME_SECTORS-1) state<=IDLE;
         else state<=WAIT_CHUNK;
   default: state<=IDLE;
  endcase
 end
 always @(posedge clk or negedge rst_n) begin
  if (!rst_n) job_art<=1'b0;
  else if (start_art || start_song) job_art<=start_art;
 end
 always @(posedge clk or negedge rst_n) begin
  if (!rst_n) job_song<=2'd0;
  else if (start_song) job_song<=song_id;
 end
 always @(posedge clk or negedge rst_n) begin
  if (!rst_n) chunk<=11'd0;
  else if (start_art || start_song) chunk<=11'd0;
  else if (state == NEXT) chunk<=chunk+11'd1;
 end
 always @(posedge clk or negedge rst_n) begin
  if (!rst_n) sector_lba<=32'd0;
  else if (start_art) sector_lba<=source_base+32'd4800;
  else if (start_song) begin
   case(song_id)
    2'd0: sector_lba<=source_base;
    2'd1: sector_lba<=source_base+32'd1200;
    2'd2: sector_lba<=source_base+32'd2400;
    2'd3: sector_lba<=source_base+32'd3600;
   endcase
  end else if (state == NEXT) sector_lba<=sector_lba+32'd1;
 end
 always @(posedge clk or negedge rst_n) begin
  if (!rst_n) write_address<=21'd0;
  else if (start_art) write_address<=ART_ADDRESS;
  else if (start_song) write_address<=SONG_ADDRESS;
  else if (state == NEXT) write_address<=write_address+21'd256;
 end
 always @(posedge clk or negedge rst_n) begin
  if (!rst_n) byte_count<=10'd0;
  else if (state == REQ) byte_count<=10'd0;
  else if (state == READ && sector_valid && byte_count < 10'd512) byte_count<=byte_count+10'd1;
 end
 always @(posedge clk or negedge rst_n) begin
  if (!rst_n) word_count<=9'd0;
  else if (state == ACK) word_count<=9'd0;
  else if (pixel_valid) word_count<=word_count+9'd1;
 end
 always @(posedge clk or negedge rst_n) begin
  if (!rst_n) low_byte<=8'd0;
  else if (state == READ && sector_valid && !sector_byte_index[0]) low_byte<=sector_byte;
 end
 always @(posedge clk or negedge rst_n) begin
  if (!rst_n) failed<=1'b0;
  else if (start_art || start_song) failed<=1'b0;
  else if (job_obsolete && state != IDLE) failed<=1'b1;
  else if (state == READ && (byte_bad || (sector_done && sector_bad))) failed<=1'b1;
 end
 always @(posedge clk or negedge rst_n) begin
  if (!rst_n) finish_mark<=1'b0;
  else if (state == ACK) finish_mark<=finish_sync[1];
 end
 always @(posedge clk or negedge rst_n) begin
  if (!rst_n) art_ready<=1'b0;
  else if (frame_finished && job_art) art_ready<=1'b1;
 end
 always @(posedge clk or negedge rst_n) begin
  if (!rst_n) song_ready<=1'b0;
  else if (song_changed || !source_valid) song_ready<=1'b0;
  else if (frame_finished && !job_art) song_ready<=1'b1;
 end
 always @(posedge clk or negedge rst_n) begin
  if (!rst_n) cached_song<=2'd0;
  else if (frame_finished && !job_art) cached_song<=job_song;
 end
 always @(posedge clk or negedge rst_n) begin
  if (!rst_n) art_failed<=1'b0;
  else if (state == NEXT && failed && job_art) art_failed<=1'b1;
 end
 always @(posedge clk or negedge rst_n) begin
  if (!rst_n) song_failed<=1'b0;
  else if (song_changed) song_failed<=1'b0;
  else if (state == NEXT && failed && !job_art && job_song == song_id) song_failed<=1'b1;
 end
endmodule
`endif

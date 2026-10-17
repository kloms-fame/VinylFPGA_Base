`ifndef VINYL_BACKGROUND_CACHE_LOADER_V
`define VINYL_BACKGROUND_CACHE_LOADER_V
// One sector is staged in the existing shared write FIFO. Hold its SDRAM
// writer until all 512 bytes validate; retry ACK clears that FIFO in place.
// Every slot replacement waits for the persistent reader epoch/ACK fence.
module background_cache_loader #(
 parameter integer FRAME_SECTORS = 1200,
 parameter integer SECTOR_RETRIES = 2
)(
 input wire clk, rst_n, enable,
 input wire [31:0] base_lba,
 input wire [1:0] song_id,
 input wire art2_supported, art_request_async, art2_request_async,
 input wire mv_writer_active, invalidate_ack_async,
 input wire write_ack, write_finish_toggle,
 output wire [5:0] ready_info,
 output wire invalidate_toggle, writer_active, write_req,
 output wire write_hold, write_cancel,
 output reg [20:0] write_address = 21'd0,
 output wire pixel_valid, output wire [31:0] pixel_data,
 output wire sector_req, output wire sector_start,
 output reg [31:0] sector_lba = 32'd0,
 input wire sector_busy, sector_grant, sector_valid,
 input wire [7:0] sector_byte,
 input wire [8:0] sector_byte_index,
 input wire sector_done,
 input wire [7:0] sector_error
);
 localparam [3:0] IDLE=0, WAIT_CHUNK=1, ACK=2, CLEAR=3,
     REQ=4, READ=5, DRAIN=7, NEXT=8, ABORT=9;
 localparam [20:0] SONG_ADDRESS=21'd1459200, ART_ADDRESS=21'd1766400;
 reg [3:0] state = IDLE;
 (* async_reg = "true" *) reg [1:0] invalidation_ack_sync = 2'd0;
 (* async_reg = "true" *) reg [1:0] write_ack_sync = 2'd0;
 (* async_reg = "true" *) reg [1:0] finish_sync = 2'd0;
 (* async_reg = "true" *) reg [1:0] art_request_sync = 2'd0;
 (* async_reg = "true" *) reg [1:0] art2_request_sync = 2'd0;
 reg epoch = 1'b0;
 reg [1:0] target_song = 2'd0, cached_song = 2'd0;
 reg target_art2 = 1'b0, cached_art2 = 1'b0;
 reg art_ready = 1'b0, song_ready = 1'b0;
 reg art_failed = 1'b0, song_failed = 1'b0;
 reg job_art = 1'b0, job_art2 = 1'b0;
 reg [1:0] job_song = 2'd0;
 reg [10:0] chunk = 11'd0;
 reg [9:0] byte_count = 10'd0;
 reg [7:0] low_byte = 8'd0;
 reg failed = 1'b0, abandoned = 1'b0, finish_mark = 1'b0;
 reg [1:0] retry_count = 2'd0;
 reg retry_pending = 1'b0;
 reg [31:0] source_base = 32'd0;
 reg source_base_valid = 1'b0, source_enabled = 1'b0;
 reg source_art2_supported = 1'b0;
 wire source_valid = source_enabled && source_base_valid;
 wire song_changed = song_id != target_song;
 wire requested_art2 = source_art2_supported && art2_request_sync[1];
 wire art_changed = art_request_sync[1] && requested_art2 != target_art2;
 wire invalidate_pending = invalidation_ack_sync[1] != epoch;
 wire job_obsolete = !source_valid || (job_art
     ? (job_art2 != target_art2 || art_changed)
     : (job_song != song_id || song_changed));
 wire start_art_request = source_valid && !art_ready && !art_failed && !art_changed;
 wire start_song_request = source_valid && (art_ready || art_failed) &&
     !song_ready && !song_failed && !song_changed && !invalidate_pending;
 wire start_art = state == IDLE && start_art_request;
 wire start_song = state == IDLE && start_song_request;
 wire byte_bad = sector_valid && (byte_count >= 10'd512 || sector_byte_index != byte_count[8:0]);
 wire [10:0] byte_count_with_valid = {1'b0,byte_count} + (sector_valid ? 11'd1 : 11'd0);
 wire sector_bad = sector_error != 8'd0 || byte_count_with_valid != 11'd512 || byte_bad;
 wire frame_finished = state == NEXT && !failed && !abandoned && !job_obsolete && chunk == FRAME_SECTORS-1;
 wire [15:0] rgb565 = {sector_byte,low_byte};
 assign ready_info = {epoch,cached_art2,art_ready,song_ready,cached_song};
 assign invalidate_toggle = epoch;
 // Never reserve SDRAM while waiting for the SD-sector arbiter. A writer
 // token is requested only after the mux confirms ownership of this sector.
 assign writer_active = state == ACK || state == CLEAR || state == READ ||
                        state == DRAIN || state == ABORT;
 assign write_req = state == ACK;
 assign write_hold = state != DRAIN;
 assign write_cancel = state == ABORT;
 assign sector_req = state == REQ && !sector_busy && !job_obsolete && !abandoned;
 assign sector_start = state == READ || (state == ABORT && sector_grant);
 assign pixel_valid = state == READ && sector_valid && sector_byte_index[0] &&
                      !failed && !byte_bad && !job_obsolete && !abandoned;
 assign pixel_data = {rgb565[15:11],rgb565[15:13],rgb565[10:5],rgb565[10:9],rgb565[4:0],rgb565[4:2],8'd0};
 always @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin
   invalidation_ack_sync<=0; write_ack_sync<=0; finish_sync<=0;
   art_request_sync<=0; art2_request_sync<=0;
  end else begin
   invalidation_ack_sync<={invalidation_ack_sync[0],invalidate_ack_async};
   write_ack_sync<={write_ack_sync[0],write_ack};
   finish_sync<={finish_sync[0],write_finish_toggle};
   art_request_sync<={art_request_sync[0],art_request_async};
   art2_request_sync<={art2_request_sync[0],art2_request_async};
  end
 end
 always @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin source_enabled<=0; source_base<=0; source_base_valid<=0; source_art2_supported<=0; end
  else begin
   source_enabled<=enable; source_base<=base_lba;
   // Capture capability before local job/CE decode. Index valid
   // otherwise travels through requested_art2 -> art_changed -> start_art.
   source_art2_supported<=art2_supported;
   source_base_valid<=source_base != 0 && source_base <= (art2_supported ? 32'hFFFFE3DF : 32'hFFFFE88F);
  end
 end
 always @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin target_song<=0; target_art2<=0; epoch<=0; end
  else begin
   target_song<=song_id;
   if (art_request_sync[1]) target_art2<=requested_art2;
   if ((song_changed || art_changed) && !invalidate_pending) epoch<=!epoch;
  end
 end
 always @(posedge clk or negedge rst_n) begin
  if (!rst_n) state<=IDLE;
  else case (state)
   // IDLE is already selected by this state branch. Use the request terms
   // directly so the next-state cone does not decode state==IDLE twice via
   // start_art/start_song before feeding the state register again.
   IDLE: if (start_art_request || start_song_request) state<=WAIT_CHUNK;
   WAIT_CHUNK: if (job_obsolete || abandoned) state<=IDLE;
               else if (!mv_writer_active && !invalidate_pending && !song_changed && !art_changed) state<=REQ;
   ACK: if (write_ack_sync[1]) state<=CLEAR;
   CLEAR: if (!write_ack_sync[1]) state<=READ;
   REQ: if (sector_grant) state<=(job_obsolete || abandoned) ? ABORT : ACK;
        else if (job_obsolete || abandoned) state<=IDLE;
   READ: if (sector_done) begin
    if (job_obsolete || abandoned) state<=ABORT;
    else if (failed || sector_bad) state<=ABORT;
    else state<=DRAIN;
   end
   DRAIN, ABORT: if (finish_sync[1] != finish_mark) state<=NEXT;
   NEXT: if (abandoned || job_obsolete) state<=IDLE;
         else if (failed) state<=retry_pending ? WAIT_CHUNK : IDLE;
         else if (chunk == FRAME_SECTORS-1) state<=IDLE;
         else state<=WAIT_CHUNK;
   default: state<=IDLE;
  endcase
 end
 always @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin job_art<=0; job_art2<=0; job_song<=0; chunk<=0; end
  else if (start_art || start_song) begin
   job_art<=start_art; job_art2<=target_art2; job_song<=song_id; chunk<=0;
 end else if (state == NEXT && !failed) chunk<=chunk+11'd1;
 end
 always @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin sector_lba<=0; write_address<=0; end
  else if (start_art) begin
   sector_lba<=source_base+(target_art2 ? 32'd6000 : 32'd4800);
   write_address<=ART_ADDRESS;
  end else if (start_song) begin
   case(song_id)
    0: sector_lba<=source_base;
    1: sector_lba<=source_base+32'd1200;
    2: sector_lba<=source_base+32'd2400;
    3: sector_lba<=source_base+32'd3600;
   endcase
   write_address<=SONG_ADDRESS;
 end else if (state == NEXT && !failed) begin
   sector_lba<=sector_lba+32'd1; write_address<=write_address+21'd256;
  end
 end
 always @(posedge clk or negedge rst_n) begin
  if (!rst_n) byte_count<=0;
  else if (state == REQ) byte_count<=0;
  else if (state == READ && sector_valid && byte_count < 512) byte_count<=byte_count+10'd1;
 end
 always @(posedge clk or negedge rst_n) begin
  if (!rst_n) low_byte<=0;
  else if (state == READ && sector_valid && !sector_byte_index[0]) low_byte<=sector_byte;
 end
 always @(posedge clk or negedge rst_n) begin
  if (!rst_n) failed<=0;
  else if (start_art || start_song || state == ACK ||
           (state == NEXT && failed && retry_pending)) failed<=0;
  else if (state == READ && (byte_bad || (sector_done && sector_bad))) failed<=1;
 end
 always @(posedge clk or negedge rst_n) begin
  if (!rst_n) abandoned<=0;
  else if (start_art || start_song) abandoned<=0;
  else if (state != IDLE && job_obsolete) abandoned<=1;
 end
 always @(posedge clk or negedge rst_n) begin
  if (!rst_n) retry_count<=0;
  else if (start_art || start_song || (state == NEXT && !failed)) retry_count<=0;
  else if (state == READ && sector_done && (failed || sector_bad) && retry_count < SECTOR_RETRIES)
   retry_count<=retry_count+2'd1;
 end
 always @(posedge clk or negedge rst_n) begin
  if (!rst_n) retry_pending<=1'b0;
  else if (start_art || start_song || state == NEXT) retry_pending<=1'b0;
  else if (state == READ && sector_done)
   retry_pending<=!job_obsolete && !abandoned && (failed || sector_bad) &&
                  retry_count < SECTOR_RETRIES;
 end
 always @(posedge clk or negedge rst_n) begin
  if (!rst_n) finish_mark<=0;
  else if (state == ACK) finish_mark<=finish_sync[1];
 end
 always @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin art_ready<=0; art_failed<=0; cached_art2<=0; end
  else begin
   if (art_changed || !source_valid) begin art_ready<=0; art_failed<=0; end
   else if (frame_finished && job_art) begin art_ready<=1; cached_art2<=job_art2; end
   else if (state == NEXT && failed && !abandoned && job_art) art_failed<=1;
  end
 end
 always @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin song_ready<=0; song_failed<=0; cached_song<=0; end
  else begin
   if (song_changed || !source_valid) begin song_ready<=0; song_failed<=0; end
   else if (frame_finished && !job_art) begin song_ready<=1; cached_song<=job_song; end
   else if (state == NEXT && failed && !abandoned && !job_art && job_song == song_id) song_failed<=1;
  end
 end
endmodule
`endif

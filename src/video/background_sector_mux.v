`ifndef VINYL_BACKGROUND_SECTOR_MUX_V
`define VINYL_BACKGROUND_SECTOR_MUX_V
// sd_card_clk. Priority is reconsidered only between complete sectors.
// Addresses belong to the client until done; audio may latch its LBA on grant.
module background_sector_mux (
 input wire clk, rst_n,
 input wire audio_req, input wire [31:0] audio_lba,
 input wire audio_urgent,
 input wire video_req, input wire [31:0] video_lba,
 input wire background_req, input wire [31:0] background_lba,
 input wire background_start,
 input wire allow_video, allow_background,
 output wire audio_busy, video_busy, background_busy,
 output wire background_grant,
 output wire audio_valid, video_valid, background_valid,
 output wire audio_done, video_done, background_done,
 output wire sector_req, output wire [31:0] sector_lba,
 input wire sector_busy, sector_valid, sector_done
);
 reg owner_valid;
 reg [1:0] owner;
 reg issued;
 reg [3:0] video_quota;
 // Audio normally needs only a small fraction of SD bandwidth. During a
 // healthy-cache refill, grant up to fifteen waiting MV sectors between audio
 // sectors; below the critical watermark audio regains strict priority.
 wire prefer_video = allow_video && video_req && !audio_urgent && video_quota!=4'd15;
 wire video_eligible = allow_video && video_req && (!audio_req || prefer_video);
 wire take_audio = !owner_valid && !sector_busy && audio_req &&
                   (!video_eligible || audio_urgent || video_quota==4'd15);
 wire take_video = !owner_valid && !sector_busy && video_eligible &&
                   (!audio_urgent || !audio_req);
 wire take_background = !owner_valid && !sector_busy && !audio_req &&
     !video_eligible && allow_background && background_req;
 initial owner_valid = 1'b0;
 initial owner = 2'd0;
 initial issued = 1'b0;
 initial video_quota = 4'd0;
 // Background ownership is reserved first. The client starts the raw SD read
 // only after its downstream SDRAM writer is ready to accept the sector.
 assign sector_req = owner_valid && !issued && !sector_busy &&
                     (owner != 2'd2 || background_start);
 assign sector_lba = owner == 2'd2 ? background_lba : owner == 2'd1 ? video_lba : audio_lba;
 // A client treats !busy as acceptance on this edge. Denial must follow the
 // same weighted choice as take_*, otherwise a losing client starts waiting
 // for another owner's response. MV holds its demand independently of busy.
 assign audio_busy = owner_valid || sector_busy || prefer_video;
 assign video_busy = owner_valid || sector_busy ||
                     (audio_req && !prefer_video) || !allow_video;
 assign background_busy = owner_valid || sector_busy || audio_req ||
     (allow_video && video_req) || !allow_background;
 assign audio_valid = owner_valid && issued && owner == 2'd0 && sector_valid;
 assign video_valid = owner_valid && issued && owner == 2'd1 && sector_valid;
 assign background_valid = owner_valid && issued && owner == 2'd2 && sector_valid;
 assign audio_done = owner_valid && issued && owner == 2'd0 && sector_done;
 assign video_done = owner_valid && issued && owner == 2'd1 && sector_done;
 assign background_done = owner_valid && issued && owner == 2'd2 && sector_done;
 assign background_grant = owner_valid && owner == 2'd2;
 always @(posedge clk or negedge rst_n) begin
  if (!rst_n) owner_valid <= 1'b0;
  else if (owner_valid && issued && sector_done) owner_valid <= 1'b0;
  else if (take_audio || take_video || take_background) owner_valid <= 1'b1;
 end
 always @(posedge clk or negedge rst_n) begin
  if (!rst_n) owner <= 2'd0;
  else if (take_audio) owner <= 2'd0;
  else if (take_video) owner <= 2'd1;
  else if (take_background) owner <= 2'd2;
 end
 always @(posedge clk or negedge rst_n) begin
  if (!rst_n) issued <= 1'b0;
  else if (!owner_valid || sector_done) issued <= 1'b0;
  else if (sector_req) issued <= 1'b1;
 end
 always @(posedge clk or negedge rst_n) begin
  if (!rst_n) video_quota <= 4'd0;
  else if (take_audio) video_quota <= 4'd0;
  else if (take_video && video_quota!=4'd15) video_quota <= video_quota+1'b1;
 end
endmodule
`endif

`ifndef VINYL_MV_SECTOR_MUX_V
`define VINYL_MV_SECTOR_MUX_V
// One non-preemptible sector. Audio wins at every idle boundary. sd_card_clk.
module mv_sector_mux (
 input wire clk, rst_n,
 input wire audio_req, input wire [31:0] audio_lba,
 input wire video_req, input wire [31:0] video_lba,
 input wire allow_video,
 output wire audio_busy, video_busy, audio_valid, video_valid, audio_done, video_done,
 output wire sector_req, output wire [31:0] sector_lba,
 input wire sector_busy, sector_valid, sector_done
);
 reg owner_valid;
 reg owner_video;
 reg issued;
 wire take_audio = !owner_valid && !sector_busy && audio_req;
 wire take_video = !owner_valid && !sector_busy && !audio_req && allow_video && video_req;
 // WAV updates sd_lba on the grant edge (WS_REQ -> WS_FILL). Request the
 // downstream adapter on the following cycle, when that address is stable.
 assign sector_req = owner_valid && !issued && !sector_busy;
 assign sector_lba = owner_video ? video_lba : audio_lba;
 assign audio_busy = owner_valid || sector_busy;
 assign video_busy = owner_valid || sector_busy || audio_req || !allow_video;
 assign audio_valid = owner_valid && issued && !owner_video && sector_valid;
 assign video_valid = owner_valid && issued && owner_video && sector_valid;
 assign audio_done = owner_valid && issued && !owner_video && sector_done;
 assign video_done = owner_valid && issued && owner_video && sector_done;
 always @(posedge clk or negedge rst_n) begin
  if (!rst_n) owner_valid <= 1'b0;
  else if (owner_valid && issued && sector_done) owner_valid <= 1'b0;
  else if (take_audio || take_video) owner_valid <= 1'b1;
 end
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) issued<=1'b0;
  else if(!owner_valid || sector_done) issued<=1'b0;
  else if(sector_req) issued<=1'b1;
 end
 always @(posedge clk or negedge rst_n) begin
  if (!rst_n) owner_video <= 1'b0;
  else if (take_audio || take_video) owner_video <= take_video;
 end
endmodule
`endif

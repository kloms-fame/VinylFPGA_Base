`ifndef VINYL_NAVIGATION_READINESS_V
`define VINYL_NAVIGATION_READINESS_V
// Keep browse availability independent of image preload completion. Playback
// requires a mounted media set and valid audio metadata for the selected song.
module navigation_readiness (
    input  wire        scan_done,
    input  wire [3:0]  source_valid,
    input  wire [15:0] scan_error,
    input  wire        media_mounted,
    input  wire        audio_file_valid,
    input  wire [31:0] audio_total_sectors,
    output wire        browse_ready,
    output wire [2:0]  browse_count,
    output wire        playback_ready
);
    assign browse_count = {2'b0, source_valid[0]} +
                          {2'b0, source_valid[1]} +
                          {2'b0, source_valid[2]} +
                          {2'b0, source_valid[3]};
    assign browse_ready = scan_done && (browse_count != 3'd0) &&
                          (scan_error == 16'd0);
    assign playback_ready = media_mounted && audio_file_valid &&
                            (audio_total_sectors != 32'd0);
endmodule
`endif

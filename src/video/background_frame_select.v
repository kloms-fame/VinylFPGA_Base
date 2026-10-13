`ifndef VINYL_BACKGROUND_FRAME_SELECT_V
`define VINYL_BACKGROUND_FRAME_SELECT_V
// Commit in vertical blank, one beat after frame_start so the page's KEY11
// mode and frame-latched song ID already contain the current frame choices.
module background_frame_select (
    input wire clk, rst_n, frame_start, enable,
    input wire [1:0] mode, song_id,
    input wire [4:0] ready_info,
    output reg image_active = 1'b0,
    output reg epoch = 1'b0,
    output reg [20:0] base = 21'd0
);
    reg commit = 1'b0;
    wire epoch_matches = ready_info[4] == epoch;
    wire song_ready = ready_info[2] && ready_info[1:0] == song_id;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) commit <= 1'b0;
        else commit <= frame_start;
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) image_active <= 1'b0;
        else if (commit) image_active <= enable && epoch_matches &&
            ((mode == 2'd1 && song_ready) || (mode == 2'd2 && ready_info[3]));
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) epoch <= 1'b0;
        else if (commit) epoch <= ready_info[4];
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) base <= 21'd0;
        else if (commit) base <= (mode == 2'd2) ? 21'd1766400 : 21'd1459200;
    end
endmodule
`endif

`timescale 1ns/1ps
`ifndef EXP_LRC_FIVE_OSD_V
`define EXP_LRC_FIVE_OSD_V
`include "playback_layout.vh"

// D11/D12 pixel selector for the five visible rows and sixth incoming row.
// This block selects a glyph request only; playback_page arbitrates the
// request with title/artist/time and drives the single shared font ROM.
module lrc_five_osd (
    input  wire          enable,
    input  wire          de,
    input  wire [9:0]    pixel_x,
    input  wire [9:0]    pixel_y,
    input  wire          window_valid,
    input  wire [5:0]    row_valid,
    input  wire [41:0]   row_indices,
    input  wire [29:0]   row_lengths,
    input  wire [767:0]  row_glyphs,
    input  wire [6:0]    highlight_index,
    input  wire [5:0]    scroll_offset,
    input  wire [7:0]    line_count,
    input  wire [127:0] no_lyrics_glyphs,
    output reg           font_request,
    output reg  [7:0]    font_glyph,
    output reg  [3:0]    font_column,
    output reg  [3:0]    font_pixel_column,
    output reg  [3:0]    font_row,
    output reg  [23:0]   text_color
);
    wire [9:0] lyric_dx = pixel_x - `PLAYBACK_LYRIC_X;
    wire lyric_x_active = (pixel_x >= `PLAYBACK_LYRIC_X) &&
        (pixel_x < (`PLAYBACK_LYRIC_X + 10'd256));
    wire lyric_y_active = (pixel_y >= `PLAYBACK_INFO_Y0) &&
        (pixel_y < `PLAYBACK_INFO_Y1);

    integer slot;
    reg signed [11:0] row_top_signed;
    reg signed [11:0] pixel_y_signed;
    reg signed [7:0] row_distance;
    reg [2:0] selected_slot;
    reg selected_row_found;
    reg [3:0] selected_row_pixel;
    reg [6:0] selected_index;
    reg [4:0] selected_length;

    always @* begin
        font_request = 1'b0;
        font_glyph = 8'd0;
        font_column = lyric_dx[7:4];
        font_pixel_column = lyric_dx[3:0];
        font_row = 4'd0;
        text_color = 24'hFFFFFF;
        selected_slot = 3'd0;
        selected_row_found = 1'b0;
        selected_row_pixel = 4'd0;
        selected_index = 7'd0;
        selected_length = 5'd0;
        row_top_signed = 12'sd0;
        pixel_y_signed = $signed({2'b00, pixel_y});
        row_distance = 8'sd0;

        if (enable && de && lyric_x_active && lyric_y_active) begin
            if (line_count == 0) begin
                if ((pixel_y >= `PLAYBACK_LYRIC_Y) &&
                    (pixel_y < (`PLAYBACK_LYRIC_Y + 10'd16)) &&
                    (font_column < 4'd9)) begin
                    font_request = 1'b1;
                    font_glyph = no_lyrics_glyphs[font_column*8 +: 8];
                    font_row = pixel_y - `PLAYBACK_LYRIC_Y;
                end
            end else if (window_valid) begin
                for (slot = 0; slot < 6; slot = slot + 1) begin
                    row_top_signed = $signed({2'b00, `PLAYBACK_LYRIC_Y}) - 12'sd96 +
                                     (slot * 12'sd48) -
                                     $signed({6'd0, scroll_offset});
                    if (($signed(pixel_y_signed) >= row_top_signed) &&
                        ($signed(pixel_y_signed) < (row_top_signed + 12'sd16)) &&
                        row_valid[slot]) begin
                        selected_slot = slot[2:0];
                        selected_row_found = 1'b1;
                        selected_row_pixel = pixel_y_signed[3:0] - row_top_signed[3:0];
                    end
                end

                if (selected_row_found) begin
                    selected_index = row_indices[selected_slot*7 +: 7];
                    selected_length = row_lengths[selected_slot*5 +: 5];
                    if (font_column < selected_length) begin
                        font_request = 1'b1;
                        font_glyph = row_glyphs[
                            selected_slot*128 + font_column*8 +: 8];
                        font_row = selected_row_pixel;
                        row_distance = $signed({1'b0, selected_index}) -
                                       $signed({1'b0, highlight_index});
                        if (row_distance == 0)
                            text_color = 24'hFFFFFF;
                        else if ((row_distance == 8'sd1) || (row_distance == -8'sd1))
                            text_color = 24'hB8C5D1;
                        else
                            text_color = 24'h738397;
                    end
                end
            end
        end
    end
endmodule
`endif

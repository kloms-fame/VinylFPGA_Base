`timescale 1ns/1ps
`ifndef EXP_PLAYBACK_PAGE_V
`define EXP_PLAYBACK_PAGE_V
`include "playback_layout.vh"

// D10b: static playback page. The existing media rectangle and waveform
// remain in the incoming stream; only page backgrounds and text are added.
// One shared synchronous font port serves title, artist, time and lyric text.
module playback_page (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         vs,
    input  wire         de,
    input  wire [9:0]   pixel_x,
    input  wire         enable,
    input  wire [23:0]  rgb_in,
    input  wire [1:0]   song_id,
    input  wire [4:0]   title_length,
    input  wire [4:0]   artist_length,
    input  wire [127:0] title_glyphs,
    input  wire [127:0] artist_glyphs,
    input  wire [7:0]   line_count,
    input  wire         lyric_valid,
    input  wire [4:0]   lyric_length,
    input  wire [127:0] lyric_glyphs,
    input  wire [127:0] no_lyrics_glyphs,
    input  wire [7:0]   progress_fill,
    input  wire [103:0] time_ascii,
    input  wire [7:0]   ascii_glyph,
    output reg  [7:0]   ascii_code,
    output reg          out_vs,
    output reg          out_de,
    output reg  [9:0]   out_pixel_x,
    output reg  [23:0]  out_rgb
);
    `include "song_text_geom.vh"

    localparam [23:0] BG_COLOR       = 24'h080D13;
    localparam [23:0] PANEL_COLOR    = 24'h111B27;
    localparam [23:0] BORDER_COLOR   = 24'h314153;
    localparam [23:0] TEXT_COLOR     = 24'hE6EEF5;
    localparam [23:0] SUBTEXT_COLOR  = 24'hA7B8C8;
    localparam [23:0] LYRIC_COLOR    = 24'hFFE860;
    localparam [23:0] PROGRESS_COLOR = 24'h45D7B0;
    localparam [23:0] TRACK_COLOR    = 24'h273744;

    localparam [1:0] TEXT_TITLE  = 2'd0;
    localparam [1:0] TEXT_ARTIST = 2'd1;
    localparam [1:0] TEXT_TIME   = 2'd2;
    localparam [1:0] TEXT_LYRIC  = 2'd3;

    function [7:0] packed_glyph_at;
        input [127:0] packed;
        input [3:0] index;
        begin
            case (index)
                4'd0: packed_glyph_at = packed[7:0];
                4'd1: packed_glyph_at = packed[15:8];
                4'd2: packed_glyph_at = packed[23:16];
                4'd3: packed_glyph_at = packed[31:24];
                4'd4: packed_glyph_at = packed[39:32];
                4'd5: packed_glyph_at = packed[47:40];
                4'd6: packed_glyph_at = packed[55:48];
                4'd7: packed_glyph_at = packed[63:56];
                4'd8: packed_glyph_at = packed[71:64];
                4'd9: packed_glyph_at = packed[79:72];
                4'd10: packed_glyph_at = packed[87:80];
                4'd11: packed_glyph_at = packed[95:88];
                4'd12: packed_glyph_at = packed[103:96];
                4'd13: packed_glyph_at = packed[111:104];
                4'd14: packed_glyph_at = packed[119:112];
                default: packed_glyph_at = packed[127:120];
            endcase
        end
    endfunction

    function [7:0] packed_ascii_at;
        input [103:0] packed;
        input [3:0] index;
        begin
            case (index)
                4'd0: packed_ascii_at = packed[103:96];
                4'd1: packed_ascii_at = packed[95:88];
                4'd2: packed_ascii_at = packed[87:80];
                4'd3: packed_ascii_at = packed[79:72];
                4'd4: packed_ascii_at = packed[71:64];
                4'd5: packed_ascii_at = packed[63:56];
                4'd6: packed_ascii_at = packed[55:48];
                4'd7: packed_ascii_at = packed[47:40];
                4'd8: packed_ascii_at = packed[39:32];
                4'd9: packed_ascii_at = packed[31:24];
                4'd10: packed_ascii_at = packed[23:16];
                4'd11: packed_ascii_at = packed[15:8];
                default: packed_ascii_at = packed[7:0];
            endcase
        end
    endfunction

    reg [9:0] line_y;
    reg de_q, vs_q;
    reg [23:0] base_rgb_q;
    reg page_enable_q;
    reg text_hit_q;
    reg [3:0] font_col_q;
    reg [1:0] text_kind_q;
    reg [9:0] pixel_y_q;
    reg [7:0] progress_fill_q;

    reg text_request;
    reg ascii_mode;
    reg [7:0] direct_glyph;
    reg [3:0] selected_column;
    reg [3:0] selected_row;
    reg [1:0] selected_kind;
    reg [7:0] selected_ascii;
    reg title_fallback;
    reg artist_fallback;
    reg lyric_fallback;

    wire [9:0] title_dx = pixel_x - `PLAYBACK_TITLE_X;
    wire [9:0] artist_dx = pixel_x - `PLAYBACK_ARTIST_X;
    wire [9:0] time_dx = pixel_x - `PLAYBACK_TIME_X;
    wire [9:0] lyric_dx = pixel_x - `PLAYBACK_LYRIC_X;
    wire title_region = enable && de &&
        (line_y >= `PLAYBACK_TITLE_Y) && (line_y < (`PLAYBACK_TITLE_Y + 10'd16)) &&
        (pixel_x >= `PLAYBACK_TITLE_X) && (pixel_x < (`PLAYBACK_TITLE_X + 10'd256));
    wire artist_region = enable && de &&
        (line_y >= `PLAYBACK_ARTIST_Y) && (line_y < (`PLAYBACK_ARTIST_Y + 10'd16)) &&
        (pixel_x >= `PLAYBACK_ARTIST_X) && (pixel_x < (`PLAYBACK_ARTIST_X + 10'd256));
    wire time_region = enable && de &&
        (line_y >= `PLAYBACK_TIME_Y) && (line_y < (`PLAYBACK_TIME_Y + 10'd16)) &&
        (pixel_x >= `PLAYBACK_TIME_X) && (pixel_x < (`PLAYBACK_TIME_X + 10'd208));
    wire lyric_region = enable && de &&
        (line_y >= `PLAYBACK_LYRIC_Y) && (line_y < (`PLAYBACK_LYRIC_Y + 10'd16)) &&
        (pixel_x >= `PLAYBACK_LYRIC_X) && (pixel_x < (`PLAYBACK_LYRIC_X + 10'd256));
    wire [7:0] selected_font_glyph = ascii_mode ? ascii_glyph : direct_glyph;
    wire [11:0] font_addr_full = {selected_font_glyph, 4'b0000} + {8'd0, selected_row};
    wire [SONG_FONT_ADDR_W-1:0] font_addr = font_addr_full[SONG_FONT_ADDR_W-1:0];
    wire [15:0] font_row;

    song_font_rom u_shared_song_font (
        .clk(clk), .addr(font_addr), .dout(font_row)
    );

    always @* begin
        text_request = 1'b0;
        ascii_mode = 1'b0;
        direct_glyph = 8'd0;
        selected_column = 4'd0;
        selected_row = 4'd0;
        selected_kind = TEXT_TITLE;
        selected_ascii = 8'h20;
        title_fallback = (title_length == 0);
        artist_fallback = (artist_length == 0);
        lyric_fallback = (line_count == 0);
        ascii_code = 8'h20;

        if (title_region) begin
            selected_kind = TEXT_TITLE;
            selected_column = title_dx[7:4];
            selected_row = line_y - `PLAYBACK_TITLE_Y;
            if (title_fallback) begin
                if (selected_column < 8) begin
                    text_request = 1'b1;
                    ascii_mode = 1'b1;
                    case (selected_column)
                        4'd0: selected_ascii = 8'h54; // T
                        4'd1: selected_ascii = 8'h52; // R
                        4'd2: selected_ascii = 8'h41; // A
                        4'd3: selected_ascii = 8'h43; // C
                        4'd4: selected_ascii = 8'h4B; // K
                        4'd5: selected_ascii = 8'h20;
                        4'd6: selected_ascii = 8'h30;
                        default: selected_ascii = 8'd49 + {6'd0, song_id};
                    endcase
                    ascii_code = selected_ascii;
                end
            end else begin
                if (selected_column < title_length) begin
                    text_request = 1'b1;
                    direct_glyph = packed_glyph_at(title_glyphs, selected_column);
                end
            end
        end else if (artist_region) begin
            selected_kind = TEXT_ARTIST;
            selected_column = artist_dx[7:4];
            selected_row = line_y - `PLAYBACK_ARTIST_Y;
            if (artist_fallback) begin
                if (selected_column < 9) begin
                    text_request = 1'b1;
                    ascii_mode = 1'b1;
                    case (selected_column)
                        4'd0: selected_ascii = 8'h41; // A
                        4'd1: selected_ascii = 8'h52; // R
                        4'd2: selected_ascii = 8'h54; // T
                        4'd3: selected_ascii = 8'h49; // I
                        4'd4: selected_ascii = 8'h53; // S
                        4'd5: selected_ascii = 8'h54; // T
                        4'd6: selected_ascii = 8'h20;
                        default: selected_ascii = 8'h2D;
                    endcase
                    ascii_code = selected_ascii;
                end
            end else begin
                if (selected_column < artist_length) begin
                    text_request = 1'b1;
                    direct_glyph = packed_glyph_at(artist_glyphs, selected_column);
                end
            end
        end else if (time_region) begin
            selected_kind = TEXT_TIME;
            selected_column = time_dx[7:4];
            selected_row = line_y - `PLAYBACK_TIME_Y;
            if (selected_column < 13) begin
                text_request = 1'b1;
                ascii_mode = 1'b1;
                selected_ascii = packed_ascii_at(time_ascii, selected_column);
                ascii_code = selected_ascii;
            end
        end else if (lyric_region) begin
            selected_kind = TEXT_LYRIC;
            selected_column = lyric_dx[7:4];
            selected_row = line_y - `PLAYBACK_LYRIC_Y;
            if (lyric_fallback) begin
                if (selected_column < 9) begin
                    text_request = 1'b1;
                    direct_glyph = packed_glyph_at(no_lyrics_glyphs, selected_column);
                end
            end else if (lyric_valid) begin
                if (selected_column < lyric_length) begin
                    text_request = 1'b1;
                    direct_glyph = packed_glyph_at(lyric_glyphs, selected_column);
                end
            end
        end
    end

    wire preserve_media =
        (pixel_x >= `PLAYBACK_MV_X0) && (pixel_x < `PLAYBACK_MV_X1) &&
        (line_y >= `PLAYBACK_MV_Y0) && (line_y < `PLAYBACK_MV_Y1);
    wire preserve_wave =
        (pixel_x >= `PLAYBACK_WAVE_X0) && (pixel_x < `PLAYBACK_WAVE_X1) &&
        (line_y >= `PLAYBACK_WAVE_Y0) && (line_y < `PLAYBACK_WAVE_Y1);
    wire [23:0] base_rgb_in = (enable && de && !preserve_media && !preserve_wave)
                            ? BG_COLOR : rgb_in;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            line_y <= 10'd0;
            de_q <= 1'b0;
            vs_q <= 1'b1;
            base_rgb_q <= 24'h000000;
            page_enable_q <= 1'b0;
            text_hit_q <= 1'b0;
            font_col_q <= 4'd0;
            text_kind_q <= TEXT_TITLE;
            pixel_y_q <= 10'd0;
            progress_fill_q <= 8'd0;
            out_vs <= 1'b1;
            out_de <= 1'b0;
            out_pixel_x <= 10'd0;
        end else begin
            de_q <= de;
            vs_q <= vs;
            if (!vs)
                line_y <= 10'd0;
            else if (de_q && !de)
                line_y <= line_y + 10'd1;

            base_rgb_q <= base_rgb_in;
            page_enable_q <= enable;
            text_hit_q <= text_request;
            font_col_q <= selected_column;
            text_kind_q <= selected_kind;
            pixel_y_q <= line_y;
            progress_fill_q <= progress_fill;
            out_vs <= vs;
            out_de <= de;
            out_pixel_x <= pixel_x;
        end
    end

    wire [9:0] progress_dx = out_pixel_x - `PLAYBACK_PROGRESS_X;
    wire in_progress_bar = out_de &&
        (pixel_y_q >= `PLAYBACK_PROGRESS_Y) &&
        (pixel_y_q < (`PLAYBACK_PROGRESS_Y + 10'd4)) &&
        (out_pixel_x >= `PLAYBACK_PROGRESS_X) &&
        (out_pixel_x < (`PLAYBACK_PROGRESS_X + `PLAYBACK_PROGRESS_W));
    wire in_left_panel =
        (out_pixel_x >= `PLAYBACK_META_X0) && (out_pixel_x < `PLAYBACK_META_X1) &&
        (pixel_y_q >= `PLAYBACK_META_Y0) && (pixel_y_q < `PLAYBACK_META_Y1);
    wire in_right_panel =
        (out_pixel_x >= `PLAYBACK_INFO_X0) && (out_pixel_x < `PLAYBACK_INFO_X1) &&
        (pixel_y_q >= `PLAYBACK_INFO_Y0) && (pixel_y_q < `PLAYBACK_INFO_Y1);
    wire left_border = (out_pixel_x == `PLAYBACK_META_X0) ||
                       (out_pixel_x == (`PLAYBACK_META_X1 - 10'd1)) ||
                       (pixel_y_q == `PLAYBACK_META_Y0) ||
                       (pixel_y_q == (`PLAYBACK_META_Y1 - 10'd1));
    wire right_border = (out_pixel_x == `PLAYBACK_INFO_X0) ||
                        (out_pixel_x == (`PLAYBACK_INFO_X1 - 10'd1)) ||
                        (pixel_y_q == `PLAYBACK_INFO_Y0) ||
                        (pixel_y_q == (`PLAYBACK_INFO_Y1 - 10'd1));
    wire font_pixel = font_row[4'd15 - font_col_q];

    always @* begin
        out_rgb = base_rgb_q;
        if (page_enable_q && out_de) begin
            if (in_left_panel)
                out_rgb = left_border ? BORDER_COLOR : PANEL_COLOR;
            else if (in_right_panel)
                out_rgb = right_border ? BORDER_COLOR : PANEL_COLOR;

            if (in_progress_bar)
                out_rgb = (progress_dx < progress_fill_q) ? PROGRESS_COLOR : TRACK_COLOR;

            if (text_hit_q && font_pixel) begin
                case (text_kind_q)
                    TEXT_ARTIST, TEXT_TIME: out_rgb = SUBTEXT_COLOR;
                    TEXT_LYRIC: out_rgb = LYRIC_COLOR;
                    default: out_rgb = TEXT_COLOR;
                endcase
            end
        end
    end
endmodule
`endif

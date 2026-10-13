`timescale 1ns/1ps
`ifndef EXP_PLAYBACK_PAGE_V
`define EXP_PLAYBACK_PAGE_V
`include "playback_layout.vh"

// Stage 1 playback UI: 320-pixel progress, text-only lyric overlay, compact
// elapsed/total time, and one-cycle RGB/DE/VS/x alignment. The media window is
// preserved from rgb_in; all text shares the existing synchronous song font.
module playback_page (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         vs,
    input  wire         de,
    input  wire [9:0]   pixel_x,
    input  wire         enable,
    input  wire         browse_mode,
    input  wire [23:0]  rgb_in,
    input  wire [1:0]   song_id,
    input  wire [4:0]   title_length,
    input  wire [4:0]   artist_length,
    input  wire [127:0] title_glyphs,
    input  wire [127:0] artist_glyphs,
    input  wire [7:0]   line_count,
    input  wire         lyric_window_valid,
    input  wire         lyric_scroll_active,
    input  wire [29:0]  lyric_row_lengths,
    input  wire [767:0] lyric_row_glyphs,
    input  wire [5:0]   lyric_scroll_offset,
    input  wire [127:0] no_lyrics_glyphs,
    input  wire [8:0]   progress_fill,
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
    localparam [23:0] TEXT_COLOR     = 24'hE6EEF5;
    localparam [23:0] SUBTEXT_COLOR  = 24'hA7B8C8;
    localparam [23:0] PROGRESS_COLOR = 24'hD4AF37;
    localparam [23:0] TRACK_COLOR    = 24'h282830;
    localparam [23:0] BROWSE_BAR_EDGE_COLOR = 24'h3A3528;
    localparam [23:0] BROWSE_DIVIDER_COLOR  = 24'h4A4030;
    localparam [23:0] BROWSE_TRACK_COLOR    = 24'h00CED1;
    localparam [23:0] BROWSE_TITLE_COLOR    = 24'hFFFFFF;
    localparam [23:0] BROWSE_ARTIST_COLOR   = 24'hA09880;
    localparam [23:0] BROWSE_TIME_COLOR     = 24'hD4AF37;
    localparam [23:0] BROWSE_MARK_ACTIVE    = 24'hFFD700;
    localparam [23:0] BROWSE_MARK_IDLE      = 24'h404048;

    localparam [2:0] TEXT_TITLE        = 3'd0;
    localparam [2:0] TEXT_ARTIST       = 3'd1;
    localparam [2:0] TEXT_TIME         = 3'd2;
    localparam [2:0] TEXT_LYRIC        = 3'd3;
    localparam [2:0] BROWSE_TRACK      = 3'd4;
    localparam [2:0] BROWSE_DURATION   = 3'd5;
    localparam [2:0] BROWSE_SEPARATOR  = 3'd6;

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
    reg browse_mode_q;
    reg [1:0] browse_song_id_q;
    reg browse_divider_hit_q;
    reg text_hit_q;
    reg [3:0] font_px_col_q;
    reg [2:0] text_kind_q;
    reg [23:0] text_color_q;
    reg [9:0] pixel_y_q;
    reg [8:0] progress_fill_q;

    reg text_request;
    reg ascii_mode;
    reg [7:0] direct_glyph;
    reg [3:0] selected_column;
    reg [3:0] selected_pixel_col;
    reg [3:0] selected_row;
    reg [2:0] selected_kind;
    reg [7:0] selected_ascii;
    reg title_fallback;
    reg artist_fallback;
    reg [3:0] browse_track_column;
    reg [3:0] browse_time_column;

    wire [9:0] title_dx = pixel_x - `PLAYBACK_TITLE_X;
    wire [9:0] artist_dx = pixel_x - `PLAYBACK_ARTIST_X;
    wire [9:0] time_dx = pixel_x - `PLAYBACK_TIME_X;
    wire [9:0] browse_track_dx = pixel_x - 10'd48;
    wire [8:0] browse_text_dx = pixel_x - 10'd164;
    wire [9:0] browse_time_dx = pixel_x - 10'd544;
    wire [4:0] browse_text_cell = browse_text_dx[8:4];
    wire [3:0] browse_text_subpixel = browse_text_dx[3:0];
    wire [8:0] browse_artist_dx = browse_text_dx - {title_length, 4'b1000};
    wire browse_bar_region = browse_mode && de &&
        (pixel_x >= 10'd32) && (pixel_x < 10'd608) &&
        (line_y >= 10'd416) && (line_y < 10'd457);
    wire browse_track_region = browse_mode && de &&
        (line_y >= 10'd424) && (line_y < 10'd440) &&
        (pixel_x >= 10'd48) && (pixel_x < 10'd136);
    wire browse_text_region = browse_mode && de &&
        (line_y >= 10'd424) && (line_y < 10'd440) &&
        (pixel_x >= 10'd164) && (pixel_x < 10'd524);
    wire browse_time_region = browse_mode && de &&
        (line_y >= 10'd424) && (line_y < 10'd440) &&
        (pixel_x >= 10'd544) && (pixel_x < 10'd584);
    wire browse_divider_region = browse_mode && de &&
        (line_y >= 10'd422) && (line_y < 10'd444) &&
        ((pixel_x == 10'd148) || (pixel_x == 10'd528));
    wire title_region = enable && de &&
        (line_y >= `PLAYBACK_TITLE_Y) && (line_y < (`PLAYBACK_TITLE_Y + 10'd16)) &&
        (pixel_x >= `PLAYBACK_TITLE_X) &&
        (pixel_x < (`PLAYBACK_TITLE_X + 10'd208));
    wire artist_region = enable && de &&
        (line_y >= `PLAYBACK_ARTIST_Y) && (line_y < (`PLAYBACK_ARTIST_Y + 10'd16)) &&
        (pixel_x >= `PLAYBACK_ARTIST_X) &&
        (pixel_x < (`PLAYBACK_ARTIST_X + 10'd208));
    wire time_region = enable && de &&
        (line_y >= `PLAYBACK_TIME_Y) && (line_y < (`PLAYBACK_TIME_Y + 10'd16)) &&
        (pixel_x >= `PLAYBACK_TIME_X) &&
        (pixel_x < (`PLAYBACK_TIME_X + `PLAYBACK_TIME_W));
    wire [7:0] selected_font_glyph = ascii_mode ? ascii_glyph : direct_glyph;
    wire [11:0] font_addr_full = {selected_font_glyph, 4'b0000} + {8'd0, selected_row};
    wire [SONG_FONT_ADDR_W-1:0] font_addr = font_addr_full[SONG_FONT_ADDR_W-1:0];
    wire [15:0] font_row;
    wire lyric_font_request;
    wire [7:0] lyric_font_glyph;
    wire [3:0] lyric_font_column;
    wire [3:0] lyric_font_pixel_column;
    wire [3:0] lyric_font_row;
    wire [23:0] lyric_text_color;

    lrc_five_osd u_lrc_five_osd (
        .enable(enable),.de(de),.pixel_x(pixel_x),.pixel_y(line_y),
        .window_valid(lyric_window_valid),
        .scroll_active(lyric_scroll_active),.row_lengths(lyric_row_lengths),
        .row_glyphs(lyric_row_glyphs),
        .scroll_offset(lyric_scroll_offset),.line_count(line_count),
        .no_lyrics_glyphs(no_lyrics_glyphs),.font_request(lyric_font_request),
        .font_glyph(lyric_font_glyph),.font_column(lyric_font_column),
        .font_pixel_column(lyric_font_pixel_column),.font_row(lyric_font_row),
        .text_color(lyric_text_color)
    );

    song_font_rom u_shared_song_font (
        .clk(clk), .addr(font_addr), .dout(font_row)
    );

    always @* begin
        text_request = 1'b0;
        ascii_mode = 1'b0;
        direct_glyph = 8'd0;
        selected_column = 4'd0;
        selected_pixel_col = 4'd0;
        selected_row = 4'd0;
        selected_kind = TEXT_TITLE;
        selected_ascii = 8'h20;
        title_fallback = (title_length == 0);
        artist_fallback = (artist_length == 0);
        ascii_code = 8'h20;
        browse_track_column = browse_track_dx[6:3];
        browse_time_column = browse_time_dx[5:3];

        if (browse_track_region) begin
            selected_kind = BROWSE_TRACK;
            selected_pixel_col = {1'b0, browse_track_dx[2:0]};
            selected_row = line_y - 10'd424;
            if (browse_track_column < 4'd11) begin
                text_request = 1'b1;
                // Reuse the glyph indices already present in song_text_rom.
                case (browse_track_column)
                    4'd0: direct_glyph = 8'd24; // T
                    4'd1: direct_glyph = 8'd22; // R
                    4'd2: direct_glyph = 8'd14; // A
                    4'd3: direct_glyph = 8'd15; // C
                    4'd4: direct_glyph = 8'd18; // K
                    4'd5: direct_glyph = 8'd0;  // space
                    4'd6: direct_glyph = 8'd3;  // 0
                    4'd7: direct_glyph = 8'd4 + {6'd0, song_id}; // 1..4
                    4'd8: direct_glyph = 8'd2;  // /
                    4'd9: direct_glyph = 8'd3;  // 0
                    default: direct_glyph = 8'd7; // 4
                endcase
            end
        end else if (browse_text_region) begin
            selected_row = line_y - 10'd424;
            if (browse_text_cell < title_length) begin
                selected_kind = TEXT_TITLE;
                selected_column = browse_text_cell[3:0];
                selected_pixel_col = browse_text_subpixel;
                if (selected_column < title_length) begin
                    text_request = 1'b1;
                    direct_glyph = packed_glyph_at(title_glyphs, selected_column);
                end
            end else if ((browse_text_cell == title_length) &&
                         !browse_text_subpixel[3]) begin
                selected_kind = BROWSE_SEPARATOR;
                selected_pixel_col = {1'b0, browse_text_subpixel[2:0]};
                text_request = 1'b1;
                direct_glyph = 8'd1; // compact separator dash
            end else begin
                selected_kind = TEXT_ARTIST;
                selected_column = browse_artist_dx[7:4];
                selected_pixel_col = browse_artist_dx[3:0];
                if (selected_column < artist_length) begin
                    text_request = 1'b1;
                    direct_glyph = packed_glyph_at(artist_glyphs, selected_column);
                end
            end
        end else if (browse_time_region) begin
            selected_kind = BROWSE_DURATION;
            selected_column = browse_time_column;
            selected_pixel_col = {1'b0, browse_time_dx[2:0]};
            selected_row = line_y - 10'd424;
            if (browse_time_column < 4'd5) begin
                text_request = 1'b1;
                ascii_mode = 1'b1;
                // The low 40 bits are the total duration, MM:SS.
                selected_ascii = packed_ascii_at(time_ascii, browse_time_column + 4'd8);
                ascii_code = selected_ascii;
            end
        end else if (title_region) begin
            selected_kind = TEXT_TITLE;
            selected_column = title_dx[7:4];
            selected_pixel_col = title_dx[3:0];
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
            selected_pixel_col = artist_dx[3:0];
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
            // 13 compact 8-pixel cells occupy 104 pixels. The existing
            // 16x16 glyph row is sampled at every other column; no font ROM
            // or read port is added.
            selected_column = time_dx[6:3];
            selected_pixel_col = {1'b0, time_dx[2:0]};
            selected_row = line_y - `PLAYBACK_TIME_Y;
            if (selected_column < 13) begin
                text_request = 1'b1;
                ascii_mode = 1'b1;
                selected_ascii = packed_ascii_at(time_ascii, selected_column);
                ascii_code = selected_ascii;
            end
        end else if (lyric_font_request) begin
            selected_kind = TEXT_LYRIC;
            selected_column = lyric_font_column;
            selected_pixel_col = lyric_font_pixel_column;
            selected_row = lyric_font_row;
            direct_glyph = lyric_font_glyph;
            text_request = lyric_font_request;
        end
    end

    wire preserve_media =
        (pixel_x >= `PLAYBACK_MV_X0) && (pixel_x < `PLAYBACK_MV_X1) &&
        (line_y >= `PLAYBACK_MV_Y0) && (line_y < `PLAYBACK_MV_Y1);
    wire [23:0] dimmed_cover_rgb =
        {1'b0, rgb_in[23:17], 1'b0, rgb_in[15:9], 1'b0, rgb_in[7:1]};
    wire [23:0] base_rgb_in = browse_bar_region
                            ? (((line_y == 10'd416) || (line_y == 10'd456))
                               ? BROWSE_BAR_EDGE_COLOR : dimmed_cover_rgb)
                            : ((enable && de && !preserve_media)
                               ? BG_COLOR : rgb_in);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            line_y <= 10'd0;
            de_q <= 1'b0;
            vs_q <= 1'b1;
            base_rgb_q <= 24'h000000;
            page_enable_q <= 1'b0;
            browse_mode_q <= 1'b0;
            browse_song_id_q <= 2'd0;
            browse_divider_hit_q <= 1'b0;
            text_hit_q <= 1'b0;
            font_px_col_q <= 4'd0;
            text_kind_q <= TEXT_TITLE;
            text_color_q <= TEXT_COLOR;
            pixel_y_q <= 10'd0;
            progress_fill_q <= 9'd0;
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
            page_enable_q <= enable || browse_mode;
            browse_mode_q <= browse_mode;
            browse_song_id_q <= song_id;
            browse_divider_hit_q <= browse_divider_region;
            text_hit_q <= text_request;
            font_px_col_q <= selected_pixel_col;
            text_kind_q <= selected_kind;
            text_color_q <= lyric_text_color;
            pixel_y_q <= line_y;
            progress_fill_q <= progress_fill;
            out_vs <= vs;
            out_de <= de;
            out_pixel_x <= pixel_x;
        end
    end

    wire [9:0] progress_dx = out_pixel_x - `PLAYBACK_PROGRESS_X;
    wire [9:0] progress_dy = pixel_y_q - `PLAYBACK_PROGRESS_Y;
    wire in_progress_bar = out_de &&
        (progress_dy < `PLAYBACK_PROGRESS_H) &&
        (progress_dx < `PLAYBACK_PROGRESS_W);
    wire in_progress_fill = in_progress_bar &&
        (progress_dx < {1'b0, progress_fill_q});
    wire progress_track_row = (progress_dy == 10'd1);
    wire [9:0] browse_marker_dx = out_pixel_x - 10'd288;
    wire [9:0] browse_marker_dy = pixel_y_q - 10'd464;
    wire in_browse_marker = out_de && browse_mode_q &&
        (browse_marker_dy < 10'd3) && (browse_marker_dx < 10'd64);
    wire browse_marker_active = (browse_marker_dx[5:4] == browse_song_id_q);
    wire browse_marker_idle_pixel = (browse_marker_dx[3:0] >= 4'd6) &&
                                    (browse_marker_dx[3:0] < 4'd10);
    wire font_half_width = (text_kind_q == TEXT_TIME) ||
                           (text_kind_q == BROWSE_TRACK) ||
                           (text_kind_q == BROWSE_DURATION) ||
                           (text_kind_q == BROWSE_SEPARATOR);
    wire font_pixel = font_half_width
                    ? font_row[4'd15 - {font_px_col_q[2:0], 1'b0}]
                    : font_row[4'd15 - font_px_col_q];

    always @* begin
        out_rgb = out_de ? base_rgb_q : 24'h000000;
        if (page_enable_q && out_de) begin
            if (browse_mode_q) begin
                if (browse_divider_hit_q) out_rgb = BROWSE_DIVIDER_COLOR;
                if (in_browse_marker) begin
                    if (browse_marker_active)
                        out_rgb = BROWSE_MARK_ACTIVE;
                    else if (browse_marker_idle_pixel)
                        out_rgb = BROWSE_MARK_IDLE;
                end
            end else begin
                if (in_progress_bar) begin
                    if (in_progress_fill)
                        out_rgb = PROGRESS_COLOR;
                    else if (progress_track_row)
                        out_rgb = TRACK_COLOR;
                end
            end

            if (text_hit_q && font_pixel) begin
                case (text_kind_q)
                    TEXT_ARTIST:
                        out_rgb = browse_mode_q ? BROWSE_ARTIST_COLOR : SUBTEXT_COLOR;
                    TEXT_TIME: out_rgb = SUBTEXT_COLOR;
                    TEXT_LYRIC: out_rgb = text_color_q;
                    BROWSE_TRACK: out_rgb = BROWSE_TRACK_COLOR;
                    BROWSE_DURATION: out_rgb = BROWSE_TIME_COLOR;
                    BROWSE_SEPARATOR: out_rgb = BROWSE_ARTIST_COLOR;
                    default: out_rgb = browse_mode_q ? BROWSE_TITLE_COLOR : TEXT_COLOR;
                endcase
            end
        end
    end
endmodule
`endif

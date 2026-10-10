`timescale 1ns/1ps
`ifndef EXP_LRC_MULTISONG_OSD_V
`define EXP_LRC_MULTISONG_OSD_V
// D9: four-song compile-time text ROM consumer. The line table is scanned
// once per frame during blanking; the selected lyric is then held for the
// whole frame. Song ID, generation and audio time are captured together at
// frame start so an old scan cannot leak into the next song.
module lrc_multisong_osd #(
    parameter RENDER_ENABLE = 1'b1
)(
    input  wire         clk,
    input  wire         rst_n,
    input  wire         vs,
    input  wire         de,
    input  wire [9:0]   pixel_x,
    input  wire         enable,
    input  wire [31:0]  time_ms,
    input  wire [1:0]   song_id_async,
    input  wire         generation_async,
    input  wire [7:0]   rom_line_count,
    input  wire         rom_line_valid,
    input  wire [31:0]  rom_line_time_ms,
    input  wire [4:0]   rom_line_length,
    input  wire [127:0] rom_line_glyphs,
    input  wire [127:0] no_lyrics_glyphs,
    output reg  [1:0]   song_id_frame,
    output reg          generation_frame,
    output reg  [6:0]   rom_line_index,
    output reg  [7:0]   song_line_count_frame,
    output reg          current_lyric_valid,
    output reg  [6:0]   current_lyric_index,
    output reg  [4:0]   current_lyric_length,
    output reg  [127:0] current_lyric_glyphs,
    input  wire [23:0]  rgb_in,
    output wire [23:0]  rgb_out,
    output wire         hit
);
    `include "lrc_geom.vh"
    `include "song_text_geom.vh"

    localparam [2:0] ST_IDLE  = 3'd0;
    localparam [2:0] ST_PREP  = 3'd1;
    localparam [2:0] ST_ISSUE = 3'd2;
    localparam [2:0] ST_SCAN  = 3'd3;
    localparam [2:0] ST_DONE  = 3'd4;

    reg [2:0] state;
    reg [11:0] line_y;
    reg de_q, vs_q;
    wire frame_start = vs_q && !vs;
    reg [31:0] frame_time_ms;
    reg [7:0] issue_index;
    reg [6:0] pending_index;
    reg pending_valid;
    reg [6:0] selected_index;
    reg [4:0] selected_length;
    reg [127:0] selected_glyphs;
    reg selected_valid;

    always @* begin
        if ((state == ST_ISSUE) || (state == ST_SCAN))
            rom_line_index = issue_index[6:0];
        else
            rom_line_index = 7'd0;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            song_id_frame <= 2'd0;
            generation_frame <= 1'b0;
            song_line_count_frame <= 8'd0;
            frame_time_ms <= 32'd0;
            issue_index <= 8'd0;
            pending_index <= 7'd0;
            pending_valid <= 1'b0;
            selected_index <= 7'd0;
            selected_length <= 5'd0;
            selected_glyphs <= 128'd0;
            selected_valid <= 1'b0;
            current_lyric_valid <= 1'b0;
            current_lyric_index <= 7'd0;
            current_lyric_length <= 5'd0;
            current_lyric_glyphs <= 128'd0;
            line_y <= 12'd0;
            de_q <= 1'b0;
            vs_q <= 1'b1;
        end else begin
            de_q <= de;
            vs_q <= vs;
            if (!vs)
                line_y <= 12'd0;
            else if (de_q && !de)
                line_y <= line_y + 12'd1;

            if (frame_start) begin
                song_id_frame <= song_id_async;
                generation_frame <= generation_async;
                frame_time_ms <= time_ms;
                song_line_count_frame <= 8'd0;
                state <= ST_PREP;
                issue_index <= 8'd0;
                pending_valid <= 1'b0;
                selected_index <= 7'd0;
                selected_length <= 5'd0;
                selected_glyphs <= 128'd0;
                selected_valid <= 1'b0;
                current_lyric_valid <= 1'b0;
                current_lyric_index <= 7'd0;
                current_lyric_length <= 5'd0;
                current_lyric_glyphs <= 128'd0;
            end else begin
                case (state)
                    ST_PREP: begin
                        // The ROM's combinational metadata now reflects the
                        // song ID latched at the preceding frame boundary.
                        song_line_count_frame <= rom_line_count;
                        issue_index <= 8'd0;
                        pending_valid <= 1'b0;
                        state <= ST_ISSUE;
                    end
                    ST_ISSUE: begin
                        if (song_line_count_frame == 0) begin
                            state <= ST_DONE;
                        end else begin
                            // The synchronous ROM samples row zero on this edge.
                            issue_index <= 8'd1;
                            pending_index <= 7'd0;
                            pending_valid <= 1'b1;
                            state <= ST_SCAN;
                        end
                    end
                    ST_SCAN: begin
                        if (pending_valid && rom_line_valid &&
                            (rom_line_time_ms <= frame_time_ms)) begin
                            selected_index <= pending_index;
                            selected_length <= rom_line_length;
                            selected_glyphs <= rom_line_glyphs;
                            selected_valid <= 1'b1;
                        end

                        if (issue_index < song_line_count_frame) begin
                            // Issue one row while consuming the prior row.
                            pending_index <= issue_index[6:0];
                            pending_valid <= 1'b1;
                            issue_index <= issue_index + 8'd1;
                        end else begin
                            pending_valid <= 1'b0;
                            if (pending_valid) begin
                                state <= ST_DONE;
                                current_lyric_valid <= selected_valid ||
                                    (rom_line_valid && (rom_line_time_ms <= frame_time_ms));
                                if (rom_line_valid && (rom_line_time_ms <= frame_time_ms)) begin
                                    current_lyric_index <= pending_index;
                                    current_lyric_length <= rom_line_length;
                                    current_lyric_glyphs <= rom_line_glyphs;
                                end else if (selected_valid) begin
                                    current_lyric_index <= selected_index;
                                    current_lyric_length <= selected_length;
                                    current_lyric_glyphs <= selected_glyphs;
                                end
                            end else begin
                                state <= ST_DONE;
                            end
                        end
                    end
                    default: ;
                endcase
            end
        end
    end

    generate if (RENDER_ENABLE) begin : gen_single_line_renderer
        reg [15:0] row_cache;
        reg [7:0] cur_glyph;
        wire [11:0] dx12 = {2'b00, pixel_x} - LRC_OSD_X;
        wire [11:0] dy12 = line_y - LRC_OSD_Y;
        wire in_box = enable && de &&
                      (dx12 < (LRC_CHARS_PER_LINE * LRC_GLYPH_W)) &&
                      (dy12 < LRC_GLYPH_H);
        wire [11:0] fetch_dx = dx12 + 12'd1;
        wire [3:0] char_sel = fetch_dx[7:4];
        wire [3:0] col_pix = dx12[3:0];
        wire [3:0] row_sel = dy12[3:0];
        wire [127:0] display_glyphs =
            (song_line_count_frame == 0) ? no_lyrics_glyphs : current_lyric_glyphs;
        wire [11:0] font_addr_full = {cur_glyph, 4'b0000} + {8'd0, row_sel};
        wire [SONG_FONT_ADDR_W-1:0] font_addr = font_addr_full[SONG_FONT_ADDR_W-1:0];
        wire [15:0] font_row;

        song_font_rom u_song_font_rom (.clk(clk), .addr(font_addr), .dout(font_row));

        always @* begin
            case (char_sel)
                4'd0:  cur_glyph = display_glyphs[7:0];
                4'd1:  cur_glyph = display_glyphs[15:8];
                4'd2:  cur_glyph = display_glyphs[23:16];
                4'd3:  cur_glyph = display_glyphs[31:24];
                4'd4:  cur_glyph = display_glyphs[39:32];
                4'd5:  cur_glyph = display_glyphs[47:40];
                4'd6:  cur_glyph = display_glyphs[55:48];
                4'd7:  cur_glyph = display_glyphs[63:56];
                4'd8:  cur_glyph = display_glyphs[71:64];
                4'd9:  cur_glyph = display_glyphs[79:72];
                4'd10: cur_glyph = display_glyphs[87:80];
                4'd11: cur_glyph = display_glyphs[95:88];
                4'd12: cur_glyph = display_glyphs[103:96];
                4'd13: cur_glyph = display_glyphs[111:104];
                4'd14: cur_glyph = display_glyphs[119:112];
                default: cur_glyph = display_glyphs[127:120];
            endcase
        end

        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) row_cache <= 16'h0000;
            else if (de && col_pix == 4'd0) row_cache <= font_row;
        end

        wire [15:0] render_row = (col_pix == 4'd0) ? font_row : row_cache;
        assign hit = in_box && render_row[15 - col_pix];
        assign rgb_out = hit ? LRC_COLOR : rgb_in;
    end else begin : gen_no_renderer
        assign hit = 1'b0;
        assign rgb_out = rgb_in;
    end endgenerate
endmodule
`endif

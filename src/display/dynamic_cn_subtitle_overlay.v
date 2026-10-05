`timescale 1ns/1ps

// Single-line, frame-committed Chinese subtitle renderer.
module dynamic_cn_subtitle_overlay #(
    parameter integer H_ACTIVE = 640,
    parameter integer V_ACTIVE = 480,
    parameter integer CELL_W = 18,
    parameter integer CELL_H = 18,
    parameter integer SUBTITLE_Y = V_ACTIVE - 30
) (
    input  wire        src_clk,
    input  wire        src_rst_n,
    input  wire        commit_toggle,
    input  wire        commit_bank,
    input  wire [5:0]  commit_length,

    input  wire        video_clk,
    input  wire        video_rst_n,
    input  wire        vsync,
    input  wire        de,
    input  wire [9:0]  pixel_x,
    input  wire [23:0] rgb_in,

    output wire [5:0]  text_raddr,
    input  wire [4:0]  text_rdata,
    output wire [9:0]  glyph_raddr,
    input  wire [15:0] glyph_rdata,
    output wire [23:0] rgb_out,
    output wire        de_out,
    output wire        vs_out,
    output wire        active
);
    reg        line_vsync_q;
    reg        line_de_q;
    reg [11:0] line_y;
    reg [2:0]  commit_sync;
    reg [2:0]  bank_sync;
    reg [5:0]  length_sync1;
    reg [5:0]  length_sync2;
    reg        commit_seen;
    reg        active_bank;
    reg [5:0]  active_length;

    wire frame_start = line_vsync_q && !vsync;

    always @(posedge video_clk or negedge video_rst_n) begin
        if (!video_rst_n) begin
            line_vsync_q <= 1'b1;
            line_de_q    <= 1'b0;
            line_y       <= 12'd0;
            commit_sync  <= 3'b000;
            bank_sync    <= 3'b000;
            length_sync1 <= 6'd0;
            length_sync2 <= 6'd0;
            commit_seen  <= 1'b0;
            active_bank  <= 1'b0;
            active_length <= 6'd0;
        end else begin
            line_vsync_q <= vsync;
            line_de_q    <= de;
            commit_sync  <= {commit_sync[1:0], commit_toggle};
            bank_sync    <= {bank_sync[1:0], commit_bank};
            length_sync1 <= commit_length;
            length_sync2 <= length_sync1;

            if (!vsync)
                line_y <= 12'd0;
            else if (line_de_q && !de)
                line_y <= line_y + 12'd1;

            if (frame_start && (commit_sync[2] != commit_seen)) begin
                active_bank   <= bank_sync[2];
                active_length <= length_sync2;
                commit_seen   <= commit_sync[2];
            end
        end
    end

    integer text_width;
    integer text_start_x;
    integer char_index;
    integer glyph_col;
    integer local_y;
    reg [5:0] text_raddr_reg;
    reg [9:0] glyph_raddr_reg;
    reg       band_pixel;
    reg       glyph_area;
    reg [3:0] glyph_row_index;

    always @* begin
        text_width       = 0;
        text_start_x     = 0;
        char_index       = 0;
        glyph_col        = 0;
        local_y          = 0;
        text_raddr_reg   = 6'd0;
        glyph_raddr_reg  = 10'd0;
        band_pixel       = 1'b0;
        glyph_area       = 1'b0;
        glyph_row_index  = 4'd0;

        if (de && (active_length != 0) &&
            (line_y >= SUBTITLE_Y) &&
            (line_y < SUBTITLE_Y + CELL_H)) begin
            text_width   = active_length * CELL_W;
            text_start_x = (H_ACTIVE - text_width) / 2;
            local_y      = line_y - SUBTITLE_Y;

            if ((pixel_x >= text_start_x) &&
                (pixel_x < text_start_x + text_width)) begin
                band_pixel = 1'b1;
                if ((local_y >= 1) && (local_y <= 16)) begin
                    char_index = (pixel_x - text_start_x) / CELL_W;
                    glyph_col  = (pixel_x - text_start_x) -
                                 (char_index * CELL_W);
                    if ((char_index < active_length) &&
                        (glyph_col >= 1) && (glyph_col <= 16)) begin
                        text_raddr_reg  = {active_bank, char_index[4:0]};
                        glyph_row_index = local_y - 1;
                        glyph_area      = 1'b1;
                    end
                end
            end
        end
    end

    assign text_raddr = text_raddr_reg;
    assign glyph_raddr = glyph_area ?
                         {active_bank, text_rdata, glyph_row_index} : 10'd0;

    reg        de_d;
    reg        vs_d;
    reg        band_pixel_d;
    reg        glyph_area_d;
    reg [4:0]  glyph_col_d;
    reg [23:0] rgb_in_d;

    always @(posedge video_clk or negedge video_rst_n) begin
        if (!video_rst_n) begin
            de_d         <= 1'b0;
            vs_d         <= 1'b1;
            band_pixel_d <= 1'b0;
            glyph_area_d <= 1'b0;
            glyph_col_d  <= 5'd0;
            rgb_in_d     <= 24'd0;
        end else begin
            de_d         <= de;
            vs_d         <= vsync;
            band_pixel_d <= band_pixel;
            glyph_area_d <= glyph_area;
            glyph_col_d  <= glyph_col[4:0];
            rgb_in_d     <= rgb_in;
        end
    end

    wire [4:0] glyph_bit_index = 5'd15 - (glyph_col_d - 5'd1);
    wire       text_pixel = glyph_area_d && (glyph_col_d != 5'd0) ?
                            glyph_rdata[glyph_bit_index] : 1'b0;

    assign rgb_out = band_pixel_d ?
                     (text_pixel ? 24'hFFFFFF : 24'h101010) : rgb_in_d;
    assign de_out  = de_d;
    assign vs_out  = vs_d;
    assign active  = band_pixel_d;
endmodule

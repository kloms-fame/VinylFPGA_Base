`timescale 1ns/1ps
`ifndef EXP_LRC_OSD_V
`define EXP_LRC_OSD_V
// =============================================================================
// lrc_osd —— S5：单行歌词叠加（按 48 kHz 毫秒时基选行）
//
// 只认 timebase_48k 给出的 cur_time_ms：本模块不做任何时间计数，
// 因此"歌词与音频同源"由结构保证，不会各自漂移。
//
// 每帧的消隐期做两件事（时间充裕，25 MHz 下 >3 万拍）：
//   1) 顺序扫描行表，选出行时间 <= cur_time_ms 的**最后一行**；
//   2) 把该行的字形号读进 16 个寄存器。
// 像素期只剩"16:1 字形选择 + 字库一次查表 + 位选"，路径短且与行号无关。
//
// 几何/字形数/颜色来自 src/include/lrc_geom.vh（由 tools/gen_lrc_assets.py 生成）。
// =============================================================================
module lrc_osd (
    input  wire        clk,          // video_clk
    input  wire        rst_n,
    input  wire        vs,           // 低有效场同步（与 mainline 一致）
    input  wire        de,
    input  wire [9:0]  pixel_x,
    input  wire        enable,       // 1=播放态才显示
    input  wire [31:0] time_ms,
    input  wire [23:0] rgb_in,
    output wire [23:0] rgb_out,
    output wire        hit
);
    `include "lrc_geom.vh"

    localparam integer LINE_IDX_W = 4;

    // ---- 行计数器（与 osd_overlay_24 相同的重建方式，与极性无关的帧边界）----
    reg [11:0] line_y;
    reg        de_q;
    reg        vs_q;
    wire       frame_start = vs_q && !vs;

    // ---- 行表 / 字库读取 ----
    reg  [LINE_IDX_W-1:0] scan_idx;
    reg  [LINE_IDX_W-1:0] load_col;
    reg  [LINE_IDX_W-1:0] line_sel;
    reg  [3:0]            scan_state;   // 0=idle 1=scan 2=load
    wire [31:0] rom_time;
    wire [7:0]  rom_glyph;

    reg  [7:0] glyph0, glyph1, glyph2, glyph3, glyph4, glyph5, glyph6, glyph7;
    reg  [7:0] glyph8, glyph9, glyph10, glyph11, glyph12, glyph13, glyph14, glyph15;

    lrc_lines_rom u_lines_rom (
        .line    (scan_state == 4'd1 ? scan_idx : line_sel),
        .col     (load_col),
        .time_ms (rom_time),
        .glyph   (rom_glyph)
    );

    reg  [7:0] cur_glyph;
    wire [LRC_FONT_ADDR_W-1:0] font_addr;
    wire [15:0] font_row;

    lrc_font_rom u_font_rom (
        .addr (font_addr),
        .dout (font_row)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            line_y    <= 12'd0;
            de_q      <= 1'b0;
            vs_q      <= 1'b1;
            scan_state<= 4'd0;
            scan_idx  <= 4'd0;
            load_col  <= 4'd0;
            line_sel  <= 4'd0;
            glyph0 <= 8'd0;  glyph1 <= 8'd0;  glyph2 <= 8'd0;  glyph3 <= 8'd0;
            glyph4 <= 8'd0;  glyph5 <= 8'd0;  glyph6 <= 8'd0;  glyph7 <= 8'd0;
            glyph8 <= 8'd0;  glyph9 <= 8'd0;  glyph10 <= 8'd0; glyph11 <= 8'd0;
            glyph12 <= 8'd0; glyph13 <= 8'd0; glyph14 <= 8'd0; glyph15 <= 8'd0;
        end else begin
            de_q <= de;
            vs_q <= vs;
            if (!vs)
                line_y <= 12'd0;
            else if (de_q && !de)
                line_y <= line_y + 12'd1;

            case (scan_state)
            4'd0: begin
                if (frame_start) begin
                    scan_state <= 4'd1;
                    scan_idx   <= 4'd0;
                    line_sel   <= 4'd0;
                end
            end
            4'd1: begin
                // 顺序扫行表：取"行时间 <= 当前时间"的最后一行
                if (scan_idx >= LRC_LINE_COUNT) begin
                    scan_state <= 4'd2;
                    load_col   <= 4'd0;
                end else begin
                    if ((rom_time <= time_ms) && (rom_time != 32'hFFFFFFFF))
                        line_sel <= scan_idx;
                    scan_idx <= scan_idx + 4'd1;
                end
            end
            4'd2: begin
                // 把选中行的 16 个字形号读进寄存器
                case (load_col)
                    4'd0:  glyph0  <= rom_glyph;
                    4'd1:  glyph1  <= rom_glyph;
                    4'd2:  glyph2  <= rom_glyph;
                    4'd3:  glyph3  <= rom_glyph;
                    4'd4:  glyph4  <= rom_glyph;
                    4'd5:  glyph5  <= rom_glyph;
                    4'd6:  glyph6  <= rom_glyph;
                    4'd7:  glyph7  <= rom_glyph;
                    4'd8:  glyph8  <= rom_glyph;
                    4'd9:  glyph9  <= rom_glyph;
                    4'd10: glyph10 <= rom_glyph;
                    4'd11: glyph11 <= rom_glyph;
                    4'd12: glyph12 <= rom_glyph;
                    4'd13: glyph13 <= rom_glyph;
                    4'd14: glyph14 <= rom_glyph;
                    default: glyph15 <= rom_glyph;
                endcase
                if (load_col == 4'd15)
                    scan_state <= 4'd0;
                else
                    load_col <= load_col + 4'd1;
            end
            default: scan_state <= 4'd0;
            endcase
        end
    end

    // ---- 像素期：字形选择 + 字库查表 + 位选 ----
    wire [11:0] dx12 = {2'b00, pixel_x} - LRC_OSD_X;
    wire [11:0] dy12 = line_y - LRC_OSD_Y;
    wire        in_box = enable && de &&
                         (dx12 < (LRC_CHARS_PER_LINE * LRC_GLYPH_W)) &&
                         (dy12 < LRC_GLYPH_H);
    wire [LINE_IDX_W-1:0] char_sel = dx12[7:4];    // /16（LRC_GLYPH_W=16, SCALE=1）
    wire [3:0]            col_pix  = dx12[3:0];
    wire [3:0]            row_sel  = dy12[3:0];

    always @* begin
        case (char_sel)
            4'd0:  cur_glyph = glyph0;
            4'd1:  cur_glyph = glyph1;
            4'd2:  cur_glyph = glyph2;
            4'd3:  cur_glyph = glyph3;
            4'd4:  cur_glyph = glyph4;
            4'd5:  cur_glyph = glyph5;
            4'd6:  cur_glyph = glyph6;
            4'd7:  cur_glyph = glyph7;
            4'd8:  cur_glyph = glyph8;
            4'd9:  cur_glyph = glyph9;
            4'd10: cur_glyph = glyph10;
            4'd11: cur_glyph = glyph11;
            4'd12: cur_glyph = glyph12;
            4'd13: cur_glyph = glyph13;
            4'd14: cur_glyph = glyph14;
            default: cur_glyph = glyph15;
        endcase
    end

    // font_addr = 字形号*16 + 行号（16x16 点阵，每行 16bit）
    wire [11:0] font_addr_full = {cur_glyph, 4'b0000} + {8'd0, row_sel};
    assign font_addr = font_addr_full[LRC_FONT_ADDR_W-1:0];
    assign hit = in_box && font_row[15 - col_pix];
    assign rgb_out = hit ? LRC_COLOR : rgb_in;

endmodule
`endif

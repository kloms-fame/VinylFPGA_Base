`timescale 1ns/1ps
`ifndef EXP_VINYL_RENDERER_V
`define EXP_VINYL_RENDERER_V
// =============================================================================
// vinyl_renderer —— S6：黑胶转盘视觉层（无 MV 曲目的默认视觉）
//
// 纯组合像素层：只按 (pixel_x,pixel_y) 与 phase 生成黑胶盘面，不读 SD/SDRAM，
// 因此天然满足"无 MV 曲目显示黑胶贴图、不黑屏"，也不会抢占音频带宽。
//
// 盘面构成（整屏居中，半径 VINYL_R）：
//   * 盘体：近黑；纹路用"距离平方右移一位"做同心环带（越靠外越密，与真实黑胶一致）
//   * 标签：中心暖红色圆
//   * 转动高光：按 phase 旋转的径向亮带，用来表现"唱片在转"
//
// dx/dy 各一次乘法得 d2；高光只用比较和象限，不使用三角乘法。
// 实际时序以当前完整工程的 TD route 报告为准。
// =============================================================================
module vinyl_renderer #(
    parameter integer VINYL_CX   = 320,
    parameter integer VINYL_CY   = 206,
    parameter integer VINYL_R    = 148,   // 盘半径
    parameter integer LABEL_R    = 46,    // 标签半径
    parameter [23:0]  DISC_DARK  = 24'h0A0A0C,
    parameter [23:0]  DISC_GROOVE= 24'h1C1C22,
    parameter [23:0]  LABEL_RGB  = 24'hB23A2E,
    parameter [23:0]  SHINE_RGB  = 24'h3A3A46,
    parameter [23:0]  OUTER_RGB  = 24'h50505C
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        de,
    input  wire [9:0]  pixel_x,
    input  wire [9:0]  pixel_y,
    input  wire [7:0]  phase,        // 旋转相位（由 48kHz 时基推进；暂停时冻结）
    input  wire        enable,
    input  wire [23:0] rgb_in,
    output wire [23:0] rgb_out,
    output wire        hit
);
    wire signed [11:0] dx = $signed({2'b00, pixel_x}) - $signed(VINYL_CX[11:0]);
    wire signed [11:0] dy = $signed({2'b00, pixel_y}) - $signed(VINYL_CY[11:0]);

    // 距离平方（省掉开方）
    wire [23:0] dx2 = dx * dx;
    wire [23:0] dy2 = dy * dy;
    wire [24:0] d2  = dx2 + dy2;

    localparam integer R2       = VINYL_R  * VINYL_R;
    localparam integer LABEL_R2 = LABEL_R  * LABEL_R;
    localparam integer RIM_R2   = (VINYL_R - 3) * (VINYL_R - 3);

    // 径向旋转高光：**不用乘法器**。把平面按"主导轴 + 象限"粗分成 8 个扇区
    // （等价于低精度 atan2），再与 phase 的高 3 位比较。
    // 这样整层只有 d2 的 2 个乘法器；实测用 sin/cos 乘法会把 DSP 从 12 抬到 16~21，
    // 反而把 100 MHz 既有 FAT32 路径挤到负 slack。
    wire [11:0] adx = dx[11] ? (~dx + 12'd1) : dx;
    wire [11:0] ady = dy[11] ? (~dy + 12'd1) : dy;
    wire        diag = (adx > ady);           // 1: |dx| 更大
    reg  [2:0]  sector;
    always @* begin
        if (!dy[11])                              // dy >= 0（下半平面）
            sector = dx[11] ? (diag ? 3'd3 : 3'd2) : (diag ? 3'd0 : 3'd1);
        else                                      // dy < 0（上半平面）
            sector = dx[11] ? (diag ? 3'd4 : 3'd5) : (diag ? 3'd7 : 3'd6);
    end
    wire shine = (sector == phase[7:5]) && (d2 > 24'd1024) && (d2 < RIM_R2);

    wire in_disc  = (d2 < R2);
    wire in_label = (d2 < LABEL_R2);
    wire in_rim   = (d2 > RIM_R2) && (d2 < R2);
    // 纹路：距离平方每 1024 交替一次；靠外环带更密更暗
    wire groove   = d2[11] ^ d2[9];

    wire [23:0] disc_px = in_rim ? OUTER_RGB :
                          (groove ? DISC_GROOVE : DISC_DARK);
    wire [23:0] vinyl_px = in_label ? LABEL_RGB :
                           (shine ? SHINE_RGB : disc_px);

    assign hit     = enable && de && in_disc;
    assign rgb_out = hit ? vinyl_px : rgb_in;
endmodule
`endif

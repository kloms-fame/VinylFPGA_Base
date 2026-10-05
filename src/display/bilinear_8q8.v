`timescale 1ns/1ps

// =============================================================================
// 第十三讲 3.3.1 双线性插值定点实现（教程选做件）
//   教程只给了 R 通道示例，并把 G/B 通道留成 TODO。
//   本文件按教程给出的写法把 G/B 通道补全（同样的 8Q8 定点、同样的
//   "每步取高 8 位再列加权"），保持与 R 通道完全同构。
//
//   两个综合陷阱（教程明确点名，必须遵守）：
//     ① 权重补数用 9'd256 - {1'b0, wx}，不能写 8'd256（会被截成 0）；
//     ② 行加权结果先取 [15:8] 再做列加权，否则 16 位装不下被静默截断。
//
//   本模块当前只在仿真中做回归，未被顶层实例化（与完赛工程一致：
//   thumbnail_layout 走最近邻，双线性属于扩展升级项）。
// =============================================================================
module bilinear_8q8 (
    input  wire [7:0] p00_r, p10_r, p01_r, p11_r,
    input  wire [7:0] p00_g, p10_g, p01_g, p11_g,
    input  wire [7:0] p00_b, p10_b, p01_b, p11_b,
    input  wire [7:0] wx, wy,
    output wire [7:0] out_r, out_g, out_b
);
    // ---- R 通道（教程原样）----
    wire [8:0]  inv_wx       = 9'd256 - {1'b0, wx};
    wire [8:0]  inv_wy       = 9'd256 - {1'b0, wy};
    wire [15:0] row_top_r    = p00_r * inv_wx + p10_r * wx;
    wire [15:0] row_bottom_r = p01_r * inv_wx + p11_r * wx;
    wire [15:0] out_r_full   = row_top_r[15:8] * inv_wy + row_bottom_r[15:8] * wy;
    assign out_r = out_r_full[15:8];

    // ---- G 通道（照抄 R 通道）----
    wire [15:0] row_top_g    = p00_g * inv_wx + p10_g * wx;
    wire [15:0] row_bottom_g = p01_g * inv_wx + p11_g * wx;
    wire [15:0] out_g_full   = row_top_g[15:8] * inv_wy + row_bottom_g[15:8] * wy;
    assign out_g = out_g_full[15:8];

    // ---- B 通道（照抄 R 通道）----
    wire [15:0] row_top_b    = p00_b * inv_wx + p10_b * wx;
    wire [15:0] row_bottom_b = p01_b * inv_wx + p11_b * wx;
    wire [15:0] out_b_full   = row_top_b[15:8] * inv_wy + row_bottom_b[15:8] * wy;
    assign out_b = out_b_full[15:8];
endmodule

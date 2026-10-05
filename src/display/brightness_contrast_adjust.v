`timescale 1ns/1ps

// =============================================================================
// 第十四讲：亮度/对比度调节（教程 3.2 练习骨架 + 3.2.2 参考答案）
//
// 亮度采用教程 2.1 中完赛工程的实际做法：
//   bright = rgb * (brightness + 1) / 256
// 取 +1 是为了让 brightness=255 时严格回到 256/256，即默认参数下
// 逐位旁路，不改变前面 13 讲已经验证过的稳定显示和转场行为。
//
// 对比度严格采用教程 3.2.2 的参考答案：
//   out = saturate((bright - 128) * contrast / 128 + 128)
// 其中 /128 使用算术右移 >>>7，保证负数方向正确。
// =============================================================================
module brightness_contrast_adjust (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        in_de,
    input  wire [23:0] rgb_in,
    input  wire [7:0]  brightness,   // 帧边界锁存后的亮度
    input  wire [7:0]  contrast,     // 帧边界锁存后的对比度
    output reg         out_de,
    output reg  [23:0] rgb_out
);
    // ---- 亮度通路：每通道 × (brightness+1) 后取高 8 位，即 /256 ----
    wire [8:0] brightness_eff = {1'b0, brightness} + 9'd1;

    wire [16:0] mul_r = {8'd0, rgb_in[23:16]} * brightness_eff;
    wire [16:0] mul_g = {8'd0, rgb_in[15:8]}  * brightness_eff;
    wire [16:0] mul_b = {8'd0, rgb_in[7:0]}   * brightness_eff;
    wire [7:0] bright_r = mul_r[16:8];
    wire [7:0] bright_g = mul_g[16:8];
    wire [7:0] bright_b = mul_b[16:8];

    // ---- 对比度 + 饱和截断（教程 3.2.2 参考答案） ----
    wire signed [8:0]  ctr_r = $signed({1'b0, bright_r}) - 9'sd128;
    wire signed [8:0]  ctr_g = $signed({1'b0, bright_g}) - 9'sd128;
    wire signed [8:0]  ctr_b = $signed({1'b0, bright_b}) - 9'sd128;

    wire signed [16:0] sc_r = (ctr_r * $signed({1'b0, contrast})) >>> 7;
    wire signed [16:0] sc_g = (ctr_g * $signed({1'b0, contrast})) >>> 7;
    wire signed [16:0] sc_b = (ctr_b * $signed({1'b0, contrast})) >>> 7;

    wire signed [9:0] sum_r = sc_r + 10'sd128;
    wire signed [9:0] sum_g = sc_g + 10'sd128;
    wire signed [9:0] sum_b = sc_b + 10'sd128;

    wire [7:0] final_r = (sum_r < 10'sd0)   ? 8'd0   :
                         (sum_r > 10'sd255) ? 8'd255 : sum_r[7:0];
    wire [7:0] final_g = (sum_g < 10'sd0)   ? 8'd0   :
                         (sum_g > 10'sd255) ? 8'd255 : sum_g[7:0];
    wire [7:0] final_b = (sum_b < 10'sd0)   ? 8'd0   :
                         (sum_b > 10'sd255) ? 8'd255 : sum_b[7:0];

    // 打一拍输出（流水线寄存器），DE 跟着打拍
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_de  <= 1'b0;
            rgb_out <= 24'h000000;
        end else begin
            out_de  <= in_de;
            rgb_out <= {final_r, final_g, final_b};
        end
    end
endmodule

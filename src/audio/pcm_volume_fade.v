`timescale 1ns/1ps

// 对 WAV PCM 施加用户音量与转场淡入淡出增益。
// 乘法结果先按 1/255 缩放，再按 1/255 缩放，最终回到 16bit。
module pcm_volume_fade (
    input  wire               sample_valid,
    input  wire               sample_ready,
    input  wire signed [15:0] sample_left,
    input  wire signed [15:0] sample_right,
    input  wire [7:0]         volume,
    input  wire [7:0]         fade_gain,
    output wire               out_valid,
    output wire               out_ready,
    output wire signed [15:0] out_left,
    output wire signed [15:0] out_right
);
    wire signed [31:0] left_ext  = {{16{sample_left[15]}},  sample_left};
    wire signed [31:0] right_ext = {{16{sample_right[15]}}, sample_right};
    // Keep the full unsigned 8x8 gain product; no intermediate rounding.
    wire [15:0] gain_product = {8'd0, volume} * {8'd0, fade_gain};
    wire signed [31:0] gain_ext = {16'd0, gain_product};

    // 显式使用32位有符号中间结果；16bit满幅样本乘200乘255仍在
    // signed 32bit范围内，不会发生中间表达式位宽截断。
    wire signed [31:0] left_full  = left_ext  * gain_ext;
    wire signed [31:0] right_full = right_ext * gain_ext;

    wire signed [15:0] left_scaled =
        (left_full > 32'sd2147418112) ? 16'sh7fff :
        left_full[31:16];
    wire signed [15:0] right_scaled =
        (right_full > 32'sd2147418112) ? 16'sh7fff :
        right_full[31:16];

    assign out_valid = sample_valid;
    assign out_ready = sample_ready;
    assign out_left  = left_scaled;
    assign out_right = right_scaled;
endmodule

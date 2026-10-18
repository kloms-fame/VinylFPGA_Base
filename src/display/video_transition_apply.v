`timescale 1ns/1ps

// Pixel-domain application of the tenth-lecture transition controller.
// Manual switches use alpha fading; automatic slideshow switches use a
// left-to-right wipe reveal. Because the frame reader has a single read port,
// the wipe reveals the newly displayed frame from black on the left side.
module video_transition_apply #(
    parameter integer WIPE_STEP = 40
) (
    input  wire [23:0] rgb_in,
    input  wire [7:0]  alpha,
    input  wire [7:0]  brightness,
    input  wire        preserve_media,
    input  wire        wipe_active,
    input  wire        wipe_reverse, // 1 reveals right -> left, 0 left -> right
    input  wire [4:0]  wipe_ramp,
    input  wire [9:0]  pixel_x,
    output wire [23:0] rgb_out
);
    // 第十四讲教程 2.1：完赛工程把亮度折进转场系数，只增加一次 8x8
    // 乘法。brightness=255 时 effective_alpha 与输入 alpha 完全相同，
    // 因而默认参数下的既有淡入淡出/擦除行为逐位不变。
    wire [8:0]  brightness_eff = {1'b0, brightness} + 9'd1;
    // PLAY uses an atomic cover/MV handoff. Browse fade/wipe may continue its
    // bank-commit handshake, but must not introduce a black flash in PLAY.
    wire [7:0] visible_alpha = preserve_media ? 8'd255 : alpha;
    wire [16:0] alpha_mul      = {8'd0, visible_alpha} * brightness_eff;
    wire [7:0]  effective_alpha = alpha_mul[16:8];

    // /256 is used instead of /255; alpha=255 is 0.4% short of full scale and
    // is visually indistinguishable, while avoiding a wide divider.
    // Explicitly extend each 8-bit channel before the multiply. In Verilog
    // the result width of "8-bit * 8-bit" is only 8 bits, so writing the
    // expression without zero-extension would truncate values above 255 and
    // darken the image even when alpha is full-scale.
    wire [15:0] red_mul   = {8'd0, rgb_in[23:16]} * effective_alpha;
    wire [15:0] green_mul = {8'd0, rgb_in[15:8]}  * effective_alpha;
    wire [15:0] blue_mul  = {8'd0, rgb_in[7:0]}   * effective_alpha;
    wire [23:0] scaled_rgb = {
        red_mul[15:8],
        green_mul[15:8],
        blue_mul[15:8]
    };

    wire [10:0] wipe_boundary = wipe_ramp * WIPE_STEP;
    wire [9:0] wipe_x = wipe_reverse ? (10'd639 - pixel_x) : pixel_x;
    wire        show_new      = (wipe_x < wipe_boundary);

    // 擦除模式也需要应用亮度；brightness=255 时保持原教程/第十讲的
    // “新画面原样、旧区域黑场”行为不变。
    wire [23:0] wipe_rgb = (brightness == 8'd255) ? rgb_in : scaled_rgb;

    assign rgb_out = (wipe_active && !preserve_media)
                   ? (show_new ? wipe_rgb : 24'd0) : scaled_rgb;
endmodule

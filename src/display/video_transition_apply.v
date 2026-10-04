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
    input  wire        wipe_active,
    input  wire [4:0]  wipe_ramp,
    input  wire [9:0]  pixel_x,
    output wire [23:0] rgb_out
);
    // /256 is used instead of /255; alpha=255 is 0.4% short of full scale and
    // is visually indistinguishable, while avoiding a wide divider.
    // Explicitly extend each 8-bit channel before the multiply. In Verilog
    // the result width of "8-bit * 8-bit" is only 8 bits, so writing the
    // expression without zero-extension would truncate values above 255 and
    // darken the image even when alpha is full-scale.
    wire [15:0] red_mul   = {8'd0, rgb_in[23:16]} * alpha;
    wire [15:0] green_mul = {8'd0, rgb_in[15:8]}  * alpha;
    wire [15:0] blue_mul  = {8'd0, rgb_in[7:0]}   * alpha;
    wire [23:0] faded_rgb = {
        red_mul[15:8],
        green_mul[15:8],
        blue_mul[15:8]
    };

    wire [10:0] wipe_boundary = wipe_ramp * WIPE_STEP;
    wire        show_new      = (pixel_x < wipe_boundary);

    assign rgb_out = wipe_active ? (show_new ? rgb_in : 24'd0) : faded_rgb;
endmodule

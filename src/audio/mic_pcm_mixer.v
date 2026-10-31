`timescale 1ns/1ps

// One-entry elastic mixer. All inputs and outputs are synchronous to clk.
// mic_sample is the most recently available 48 kHz-domain sample; it is
// captured only when the music-side transaction is accepted.
//
// Microphone gain law: mic_scaled = mic_sample * mic_gain / 32.
//   mic_gain_max 255 -> 7.97x   (about +18 dB digital gain)
//   mic_gain_max 128 -> 4.00x   (default: +24 dB versus the old 1/4 law)
// The coefficient ramps by MIC_GAIN_STEP every RAMP_INTERVAL accepted
// samples, so a 0.25 s style click-free fade needs no extra state.
// The microphone term is limited to 16 bits before it is summed with the
// music, so a very hot microphone cannot invert the music polarity.
module mic_pcm_mixer #(
    parameter integer RAMP_INTERVAL = 64,
    parameter integer MIC_GAIN_STEP = 8,
    parameter integer COUNT_BITS = (RAMP_INTERVAL < 2) ? 1 : $clog2(RAMP_INTERVAL)
) (
    input wire clk,
    input wire rst_n,
    input wire in_valid,
    output wire in_ready,
    input wire signed [15:0] in_left,
    input wire signed [15:0] in_right,
    input wire signed [15:0] mic_sample,
    input wire mic_valid,
    input wire mic_enable,
    input wire [7:0] mic_gain_max,
    input wire mute,
    output reg out_valid,
    input wire out_ready,
    output reg signed [15:0] out_left,
    output reg signed [15:0] out_right
);
    reg [7:0] mic_gain;
    reg [COUNT_BITS-1:0] ramp_count;
    wire accept = in_valid && in_ready;
    wire signed [23:0] mic_product = mic_sample * $signed({1'b0,mic_gain});
    wire signed [23:0] mic_scaled_raw = mic_valid ? (mic_product >>> 5) : 24'sd0;
    wire signed [15:0] mic_scaled = (mic_scaled_raw > 24'sd32767) ? 16'sh7fff :
                                    (mic_scaled_raw < -24'sd32768) ? 16'sh8000 :
                                    mic_scaled_raw[15:0];
    wire signed [17:0] left_sum = $signed({{2{in_left[15]}},in_left}) +
                                  $signed({{2{mic_scaled[15]}},mic_scaled});
    wire signed [17:0] right_sum = $signed({{2{in_right[15]}},in_right}) +
                                   $signed({{2{mic_scaled[15]}},mic_scaled});
    wire signed [15:0] left_sat = (left_sum > 18'sd32767) ? 16'sh7fff :
                                  (left_sum < -18'sd32768) ? 16'sh8000 : left_sum[15:0];
    wire signed [15:0] right_sat = (right_sum > 18'sd32767) ? 16'sh7fff :
                                   (right_sum < -18'sd32768) ? 16'sh8000 : right_sum[15:0];
    localparam [8:0] GAIN_STEP_W = MIC_GAIN_STEP;
    wire [8:0] gain_rise = {1'b0,mic_gain} + GAIN_STEP_W;
    wire [8:0] gain_fall = {1'b0,mic_gain} - GAIN_STEP_W;
    wire [8:0] gain_target = {1'b0,mic_gain_max};

    assign in_ready = !out_valid || out_ready;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) out_valid <= 1'b0;
        else if (in_ready) out_valid <= in_valid;
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) out_left <= 16'sd0;
        else if (accept) out_left <= mute ? 16'sd0 : left_sat;
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) out_right <= 16'sd0;
        else if (accept) out_right <= mute ? 16'sd0 : right_sat;
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) ramp_count <= {COUNT_BITS{1'b0}};
        else if (accept) begin
            if (ramp_count == RAMP_INTERVAL - 1) ramp_count <= {COUNT_BITS{1'b0}};
            else ramp_count <= ramp_count + 1'b1;
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) mic_gain <= 8'd0;
        else if (accept && ramp_count == RAMP_INTERVAL - 1) begin
            if (mic_enable) begin
                if (gain_rise >= gain_target) mic_gain <= mic_gain_max;
                else mic_gain <= gain_rise[7:0];
            end else if (!gain_fall[8]) begin
                mic_gain <= gain_fall[7:0];
            end else begin
                mic_gain <= 8'd0;
            end
        end
    end
endmodule

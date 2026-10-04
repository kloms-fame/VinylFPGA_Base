`timescale 1ns/1ps

// 第3课音频源到安路 HDMI 1.4b 加密核的适配层。
//
// 完赛工程原本使用：
//   pcm_media_tone -> m06_pcm_contract_adapter -> hdmi_audio_symbol_core
// 其中 hdmi_audio_symbol_core 负责自行封装 HDMI 音频包并输出 TMDS 符号。
//
// 本工程使用官方加密 HDMI 1.4b 发射核，音频采样包、InfoFrame 和 ACR 已在
// 核内部完成。该核只接收 48kHz 的 24bit 并行 PCM：
//   I_audio_valid / I_audio_left_data / I_audio_right_data
// 因此这里保留教程的 PCM 音源和契约适配，只把 16bit PCM 左移 8bit 后送入
// 加密核，避免重复实现 HDMI 音频包封装。
module hdmi_pcm_audio_bridge #(
    parameter integer CLOCK_HZ  = 25000000,
    parameter integer SAMPLE_HZ = 48000
) (
    input  wire               clk,
    input  wire               rst_n,
    input  wire [1:0]         media_id,
    input  wire [7:0]         volume,
    output wire               audio_valid,
    output wire signed [23:0] audio_left,
    output wire signed [23:0] audio_right,
    output wire               sample_overflow,
    output wire               contract_error,
    output wire               blip_active
);
    wire               source_valid;
    wire               source_ready;
    wire signed [15:0] source_left;
    wire signed [15:0] source_right;
    wire               pcm_valid;
    wire signed [15:0] pcm_left;
    wire signed [15:0] pcm_right;

    pcm_media_tone #(
        .CLOCK_HZ  (CLOCK_HZ),
        .SAMPLE_HZ (SAMPLE_HZ)
    ) u_pcm_media_tone (
        .clk          (clk),
        .rst_n        (rst_n),
        .media_id     (media_id),
        .volume       (volume),
        .sample_valid (source_valid),
        .sample_ready (source_ready),
        .sample_left  (source_left),
        .sample_right (source_right),
        .overflow     (sample_overflow),
        .blip_active  (blip_active)
    );

    m06_pcm_contract_adapter u_m06_pcm_contract_adapter (
        .clk            (clk),
        .rst_n          (rst_n),
        .source_valid   (source_valid),
        .source_ready   (source_ready),
        .source_left    (source_left),
        .source_right   (source_right),
        .pcm_valid      (pcm_valid),
        .pcm_ready      (1'b1),
        .pcm_left       (pcm_left),
        .pcm_right      (pcm_right),
        .contract_error (contract_error)
    );

    // 16bit PCM 在 HDMI/IEC 60958 的 24bit sample word 中左对齐。
    assign audio_valid = pcm_valid;
    assign audio_left  = {pcm_left,  8'b0};
    assign audio_right = {pcm_right, 8'b0};
endmodule

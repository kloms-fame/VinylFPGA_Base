`timescale 1ns/1ps

// 通用 16bit PCM 源 -> M06 契约 -> 安路 HDMI 1.4b 加密核 24bit 接口。
// 第十一讲顶层把 WAV/琶音选择结果接到本模块。
module hdmi_pcm_source_bridge (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               source_valid,
    output wire               source_ready,
    input  wire signed [15:0] source_left,
    input  wire signed [15:0] source_right,
    output wire               audio_valid,
    output wire signed [23:0] audio_left,
    output wire signed [23:0] audio_right,
    output wire               contract_error
);
    wire               pcm_valid;
    wire signed [15:0] pcm_left;
    wire signed [15:0] pcm_right;

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

    assign audio_valid = pcm_valid;
    assign audio_left  = {pcm_left,  8'b0};
    assign audio_right = {pcm_right, 8'b0};
endmodule

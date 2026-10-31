`ifndef VINYL_MIC_SIGNAL_CONDITION_V
`define VINYL_MIC_SIGNAL_CONDITION_V
`timescale 1ns/1ps

// 麦克风数字调理链（视频/音频域，25 MHz，无跨时钟）：
//   ADC 偏置码 -> 补码 -> 一阶 DC 跟踪高通（约 120 Hz 拐点）
//   -> 两级一阶低通（alpha = 1/4，级联 12 dB/oct：单级 -3 dB 约 8.8 kHz，双级约 5.7 kHz）
//   -> 4:1 抽取到 48 kHz（与音乐同节拍）
//   -> Q8 增益（0X/4X/5X/6X/7X，斜坡去拉链）
//   -> 软噪声门（包络为增益前幅度，门限约 1.2%/3.5% ADC 满量程）
// 输出 mic_sample 已完成增益与门控，可直接与音乐 PCM 饱和相加。
module mic_signal_condition #(
    parameter [11:0]  GATE_SHUT_ENV   = 12'd24, // 约 1.2% FS，以下完全关闭
    parameter [11:0]  GATE_OPEN_ENV   = 12'd72, // 约 3.5% FS，以上完全打开
    parameter [3:0]   GATE_REL_SHIFT  = 4'd10,  // 释放时间常数 2^10 个 48 kHz 样本
    parameter integer GAIN_RAMP_STEP  = 8       // Q8 增益每 48 kHz 样本最大变化
)(
    input  wire               clk,
    input  wire               rst_n,
    input  wire [11:0]        sample_code,
    input  wire               sample_valid,
    input  wire [2:0]         mic_level,
    output reg  signed [15:0] mic_sample,
    output reg                mic_valid
);
    // ----------------------------------------------------------------
    // 1. 偏置二进制转补码，补 4 bit 小数位参与滤波
    // ----------------------------------------------------------------
    wire signed [11:0] centered      = {sample_code[11] ^ 1'b1, sample_code[10:0]};
    wire signed [16:0] centered_frac = {centered[11], centered, 4'b0000};

    // ----------------------------------------------------------------
    // 2. 一阶 DC 跟踪高通：2^8 个 192 kHz 样本的时间常数
    // ----------------------------------------------------------------
    reg  signed [20:0] dc_estimate;
    wire signed [20:0] dc_target = {centered[11], centered, 8'b0000_0000};
    wire signed [21:0] dc_delta  = dc_target - dc_estimate;
    wire signed [21:0] dc_step   = dc_delta >>> 8;
    wire signed [20:0] dc_next   = dc_estimate + dc_step[20:0];
    wire signed [21:0] dc_frac   = dc_estimate >>> 4;
    wire signed [21:0] hp_wide   = centered_frac - dc_frac;
    wire signed [18:0] hp        = hp_wide[18:0];

    // ----------------------------------------------------------------
    // 3. 两级一阶低通，alpha = 1/4
    // ----------------------------------------------------------------
    reg  signed [18:0] lpf1, lpf2;
    wire signed [18:0] lpf1_delta = hp - lpf1;
    wire signed [18:0] lpf1_next  = lpf1 + (lpf1_delta >>> 2);
    wire signed [18:0] lpf2_delta = lpf1_next - lpf2;
    wire signed [18:0] lpf2_next  = lpf2 + (lpf2_delta >>> 2);

    // ----------------------------------------------------------------
    // 4. 4:1 抽取到 48 kHz，Q4 即 16 bit PCM 满刻度
    // ----------------------------------------------------------------
    reg  [1:0]         dec_phase;
    reg  signed [20:0] dec_acc;
    wire signed [20:0] dec_sum = dec_acc + lpf2_next;
    wire signed [20:0] dec_avg = dec_sum >>> 2;
    wire signed [15:0] dec_sat = (dec_avg > 21'sd32767)  ? 16'sh7fff :
                                 (dec_avg < -21'sd32768) ? 16'sh8000 : dec_avg[15:0];

    // ----------------------------------------------------------------
    // 5. 软噪声门：包络 = 增益前的 ADC 码幅度（0..2048）
    //    瞬时起振 + 慢释放，避免正弦包络逐周期抖动
    // ----------------------------------------------------------------
    reg  signed [15:0] s16;
    reg                s16_valid;
    reg  [11:0]        gate_env;
    wire [15:0]        s16_mag  = s16[15] ? (~s16 + 16'd1) : s16;
    wire [11:0]        env_in   = s16_mag[15:4];
    // 释放：衰减量至少 1，避免 12 bit 包络在 gate_env < 2^GATE_REL_SHIFT 时衰减停滞
    wire [11:0]        env_leak      = (gate_env >> GATE_REL_SHIFT) + 12'd1;
    wire [11:0]        env_decay     = gate_env - env_leak;
    wire [11:0]        gate_env_next = (env_in >= gate_env) ? env_in : env_decay;
    wire [12:0]        gate_span     = {1'b0, gate_env} - {1'b0, GATE_SHUT_ENV};
    wire [12:0]        gate_mul      = (gate_span << 2) + gate_span;
    wire [7:0]         gate_factor   =
        (gate_env <= GATE_SHUT_ENV) ? 8'd0 :
        (gate_env >= GATE_OPEN_ENV) ? 8'd255 :
        (gate_mul > 13'd255)        ? 8'd255 : gate_mul[7:0];

    // ----------------------------------------------------------------
    // 6. Q8 增益斜坡 + 门控系数，最终 16x11 乘法
    // ----------------------------------------------------------------
    reg  [10:0]        gain_q8;
    wire [10:0]        gain_target   = {1'b0, mic_level, 8'b0000_0000};
    wire [10:0]        gain_ramp_max = GAIN_RAMP_STEP;
    wire [10:0]        gain_span     = (gain_target >= gain_q8) ? (gain_target - gain_q8)
                                                               : (gain_q8 - gain_target);
    wire [10:0]        gain_step     = (gain_span > gain_ramp_max) ? gain_ramp_max : gain_span;
    wire [10:0]        gain_next     = (gain_target >= gain_q8) ? (gain_q8 + gain_step)
                                                               : (gain_q8 - gain_step);
    wire [18:0]        gain_gated    = gain_q8 * gate_factor;
    wire [10:0]        gain_eff      = gain_gated[18:8];
    wire signed [26:0] mic_prod      = s16 * $signed({1'b0, gain_eff});
    wire signed [26:0] mic_scaled    = mic_prod >>> 8;
    wire signed [15:0] mic_out       = (mic_scaled > 27'sd32767)  ? 16'sh7fff :
                                       (mic_scaled < -27'sd32768) ? 16'sh8000 :
                                       mic_scaled[15:0];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dc_estimate <= 21'sd0;
            lpf1        <= 19'sd0;
            lpf2        <= 19'sd0;
            dec_phase   <= 2'd0;
            dec_acc     <= 21'sd0;
            s16         <= 16'sd0;
            s16_valid   <= 1'b0;
            gate_env    <= 12'd0;
            gain_q8     <= 11'd0;
            mic_sample  <= 16'sd0;
            mic_valid   <= 1'b0;
        end else begin
            s16_valid <= 1'b0;
            mic_valid <= 1'b0;
            if (sample_valid) begin
                dc_estimate <= dc_next;
                lpf1        <= lpf1_next;
                lpf2        <= lpf2_next;
                if (dec_phase == 2'd3) begin
                    dec_phase <= 2'd0;
                    dec_acc   <= 21'sd0;
                    s16       <= dec_sat;
                    s16_valid <= 1'b1;
                end else begin
                    dec_phase <= dec_phase + 2'd1;
                    dec_acc   <= dec_sum;
                end
            end
            if (s16_valid) begin
                gate_env   <= gate_env_next;
                gain_q8    <= gain_next;
                mic_sample <= mic_out;
                mic_valid  <= 1'b1;
            end
        end
    end
endmodule
`endif

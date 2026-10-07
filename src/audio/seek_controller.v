`timescale 1ns/1ps
`ifndef VINYL_SEEK_CONTROLLER_V
`define VINYL_SEEK_CONTROLLER_V
// =============================================================================
// seek_controller —— X2：最小的 Seek/重播目标计算器（sd_card_clk 域）
//
// 只做三件事，不复制任何播放状态机：
//   1) 把红外 F8/EA（±5 s）与 EC2 旋钮（±2 s）的步进做"扩位有符号加法"，
//      再钳位到 [0, total_samples-1]；
//   2) 事务忙窗口内把后续步进继续累加到**最新目标**；
//   3) 每接受一次 Seek/重播就请求一次 restart（真正的停发/等在途/预缓冲
//      由既有 stream_session 完成）。
//
// 重播（F6）等价于 target=0 的定位。切曲/重播请求由 play_ctrl 通过
// clear_pulse 把目标归零，因此"新曲从 0 开始"不需要额外状态。
// =============================================================================
module seek_controller #(
    parameter [31:0] STEP_IR  = 32'd240000,   // ±5 s @48 kHz
    parameter [31:0] STEP_ENC = 32'd96000,    // ±2 s @48 kHz
    parameter [19:0] BUSY_HOLD= 20'hFFFFF     // ~10.5 ms @100 MHz
)(
    input  wire        clk,
    input  wire        rst_n,

    input  wire        play_active,      // 播放态才允许 Seek
    input  wire [31:0] cur_sample,       // 当前读侧样本位置（格雷同步后）
    input  wire [31:0] total_samples,    // 本曲样本总数，0=空音频
    input  wire        clear_pulse,      // 切曲/重播：目标归零

    // 事件（clk 域翻转电平，本模块内部 3FF + 边沿还原）
    input  wire        seek_fwd5_tgl,    // 红外 F8
    input  wire        seek_bwd5_tgl,    // 红外 EA
    input  wire        seek_fwd2_tgl,    // EC2 顺时针
    input  wire        seek_bwd2_tgl,    // EC2 逆时针
    input  wire        replay_tgl,       // 红外 F6

    output reg  [31:0] target_sample,
    output reg         restart_req       // 1 拍：请求 stream_session 重启
);
    reg [2:0] s5f, s5b, s2f, s2b, srp;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s5f <= 3'd0; s5b <= 3'd0; s2f <= 3'd0; s2b <= 3'd0; srp <= 3'd0;
        end else begin
            s5f <= {s5f[1:0], seek_fwd5_tgl};
            s5b <= {s5b[1:0], seek_bwd5_tgl};
            s2f <= {s2f[1:0], seek_fwd2_tgl};
            s2b <= {s2b[1:0], seek_bwd2_tgl};
            srp <= {srp[1:0], replay_tgl};
        end
    end

    wire p5f = s5f[2] ^ s5f[1];
    wire p5b = s5b[2] ^ s5b[1];
    wire p2f = s2f[2] ^ s2f[1];
    wire p2b = s2b[2] ^ s2b[1];
    wire prp = srp[2] ^ srp[1];

    reg        busy;
    reg [19:0] hold;
    reg [31:0] lim_reg;

    wire        seek_ev  = p5f | p5b | p2f | p2b;
    wire        any_ev   = seek_ev | prp;
    wire [31:0] mag      = (p5f | p5b) ? STEP_IR : STEP_ENC;
    wire        dir_up   = p5f | p2f;      // 1 = 向曲尾

    // 扩位有符号加法：base(33bit 正) + delta(33bit 有符号)
    wire signed [32:0] delta_ext = dir_up ? $signed({1'b0, mag})
                                          : -$signed({1'b0, mag});
    wire signed [32:0] base_ext  = busy ? $signed({1'b0, target_sample})
                                        : $signed({1'b0, cur_sample});
    wire signed [32:0] cand      = base_ext + delta_ext;

    wire [31:0] clamped = cand[32]                       ? 32'd0 :
                          (cand > $signed({1'b0, lim_reg})) ? lim_reg : cand[31:0];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            target_sample <= 32'd0;
            restart_req   <= 1'b0;
            busy          <= 1'b0;
            hold          <= 20'd0;
            lim_reg       <= 32'd0;
        end else begin
            restart_req <= 1'b0;
            // 总数在整曲生命周期内稳定；预先寄存 total-1，避免它进入
            // 事件当拍的 33 位加法/钳位路径（100 MHz SD 域关键路径）。
            lim_reg <= (total_samples == 32'd0) ? 32'd0 : (total_samples - 32'd1);
            if (clear_pulse) begin
                target_sample <= 32'd0;
                busy          <= 1'b0;
                hold          <= 20'd0;
            end else if (any_ev) begin
                // 空音频或非播放态一律不响应（方案：空音频禁止 Seek）
                if (play_active && (total_samples != 32'd0)) begin
                    target_sample <= prp ? 32'd0 : clamped;
                    restart_req   <= 1'b1;
                    busy          <= 1'b1;
                    hold          <= BUSY_HOLD;
                end
            end else if (busy) begin
                if (hold == 20'd0) busy <= 1'b0;
                else               hold <= hold - 1'b1;
            end
        end
    end
endmodule
`endif

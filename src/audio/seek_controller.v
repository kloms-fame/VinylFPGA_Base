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
    wire        accept   = any_ev && play_active && (total_samples != 32'd0);

    wire signed [35:0] new_delta = dir_up ? $signed({4'b0, mag})
                                          : -$signed({4'b0, mag});

    // 三级显式流水：
    //   IDLE  : 装载基址与增量，忙时新事件进入 pending。
    //   ADD   : 只寄存 base+delta，不接钳位比较。
    //   CLAMP : 只比较/选择并提交 target，不和加法叠在同一拍。
    // 这样切断了原本 lim_ext -> clamp -> pending_target -> new_base -> acc_base
    // 的回灌组合链；连续事件仍按增量合并后在忙窗口内依次提交。
    localparam [1:0] S_IDLE  = 2'd0;
    localparam [1:0] S_ADD   = 2'd1;
    localparam [1:0] S_CLAMP = 2'd2;

    reg [1:0]       state;
    reg [32:0]      work_base;
    reg signed [35:0] work_delta;
    reg             work_replay;
    reg             pend_v;
    reg signed [35:0] pend_delta;
    reg             pend_replay;
    reg signed [36:0] sum_reg;

    wire signed [36:0] sum_next = $signed({1'b0, work_base}) + work_delta;
    wire signed [36:0] lim_ext  = $signed({5'b0, lim_reg});
    wire signed [36:0] clamped  = (sum_reg < 0)       ? 37'sd0 :
                                  (sum_reg > lim_ext) ? lim_ext : sum_reg;

    wire start_pending = (state == S_IDLE) && pend_v;
    wire start_event   = (state == S_IDLE) && !pend_v && accept;
    wire queue_event   = accept && !start_event;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            target_sample <= 32'd0;
            restart_req   <= 1'b0;
            busy          <= 1'b0;
            hold          <= 20'd0;
            lim_reg       <= 32'd0;
            state         <= S_IDLE;
            work_base     <= 33'd0;
            work_delta    <= 36'sd0;
            work_replay   <= 1'b0;
            pend_v        <= 1'b0;
            pend_delta    <= 36'sd0;
            pend_replay   <= 1'b0;
            sum_reg       <= 37'sd0;
        end else begin
            restart_req <= 1'b0;
            // 总数在整曲生命周期内稳定；预先寄存 total-1，避免它进入
            // 事件当拍的 33 位加法/钳位路径（100 MHz SD 域关键路径）。
            lim_reg <= (total_samples == 32'd0) ? 32'd0 : (total_samples - 32'd1);
            if (clear_pulse) begin
                target_sample <= 32'd0;
                busy          <= 1'b0;
                hold          <= 20'd0;
                state         <= S_IDLE;
                pend_v        <= 1'b0;
                work_replay   <= 1'b0;
                pend_replay   <= 1'b0;
            end else begin
                case (state)
                S_IDLE: begin
                    if (start_pending) begin
                        work_base   <= busy ? {1'b0, target_sample} : {1'b0, cur_sample};
                        work_delta  <= pend_delta;
                        work_replay <= pend_replay;
                        pend_v      <= 1'b0;
                        pend_replay <= 1'b0;
                        state       <= S_ADD;
                    end else if (start_event) begin
                        work_base   <= busy ? {1'b0, target_sample} : {1'b0, cur_sample};
                        work_delta  <= new_delta;
                        work_replay <= prp;
                        state       <= S_ADD;
                    end else if (busy) begin
                        if (hold == 20'd0) busy <= 1'b0;
                        else               hold <= hold - 1'b1;
                    end
                end

                S_ADD: begin
                    sum_reg <= sum_next;
                    state   <= S_CLAMP;
                end

                default: begin // S_CLAMP
                    target_sample <= work_replay ? 32'd0 : clamped[31:0];
                    restart_req   <= 1'b1;
                    busy          <= 1'b1;
                    hold          <= BUSY_HOLD;
                    if (pend_v) begin
                        work_base   <= clamped[32:0];
                        work_delta  <= pend_delta;
                        work_replay <= pend_replay;
                        pend_v      <= 1'b0;
                        pend_replay <= 1'b0;
                        state       <= S_ADD;
                    end else begin
                        state <= S_IDLE;
                    end
                end
                endcase

                if (queue_event) begin
                    pend_delta  <= pend_v ? (pend_delta + new_delta) : new_delta;
                    pend_replay <= pend_replay | prp;
                    pend_v      <= 1'b1;
                end
            end
        end
    end
endmodule
`endif

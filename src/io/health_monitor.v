`ifndef EXP_HEALTH_MONITOR_V
`define EXP_HEALTH_MONITOR_V
// =============================================================================
// health_monitor —— S7-01B 资源/时序/诊断遥测汇聚（clk 域）
//
// 职责：把顶层已经同步到 clk 域的若干"慢变/单拍"可观测信号，汇聚成
//   - 饱和计数（到达 16'hFFFF 后停住，不归零）：音频欠载、播放中缓冲进入
//     低水位、MV 取帧失败、事件队列溢出；
//   - sticky 状态：最近一次非零错误码；
//   - 周期 STAT 请求脉冲（默认 2 秒）与错误变化 ERR 请求脉冲，交给
//     exp_echo_reporter 在串口上拼装上报。
//
// 设计边界（与《S7 优化迭代与功能拓展分阶段开发方案》S7-01B 一致）：
//   - 本模块是被动遥测旁路：只累加计数，不反压、不阻塞音频/视频主链路，
//     不改动任何既有状态机；
//   - 所有输入均已由顶层做跨域同步（单拍用 toggle 握手、电平用 2FF），
//     本模块不做任何二次跨域；
//   - "SD 超时/重试"与"最大等待"两项在本阶段不伪造：当前 SD 层没有显式
//     超时/重试寄存器，这两项留到 S7-02 的 media_supervisor 再补（见交付说明）。
// =============================================================================
module health_monitor #(
    parameter integer CLK_FREQ_HZ    = 50_000_000,
    parameter integer STAT_PERIOD_MS = 2000,
    parameter [31:0] FW_VERSION      = 32'h0701_0001  // 运行版本：大版本/子阶段/构建号
)(
    input  wire        clk,
    input  wire        rst_n,

    // ---- 已由顶层同步到本 clk 域的可观测输入 ----
    input  wire        underrun_pulse,   // 音频欠载单拍脉冲（video 域经 toggle 握手搬来）
    input  wire        buffer_low,       // WAV 缓冲低水位电平（2FF 同步）
    input  wire        stream_active,    // WAV 流式播放中电平（2FF 同步）
    input  wire        video_failed,     // MV 取帧失败电平（2FF 同步）
    input  wire        osd_err_valid,    // 错误码变化单拍脉冲（toggle 边沿还原）
    input  wire [7:0]  osd_err_code,     // 已同步错误码
    input  wire        ev_overflow,      // 事件队列溢出单拍脉冲

    // ---- 输出给 exp_echo_reporter ----
    output reg         stat_req,         // 周期 STAT 请求脉冲
    output reg         err_req,          // 错误变化 ERR 请求脉冲
    output reg  [7:0]  err_code,         // current error; explicit zero reports recovery
    output reg  [15:0] cnt_underrun,     // 饱和：音频欠载次数
    output reg  [15:0] cnt_buffer_low,   // 饱和：播放中缓冲进入低水位次数
    output reg  [15:0] cnt_video_fail,   // 饱和：MV 取帧失败次数
    output reg  [15:0] cnt_ev_overflow,  // 饱和：事件队列溢出次数
    output wire [31:0] fw_version        // 运行版本（参数透出，单一事实来源）
);

    localparam integer STAT_CYCLES = (CLK_FREQ_HZ / 1000) * STAT_PERIOD_MS;
    localparam integer STAT_W      = $clog2(STAT_CYCLES + 1);

    assign fw_version = FW_VERSION;

    reg [STAT_W-1:0] stat_cnt;
    reg              buffer_low_q;      // 低水位电平上一拍，用于上升沿检测
    reg              video_failed_q;    // 失败电平上一拍，用于上升沿检测

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stat_cnt        <= {STAT_W{1'b0}};
            buffer_low_q    <= 1'b0;
            video_failed_q  <= 1'b0;
            stat_req        <= 1'b0;
            err_req         <= 1'b0;
            err_code        <= 8'd0;
            cnt_underrun    <= 16'd0;
            cnt_buffer_low  <= 16'd0;
            cnt_video_fail  <= 16'd0;
            cnt_ev_overflow <= 16'd0;
        end else begin
            // 单拍请求脉冲只在当拍有效，下一拍默认清掉
            stat_req <= 1'b0;
            err_req  <= 1'b0;

            buffer_low_q   <= buffer_low;
            video_failed_q <= video_failed;

            // ---- 周期 STAT：每 STAT_PERIOD_MS 触发一次 ----
            if (stat_cnt >= (STAT_CYCLES - 1)) begin
                stat_cnt <= {STAT_W{1'b0}};
                stat_req <= 1'b1;
            end else begin
                stat_cnt <= stat_cnt + 1'b1;
            end

            // ---- 饱和自增（到达上限后不再变化） ----
            if (underrun_pulse && cnt_underrun != 16'hFFFF)
                cnt_underrun <= cnt_underrun + 16'd1;

            // 缓冲进入低水位：仅在流式播放中且低水位电平出现上升沿时计数，
            // 避免上电空缓冲与播放结束排空阶段被误判为"欠载事件"。
            if (buffer_low && !buffer_low_q && stream_active &&
                cnt_buffer_low != 16'hFFFF)
                cnt_buffer_low <= cnt_buffer_low + 16'd1;

            if (video_failed && !video_failed_q && cnt_video_fail != 16'hFFFF)
                cnt_video_fail <= cnt_video_fail + 16'd1;

            if (ev_overflow && cnt_ev_overflow != 16'hFFFF)
                cnt_ev_overflow <= cnt_ev_overflow + 16'd1;

            // ---- Current fault: zero is an explicit recovery event; counters retain history. ----
            if (osd_err_valid &&
                (osd_err_code != err_code)) begin
                err_code <= osd_err_code;
                err_req  <= 1'b1;
            end
        end
    end

endmodule
`endif

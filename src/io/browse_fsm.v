`ifndef EXP_BROWSE_FSM_V
`define EXP_BROWSE_FSM_V
// =============================================================================
// browse_fsm —— S3：中央大图选曲与播放返回事件适配层
//
// 运行在 sd_card_clk(100 MHz) 域，将 ui_event_bridge 的 toggle 事件还原为单拍。
// 唯一选曲视图是中央大图：方向事件直接切换封面，确认事件开始播放当前封面。
// KEY7 在播放态停止播放并返回中央大图选曲页。
// 顶层将遗留 home 事件绑 0；KEY11 已独立路由到播放背景控制。
//
// CDC：四路 toggle 为目标域电平，先 3 级 FF（2 级同步 + 1 级延迟）再异或
// 取边沿，事件间隔远大于同步延迟，不会丢步；一次边沿只产出一拍。
// =============================================================================
module browse_fsm #(
    parameter         J2_BROWSE_ENABLE = 1'b1
)(
    input  wire        clk,            // sd_card_clk（100 MHz）
    input  wire        rst_n,          // sdcard_rst_n（低有效）

    input  wire        ev_prev_tgl,    // clk 域电平（ui_event_bridge）
    input  wire        ev_next_tgl,
    input  wire        ev_confirm_tgl,
    input  wire        ev_mode_tgl,
    input  wire        ev_home_tgl,

    input  wire        mode_play,      // 1=播放态：KEY7 返回中央大图选曲页

    output reg         fs_next,        // 全屏：下一张
    output reg         fs_prev,        // 全屏：上一张
    output reg         play_start,
    output reg         play_stop
);
    // ---- CDC：目标域同步 + 边沿检测（单拍）----
    reg prev_s1,    prev_s2,    prev_s3;
    reg next_s1,    next_s2,    next_s3;
    reg confirm_s1, confirm_s2, confirm_s3;
    reg mode_s1,    mode_s2,    mode_s3;
    reg [2:0] home_sync;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) home_sync <= 3'b000;
        else home_sync <= {home_sync[1:0], ev_home_tgl};
    end
    wire home_event = home_sync[2] ^ home_sync[1];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prev_s1 <= 1'b0; prev_s2 <= 1'b0; prev_s3 <= 1'b0;
            next_s1 <= 1'b0; next_s2 <= 1'b0; next_s3 <= 1'b0;
            confirm_s1 <= 1'b0; confirm_s2 <= 1'b0; confirm_s3 <= 1'b0;
            mode_s1 <= 1'b0; mode_s2 <= 1'b0; mode_s3 <= 1'b0;
        end else begin
            prev_s1    <= ev_prev_tgl;
            prev_s2    <= prev_s1;
            prev_s3    <= prev_s2;
            next_s1    <= ev_next_tgl;
            next_s2    <= next_s1;
            next_s3    <= next_s2;
            confirm_s1 <= ev_confirm_tgl;
            confirm_s2 <= confirm_s1;
            confirm_s3 <= confirm_s2;
            mode_s1    <= ev_mode_tgl;
            mode_s2    <= mode_s1;
            mode_s3    <= mode_s2;
        end
    end

    wire j2_prev    = J2_BROWSE_ENABLE ? (prev_s2    ^ prev_s3)    : 1'b0;
    wire j2_next    = J2_BROWSE_ENABLE ? (next_s2    ^ next_s3)    : 1'b0;
    wire j2_confirm = J2_BROWSE_ENABLE ? (confirm_s2 ^ confirm_s3) : 1'b0;
    wire j2_mode    = J2_BROWSE_ENABLE ? (mode_s2    ^ mode_s3)    : 1'b0;

    wire mode_any = j2_mode;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fs_next    <= 1'b0;
            fs_prev    <= 1'b0;
            play_start <= 1'b0;
            play_stop  <= 1'b0;
        end else begin
            fs_next    <= j2_next && !mode_play;
            fs_prev    <= j2_prev && !mode_play;
            play_start <= j2_confirm && !mode_play && !home_event && !mode_any;
            play_stop  <= home_event || (mode_any && mode_play);
        end
    end
endmodule
`endif

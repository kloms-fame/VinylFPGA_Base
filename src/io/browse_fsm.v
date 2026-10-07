`ifndef EXP_BROWSE_FSM_V
`define EXP_BROWSE_FSM_V
// =============================================================================
// browse_fsm —— S3：主界面选歌的"事件 -> 控制"适配层
//
// 运行在 sd_card_clk(100 MHz) 域，位于 ui_event_bridge(clk 域) 与既有
// thumbnail_controller/sd_card_bmp 之间。职责只有一件：把 J2 选曲事件
// （经独立 toggle 跨域），按当前视图路由成既有主链路
// 已经能消费的控制脉冲。**不重写**缩略图布局、bank 预加载或取数握手。
//
// 路由规则（S3 冻结约定，S7-03b 更新 KEY07/KEY11 归属）：
//   全屏态 view_mode=0：
//     next   -> fs_next   （既有"下一张"路径，经转场在整帧边界切换）
//     prev   -> fs_prev   （新增 prev_event，复用 sd_card_bmp 既有"上一张"分支）
//     confirm-> play_start（EC1 按压 / KEY02 直接播放当前封面）
//  缩略图态 view_mode=1：
//     next   -> thumb_right（焦点 +1）
//     prev   -> thumb_left （焦点 -1）
//     confirm-> thumb_confirm（确认焦点并返回全屏）
//     mode   -> thumb_mode （进入/退出缩略图）
//  播放态 mode_play=1：
//     KEY07(切歌模式) -> play_stop + thumb_mode：直接退出播放并落到 2x2 缩略图选曲
//     KEY11(拓展1=返回主界面) -> play_stop + go_home：退出播放并回全屏主界面
//   说明：旧版 KEY07 在播放态先回主界面、再按一次才进缩略图；S7-03b 起 KEY07
//         在主界面与播放界面都可直接进入缩略图选曲，KEY11 专责返回主界面。
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

    input  wire        view_mode,      // 1=2x2 缩略图选曲视图
    input  wire        mode_play,      // 1=播放态：导航交给 play_ctrl，KEY7 只生成 stop/home

    output reg         fs_next,        // 全屏：下一张
    output reg         fs_prev,        // 全屏：上一张
    output reg         thumb_right,    // 缩略图：焦点 +1
    output reg         thumb_left,     // 缩略图：焦点 -1
    output reg         thumb_confirm,  // 缩略图：确认焦点
    output reg         thumb_mode,
    output reg         play_start,
    output reg         play_stop,
    output reg         go_home
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

    wire next_any    = j2_next;
    wire prev_any    = j2_prev;
    wire confirm_any = j2_confirm;
    wire mode_any    = j2_mode;
    wire left_any    = j2_prev;

    // S7-03b：切歌模式(mode)两种来源分流。
    //   j2_grid      = J2 KEY07 切歌模式：任意态(全屏/缩略图/播放)进入或退出缩略图。
    wire j2_grid      = j2_mode & ~home_event;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fs_next       <= 1'b0;
            fs_prev       <= 1'b0;
            thumb_right   <= 1'b0;
            thumb_left    <= 1'b0;
            thumb_confirm <= 1'b0;
            thumb_mode    <= 1'b0;
            play_start <= 1'b0;
            play_stop <= 1'b0;
            go_home <= 1'b0;
        end else begin
            fs_next       <= next_any & ~view_mode & ~mode_play;
            fs_prev       <= prev_any & ~view_mode & ~mode_play;
            thumb_right   <= next_any &  view_mode & ~mode_play;
            thumb_left    <= left_any &  view_mode & ~mode_play;
            thumb_confirm <= confirm_any & view_mode & ~mode_play;
            // S7-03b：KEY07 在浏览与播放两态都可直接进入/退出 2x2 缩略图；
            //   播放态同拍产生 play_stop 退出播放（落点即缩略图视图）。
            //   KEY11(home_event) 停止播放并强制 go_home 回主界面全屏。
            //   thumb_mode / play_stop / go_home 同在 sd_card_clk 单域同拍生成，
            //   旧版"退出播放"与"翻转视图"两条独立跨域路径的竞态不复存在。
            thumb_mode    <= j2_grid;
            play_start    <= confirm_any && !view_mode && !mode_play && !home_event && !mode_any;
            play_stop     <= home_event || (mode_any && mode_play);
            go_home       <= home_event;
        end
    end
endmodule
`endif

`ifndef EXP_UI_EVENT_BRIDGE_V
`define EXP_UI_EVENT_BRIDGE_V
// =============================================================================
// ui_event_bridge —— S3：把统一事件总线的"选曲业务"事件解码成电平翻转
//
// 运行在板级 clk(50 MHz) 域，紧接 expansion_integration 的 ui_event_* 输出。
// 只挑选"主界面选歌"需要的四类事件，各自翻一根电平（toggle），再由
// browse_fsm 在 sd_card_clk(100 MHz) 域做两级同步 + 边沿检测还原为单拍脉冲。
//
// 为什么用"每类事件一根独立 toggle"而不是整条总线跨域：
//   - 沿用 S2 已验证的 CDC 手法（单比特电平翻转 + 目标域 2FF/边沿检测），
//     不引入新的跨域模块，也不会因为事件密集而丢脉冲；
//   - 四类事件（prev/next/confirm/mode）互相独立，不会因同一拍仲裁互相覆盖。
//
// 事件来源（事件编码见 src/include/exp_event_defs.vh，标定语义见报告 2.3）：
//   prev   : EC1 逆时针（EV_ENC_STEP, enc=1, dir=1） 或 KEY01(左) 或 KEY04(上)
//   next   : EC1 顺时针（EV_ENC_STEP, enc=1, dir=0） 或 KEY03(右) 或 KEY05(下)
//   confirm: EC1 按压（EV_ENC_SW,  enc=1, DOWN）     或 KEY02(中)
//   mode   : KEY07(切歌模式) —— 播放态退出到中央大图选曲页
//
// 说明：KEY 事件用按下沿（EV_KEY_DOWN），避免按下/释放各触发一次。
//       EC1 为选曲主控；EC2 暂不参与选曲（预留给后续播放控制）。
// =============================================================================
module ui_event_bridge (
    input  wire        clk,            // 板级 clk（50 MHz）
    input  wire        rst_n,          // clk 域低有效复位

    input  wire        ev_valid,       // 统一事件总线单拍
    input  wire [3:0]  ev_code,
    input  wire [15:0] ev_arg,
    input  wire [15:0] ev_aux,

    output reg         prev_tgl,
    output reg         next_tgl,
    output reg         confirm_tgl,
    output reg         mode_tgl,
    output reg         home_tgl,       // Legacy port name: KEY11 background-cycle toggle
    output reg         effect_tgl,
    output reg         lyric_focus_tgl, // KEY6: five rows / current-row focus
    output reg         end_mode_tgl,
    // ---- S5：播放控制额外需要的"原始"事件（与上面 4 路并存）----
    // enc_cw/enc_ccw 只取 KEY01/03；EC1 同时产生浏览导航和 Seek，由各目标状态门控；
    // key_up/key_down 取 KEY04/KEY05（播放态 = 音量±，方向键上下）。
    output reg         enc_cw_tgl,
    output reg         enc_ccw_tgl,
    output reg         key_up_tgl,
    output reg         visual_tgl,
    output reg         key_down_tgl,
    // ---- X1B：KEY10 切换 WS2812 灯效（全灭 / VU）----
    output reg         ws_mode_tgl,
    // ---- X2：Seek / 重播（红外 F8/EA/F6 + EC1 旋钮 SEEK）----
    output reg         seek_fwd5_tgl,    // 红外 EA   +5 s
    output reg         seek_bwd5_tgl,    // 红外 F8   -5 s
    output reg         replay_tgl,       // 红外 F6   本曲重播
    output reg         seek_fwd2_tgl,    // EC1 顺    +2 s
    output reg         seek_bwd2_tgl     // EC1 逆    -2 s
);
    `include "exp_event_defs.vh"

    initial lyric_focus_tgl = 1'b0;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) lyric_focus_tgl <= 1'b0;
        else if (ev_valid && ev_code == EV_KEY_DOWN && ev_arg == 16'd5)
            lyric_focus_tgl <= ~lyric_focus_tgl;
    end

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) visual_tgl<=1'b0;
        else if(ev_valid && ev_code==EV_KEY_DOWN && ev_arg==16'd7) visual_tgl<=~visual_tgl;
    end
    wire is_enc1_step = (ev_code == EV_ENC_STEP) && (ev_aux[1] == 1'b0);
    wire is_enc2_step = (ev_code == EV_ENC_STEP) && (ev_aux[1] == 1'b1);
    wire is_enc1_baseline = (ev_code == EV_ENC_BASELINE) && !ev_aux[1];
    wire is_key_down  = (ev_code == EV_KEY_DOWN);

    // EV_ENC_SW: ev_aux[1]=enc_id，ev_arg[0]=0 表示按下（fall）/ 1 表示释放。
    wire is_enc1_down = (ev_code == EV_ENC_SW) && (ev_aux[1] == 1'b0) &&
                        (ev_arg[0] == 1'b0);

    // EC1 方向：direction=0 递增（顺时针/下一张）；direction=1 递减（逆时针/上一张）。
    wire enc1_dec = is_enc1_step && (ev_aux[0] == 1'b1);
    wire enc1_inc = is_enc1_step && (ev_aux[0] == 1'b0);

    // KEY 索引 = 端口数组位（KEYnn => idx nn-1）：
    //   0=KEY01左  1=KEY02中  2=KEY03右  3=KEY04上  4=KEY05下  6=KEY07切歌模式
    wire key_prev = is_key_down && ((ev_arg == 16'd0) || (ev_arg == 16'd3));
    wire key_next = is_key_down && ((ev_arg == 16'd2) || (ev_arg == 16'd4));
    wire key_ok   = is_key_down &&  (ev_arg == 16'd1);
    wire key_mode = is_key_down &&  (ev_arg == 16'd6);

    wire ev_prev    = key_prev;
    wire ev_next    = key_next;
    wire ev_confirm = is_enc1_down | key_ok;
    wire ev_mode    = key_mode;

    // S5：EC1 旋转与 KEY03/KEY01（S7-03 起 KEY01/03 在 PLAY 等价上一/下一曲，
    // 与 EC1 旋转同源进入 play_ctrl 的切曲路径；浏览态仍走 prev/next 不变）
    wire key01_prev = is_key_down && (ev_arg == 16'd0);  // KEY01 左 = 上一曲
    wire key03_next = is_key_down && (ev_arg == 16'd2);  // KEY03 右 = 下一曲
    wire ev_enc_cw  = key03_next;
    wire ev_enc_ccw = key01_prev;
    wire ev_key_up  = is_key_down && (ev_arg == 16'd3);   // KEY04 上
    wire ev_key_dn  = is_key_down && (ev_arg == 16'd4);   // KEY05 下

    // X2：红外 Seek/重播由 ui_command_router 翻译成 ev_arg=12/13/14 的"虚拟按键"；
    //     EC1 旋钮转一步 = ±2 s（方向沿用 enc 约定：0=递增/向曲尾）。
    wire ev_seek_fwd5 = is_key_down && (ev_arg == 16'd12);
    wire ev_seek_bwd5 = is_key_down && (ev_arg == 16'd13);
    wire ev_replay    = is_key_down && (ev_arg == 16'd14);

    // The event arbiter coalesces encoder pulses but carries the latest count.
    // Replay the modular delta, separated by eight source clocks for toggle CDC.
    reg [15:0] enc_target,enc_delivered;
    reg enc_seen;
    reg [2:0] enc_gap;
    wire [15:0] enc_delta=enc_target-enc_delivered;
    wire emit_encoder=(enc_gap==0) && enc_seen && (enc_delta!=0) && !ev_valid;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin enc_target<=0;enc_delivered<=0;enc_seen<=0;enc_gap<=0;end
        else begin
            if(enc_gap!=0) enc_gap<=enc_gap-1'b1;
            if(ev_valid && is_enc1_baseline) begin
                enc_target<=ev_arg;
                enc_delivered<=ev_arg;
                enc_seen<=1'b1;
                enc_gap<=0;
            end else if(ev_valid && is_enc1_step) begin
                enc_target<=ev_arg;
                if(!enc_seen) begin
                    enc_seen<=1;
                    enc_delivered<=enc1_dec ? ev_arg+16'd1 : ev_arg-16'd1;
                end
            end else if(emit_encoder) begin
                enc_delivered<=enc_delta[15] ? enc_delivered-16'd1 : enc_delivered+16'd1;
                enc_gap<=7;
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prev_tgl    <= 1'b0;
            next_tgl    <= 1'b0;
            confirm_tgl <= 1'b0;
            mode_tgl    <= 1'b0;
            home_tgl    <= 1'b0;
            effect_tgl  <= 1'b0;
            end_mode_tgl<= 1'b0;
            enc_cw_tgl  <= 1'b0;
            enc_ccw_tgl <= 1'b0;
            key_up_tgl  <= 1'b0;
            key_down_tgl<= 1'b0;
            ws_mode_tgl <= 1'b0;
            seek_fwd5_tgl<=1'b0;
            seek_bwd5_tgl<=1'b0;
            replay_tgl   <=1'b0;
            seek_fwd2_tgl<=1'b0;
            seek_bwd2_tgl<=1'b0;
        end else begin
            if (ev_valid && is_key_down && ev_arg == 16'd10) home_tgl <= ~home_tgl;
            if (ev_valid && is_key_down && ev_arg == 16'd8) effect_tgl <= ~effect_tgl;
            if (ev_valid && is_key_down && ev_arg == 16'd11) end_mode_tgl <= ~end_mode_tgl;
            // X1B：KEY10（端口 exp_key_n[9] -> 事件索引 9）切换 WS2812 全灭/VU
            if (ev_valid && is_key_down && ev_arg == 16'd9) ws_mode_tgl <= ~ws_mode_tgl;
            if (emit_encoder && enc_delta[15]) begin prev_tgl<=~prev_tgl;seek_bwd2_tgl<=~seek_bwd2_tgl;end
            if (emit_encoder && !enc_delta[15]) begin next_tgl<=~next_tgl;seek_fwd2_tgl<=~seek_fwd2_tgl;end
            if (ev_valid && ev_prev)    prev_tgl    <= ~prev_tgl;
            if (ev_valid && ev_next)    next_tgl    <= ~next_tgl;
            if (ev_valid && ev_confirm) confirm_tgl <= ~confirm_tgl;
            if (ev_valid && ev_mode)    mode_tgl    <= ~mode_tgl;
            if (ev_valid && ev_enc_cw)  enc_cw_tgl  <= ~enc_cw_tgl;
            if (ev_valid && ev_enc_ccw) enc_ccw_tgl <= ~enc_ccw_tgl;
            if (ev_valid && ev_key_up)  key_up_tgl  <= ~key_up_tgl;
            if (ev_valid && ev_key_dn)  key_down_tgl<= ~key_down_tgl;
            if (ev_valid && ev_seek_fwd5) seek_fwd5_tgl<=~seek_fwd5_tgl;
            if (ev_valid && ev_seek_bwd5) seek_bwd5_tgl<=~seek_bwd5_tgl;
            if (ev_valid && ev_replay)    replay_tgl   <=~replay_tgl;
        end
    end
endmodule
`endif

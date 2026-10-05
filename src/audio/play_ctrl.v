`timescale 1ns/1ps
`ifndef EXP_PLAY_CTRL_V
`define EXP_PLAY_CTRL_V
// =============================================================================
// play_ctrl —— S5：播放态控制（选曲 / 播放暂停 / 切曲 / 音量）
//
// 运行在板级 clk(50 MHz) 域，与 ui_event_bridge 同域，因此事件侧只需
// 3 级 FF 同步 + 边沿检测（沿用 S2/S3 已验证的手法），不引入新的跨域通路。
//
// 交互约定（S5 冻结）：
//   浏览态 -EC1 旋转 换封面 / EC1 按压 进 2x2 缩略图      （S3 行为不变）
//   缩略图 -EC1 旋转移焦点 / EC1 按压 选定并进入播放态     （复用 S3 确认脉冲）
//   播放态 -EC1 旋转 切上一首/下一首；EC1 按压 暂停/恢复
//           KEY04(上) 音量+ / KEY05(下) 音量−；KEY07 退出播放态
//
// 音量在 [VOL_MIN, VOL_MAX] 之间做饱和钳位，避免溢出回绕成静音/爆音。
// 播放态由 play_active 表达；paused 只影响"时基是否推进"，不停 SD 读请求，
// 这样恢复播放不会有重新预取造成的爆音。
// =============================================================================
module play_ctrl #(
    parameter [7:0] VOL_DEFAULT = 8'd200,
    parameter [7:0] VOL_STEP    = 8'd16,
    parameter [7:0] VOL_MIN     = 8'd32,
    parameter [7:0] VOL_MAX     = 8'd255
)(
    input  wire       clk,
    input  wire       rst_n,

    input  wire [2:0] song_total,     // 可用曲目数（0/1 均按 1 首处理）
    input  wire       song_confirm,   // 1 拍：缩略图确认（browse_fsm）
    input  wire [1:0] focus_index,    // 确认时的焦点 = 起始曲目

    input  wire       enc_cw_tgl,     // EC1 顺时针（电平翻转）
    input  wire       enc_ccw_tgl,    // EC1 逆时针
    input  wire       confirm_tgl,    // EC1 按压 / KEY02（播放态 = 暂停/恢复）
    input  wire       key_up_tgl,     // KEY04
    input  wire       key_down_tgl,   // KEY05
    input  wire       stop_tgl,       // KEY07 退出播放态

    output reg        play_active,
    output reg        paused,
    output reg [1:0]  sel_song,
    output reg [7:0]  volume,
    output reg        track_step,     // 1 拍：请求换封面（顶层层转成 fs_next/prev）
    output reg        track_dir       // 1=下一首 0=上一首
);
    // ---- CDC：3 级 FF + 边沿检测 ----
    reg cw_s1, cw_s2, cw_s3;
    reg ccw_s1, ccw_s2, ccw_s3;
    reg cf_s1, cf_s2, cf_s3;
    reg up_s1, up_s2, up_s3;
    reg dn_s1, dn_s2, dn_s3;
    reg st_s1, st_s2, st_s3;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cw_s1 <= 1'b0;  cw_s2 <= 1'b0;  cw_s3 <= 1'b0;
            ccw_s1 <= 1'b0; ccw_s2 <= 1'b0; ccw_s3 <= 1'b0;
            cf_s1 <= 1'b0;  cf_s2 <= 1'b0;  cf_s3 <= 1'b0;
            up_s1 <= 1'b0;  up_s2 <= 1'b0;  up_s3 <= 1'b0;
            dn_s1 <= 1'b0;  dn_s2 <= 1'b0;  dn_s3 <= 1'b0;
            st_s1 <= 1'b0;  st_s2 <= 1'b0;  st_s3 <= 1'b0;
        end else begin
            cw_s1  <= enc_cw_tgl;   cw_s2  <= cw_s1;   cw_s3  <= cw_s2;
            ccw_s1 <= enc_ccw_tgl;  ccw_s2 <= ccw_s1;  ccw_s3 <= ccw_s2;
            cf_s1  <= confirm_tgl;  cf_s2  <= cf_s1;   cf_s3  <= cf_s2;
            up_s1  <= key_up_tgl;   up_s2  <= up_s1;   up_s3  <= up_s2;
            dn_s1  <= key_down_tgl; dn_s2  <= dn_s1;   dn_s3  <= dn_s2;
            st_s1  <= stop_tgl;     st_s2  <= st_s1;   st_s3  <= st_s2;
        end
    end

    wire p_cw  = cw_s2  ^ cw_s3;
    wire p_ccw = ccw_s2 ^ ccw_s3;
    wire p_cf  = cf_s2  ^ cf_s3;
    wire p_up  = up_s2  ^ up_s3;
    wire p_dn  = dn_s2  ^ dn_s3;
    wire p_stop= st_s2  ^ st_s3;

    // 曲目数归一化（0/1 都按 1 首）
    wire [1:0] tot = (song_total < 3'd2) ? 2'd1 : song_total[1:0];

    wire [1:0] sel_next = (sel_song >= (tot - 2'd1)) ? 2'd0 : (sel_song + 2'd1);
    wire [1:0] sel_prev = (sel_song == 2'd0) ? (tot - 2'd1) : (sel_song - 2'd1);

    wire [8:0] vol_up_sum = {1'b0, volume} + {1'b0, VOL_STEP};
    wire [8:0] vol_dn_sub = {1'b0, volume} - {1'b0, VOL_STEP};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            play_active <= 1'b0;
            paused      <= 1'b0;
            sel_song    <= 2'd0;
            volume      <= VOL_DEFAULT;
            track_step  <= 1'b0;
            track_dir   <= 1'b1;
        end else begin
            track_step <= 1'b0;

            if (!play_active) begin
                // 缩略图确认：选定该曲目并进入播放态（封面切换由 S3 选图路径完成）
                if (song_confirm) begin
                    play_active <= 1'b1;
                    paused      <= 1'b0;
                    sel_song    <= focus_index;
                end
            end else begin
                if (p_stop) begin
                    play_active <= 1'b0;
                    paused      <= 1'b0;
                end else begin
                    // 播放态内 EC1 按压 = 暂停/恢复（注意：进入播放态的那一拍
                    // play_active 仍为 0，因此不会被同一次确认立刻翻成暂停）
                    if (p_cf) paused <= ~paused;

                    if (p_cw) begin
                        sel_song   <= sel_next;
                        track_step <= 1'b1;
                        track_dir  <= 1'b1;
                    end else if (p_ccw) begin
                        sel_song   <= sel_prev;
                        track_step <= 1'b1;
                        track_dir  <= 1'b0;
                    end

                    if (p_up)
                        volume <= (vol_up_sum > {1'b0, VOL_MAX}) ? VOL_MAX
                                                                 : vol_up_sum[7:0];
                    else if (p_dn)
                        volume <= (vol_dn_sub < {1'b0, VOL_MIN}) ? VOL_MIN
                                                                 : vol_dn_sub[7:0];
                end
            end
        end
    end
endmodule
`endif

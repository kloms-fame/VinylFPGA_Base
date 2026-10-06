`timescale 1ns/1ps
`ifndef EXP_PLAY_CTRL_V
`define EXP_PLAY_CTRL_V
// =============================================================================
// play_ctrl —— S5：播放态控制（选曲 / 播放暂停 / 切曲 / 音量）
//
// Runs in sd_card_clk, alongside browse_fsm. UI toggle inputs cross from clk.
// browse_fsm exclusively routes KEY7 / KEY11 into stop_request; song_confirm
// starts the displayed/focused bank. End policy defaults to pause in PLAY.
// Normal pause retains buffered data; EOF replay and every track step request a
// drained stream_session restart. Storage failures are not successful EOF.
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
    input  wire       song_confirm,   // 1 拍：主界面/缩略图确认
    input  wire [1:0] focus_index,    // 确认时的焦点 = 起始曲目

    input  wire       enc_cw_tgl,     // EC1 顺时针（电平翻转）
    input  wire       enc_ccw_tgl,    // EC1 逆时针
    input  wire       confirm_tgl,    // EC1 按压 / KEY02（播放态 = 暂停/恢复）
    input  wire       key_up_tgl,     // KEY04
    input  wire       key_down_tgl,   // KEY05
    input  wire       stop_request,
    input  wire       media_lost,
    input  wire       stream_end,     // synchronized drained, successful EOF
    input  wire       end_mode_tgl,
    output reg [1:0]  end_mode,       // 0=pause, 1=repeat, 2=next
    output reg        restart_request,
    input  wire       stop_tgl,       // legacy stop toggle (top uses routed stop_request)

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

    reg [2:0] end_sync;
    reg eof_seen, ended;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) end_sync <= 3'd0;
        else end_sync <= {end_sync[1:0], end_mode_tgl};
    end
    wire mode_event = end_sync[2] ^ end_sync[1];
    // Preserve all four songs; zero songs cannot start playback.
    wire [2:0] tot = (song_total < 3'd2) ? 3'd1 : song_total;

    wire [1:0] sel_next = (sel_song >= (tot - 3'd1)) ? 2'd0 : (sel_song + 2'd1);
    wire [1:0] sel_prev = (sel_song == 2'd0) ? (tot - 3'd1) : (sel_song - 2'd1);

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
            end_mode <= 2'd0;
            restart_request <= 1'b0;
            eof_seen <= 1'b0;
            ended <= 1'b0;
        end else begin
            track_step <= 1'b0;
            restart_request <= 1'b0;
            if (mode_event) end_mode <= (end_mode == 2'd2) ? 2'd0 : end_mode + 1'b1;
            if (!stream_end) eof_seen <= 1'b0;

            if (p_stop || stop_request || media_lost) begin
                play_active <= 1'b0;
                paused <= 1'b0;
                ended <= 1'b0;
            end else if (!play_active) begin
                if (song_confirm && song_total != 0) begin
                    play_active <= 1'b1;
                    paused <= 1'b0;
                    ended <= 1'b0;
                    sel_song <= focus_index;
                    restart_request <= 1'b1;
                end
            end else begin
                if (p_cw || p_ccw) begin
                    sel_song <= p_cw ? sel_next : sel_prev;
                    track_step <= 1'b1;
                    track_dir <= p_cw;
                    paused <= 1'b0;
                    ended <= 1'b0;
                    restart_request <= 1'b1;
                    eof_seen <= 1'b1;
                end else if (p_cf) begin
                    if (ended) begin
                        paused <= 1'b0;
                        ended <= 1'b0;
                        restart_request <= 1'b1;
                    end else paused <= ~paused;
                end else if (stream_end && !eof_seen && !paused) begin
                    eof_seen <= 1'b1;
                    if (end_mode == 2'd0) begin
                        paused <= 1'b1;
                        ended <= 1'b1;
                    end else begin
                        restart_request <= 1'b1;
                        if (end_mode == 2'd2) begin
                            sel_song <= sel_next;
                            track_step <= 1'b1;
                            track_dir <= 1'b1;
                        end
                    end
                end
                if (p_up)
                    volume <= (vol_up_sum > {1'b0, VOL_MAX}) ? VOL_MAX : vol_up_sum[7:0];
                else if (p_dn)
                    volume <= ({1'b0, volume} < ({1'b0, VOL_MIN}+{1'b0,VOL_STEP})) ? VOL_MIN : vol_dn_sub[7:0];
            end
        end
    end
endmodule
`endif

`timescale 1ns/1ps

// =============================================================================
// S5 回归：统一 48 kHz 时基 + 播放控制 + 单行歌词渲染
//
//   1) timebase_48k：48 个采样节拍 = 1 ms；running=0 冻结；restart 清零
//   2) play_ctrl   ：确认进播放态 / 再按暂停 / EC1 正反转切曲 / KEY04-05 音量
//                    （含上下饱和钳位）/ KEY07 退出
//   3) lrc_osd     ：按 cur_time_ms 选行后，在歌词框内确实点亮了字形像素
// =============================================================================
module tb_s5_play;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    integer errors = 0;
    integer i;

    always #5 clk = ~clk;      // 100 MHz

    task check;
        input cond;
        input [8*56:1] name;
        begin
            if (!cond) begin
                $display("FAIL: %0s", name);
                errors = errors + 1;
            end
        end
    endtask

    // ---------------- 1) timebase_48k ----------------
    reg        tb_tick = 1'b0, tb_run = 1'b0, tb_restart = 1'b0;
    wire [31:0] tb_cnt, tb_ms;
    wire [5:0]  tb_sub;

    timebase_48k u_tb (
        .clk(clk), .rst_n(rst_n), .sample_tick(tb_tick), .running(tb_run),
        .restart(tb_restart), .sample_count(tb_cnt), .cur_time_ms(tb_ms),
        .sub_sample(tb_sub)
    );

    task tb_pulse_ms;
        input integer n;
        integer k;
        begin
            for (k = 0; k < n * 48; k = k + 1) begin
                @(negedge clk); tb_tick = 1'b1;
                @(negedge clk); tb_tick = 1'b0;
            end
        end
    endtask

    // ---------------- 2) play_ctrl ----------------
    reg        pc_enc_cw = 0, pc_enc_ccw = 0, pc_confirm = 0, pc_up = 0, pc_dn = 0, pc_stop = 0;
    reg        pc_confirm_pulse = 0;
    reg  [1:0] pc_focus = 2'd0;
    reg  [2:0] pc_total = 3'd4;
    wire       pc_active, pc_paused, pc_step, pc_dir;
    wire [1:0] pc_sel;
    wire [7:0] pc_vol;

    play_ctrl u_pc (.stop_request(1'b0),.media_lost(1'b0),.stream_end(1'b0),.end_mode_tgl(1'b0),
        .clk(clk), .rst_n(rst_n),
        .song_total(pc_total), .song_confirm(pc_confirm_pulse), .focus_index(pc_focus),
        .enc_cw_tgl(pc_enc_cw), .enc_ccw_tgl(pc_enc_ccw), .confirm_tgl(pc_confirm),
        .key_up_tgl(pc_up), .key_down_tgl(pc_dn), .stop_tgl(pc_stop),
        .play_active(pc_active), .paused(pc_paused), .sel_song(pc_sel),
        .volume(pc_vol), .track_step(pc_step), .track_dir(pc_dir)
    );

    integer step_count = 0;
    always @(posedge clk) if (rst_n && pc_step) step_count = step_count + 1;

    // 1=cw 2=ccw 3=confirm 4=up 5=down 6=stop
    task toggle;
        input integer which;
        begin
            @(negedge clk);
            case (which)
                1: pc_enc_cw  = ~pc_enc_cw;
                2: pc_enc_ccw = ~pc_enc_ccw;
                3: pc_confirm = ~pc_confirm;
                4: pc_up      = ~pc_up;
                5: pc_dn      = ~pc_dn;
                default: pc_stop = ~pc_stop;
            endcase
            repeat (8) @(posedge clk);
        end
    endtask

    task confirm_song;
        input [1:0] idx;
        begin
            @(negedge clk); pc_focus = idx; pc_confirm_pulse = 1'b1;
            @(negedge clk); pc_confirm_pulse = 1'b0;
            repeat (4) @(posedge clk);
        end
    endtask

    // ---------------- 3) lrc_osd ----------------
    reg        lo_vs = 1'b0, lo_de = 1'b0;
    reg [9:0]  lo_x = 10'd0;
    reg [31:0] lo_time = 32'd0;
    wire [23:0] lo_rgb;
    wire        lo_hit;
    integer     hits = 0;
    integer     line, px;

    lrc_osd u_lrc (
        .clk(clk), .rst_n(rst_n), .vs(lo_vs), .de(lo_de), .pixel_x(lo_x),
        .enable(1'b1), .time_ms(lo_time), .rgb_in(24'h000000),
        .rgb_out(lo_rgb), .hit(lo_hit)
    );

    always @(posedge clk) if (rst_n && lo_hit) hits = hits + 1;

    // 扫一帧：先给 vs 低脉冲，再逐行推进 de 窗口（800x525 的简化版）
    task scan_frame;
        begin
            hits = 0;
            @(negedge clk); lo_vs = 1'b0; lo_de = 1'b0;
            repeat (4) @(posedge clk);
            @(negedge clk); lo_vs = 1'b1;
            repeat (10) @(posedge clk);
            for (line = 0; line < 480; line = line + 1) begin
                for (px = 0; px < 640; px = px + 1) begin
                    @(negedge clk);
                    lo_x = px[9:0];
                    lo_de = 1'b1;
                end
                @(negedge clk); lo_de = 1'b0;
                repeat (2) @(posedge clk);
            end
        end
    endtask

    initial begin
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (4) @(posedge clk);

        // ---- 1) 时基 ----
        tb_run = 1'b1;
        tb_pulse_ms(1);
        check(tb_ms === 32'd1, "48 拍 = 1 ms");
        check(tb_sub === 6'd0, "1 ms 后 sub_sample 归零");
        tb_pulse_ms(4);
        check(tb_ms === 32'd5, "5 ms 累计正确");
        tb_run = 1'b0;
        tb_pulse_ms(3);
        check(tb_ms === 32'd5, "running=0 时时基冻结（暂停语义）");
        tb_run = 1'b1;
        @(negedge clk); tb_restart = 1'b1;
        @(negedge clk); tb_restart = 1'b0;
        check(tb_ms === 32'd0 && tb_cnt === 32'd0, "restart 清零时基（切曲语义）");
        tb_run = 1'b0;

        // ---- 2) 播放控制 ----
        check(pc_active === 1'b0, "上电不在播放态");
        confirm_song(2'd2);
        check(pc_active === 1'b1 && pc_sel === 2'd2 && pc_paused === 1'b0,
              "缩略图确认 -> 进入播放态并选中该曲目");

        toggle(3);
        check(pc_paused === 1'b1, "播放态 EC1 按压 -> 暂停");
        toggle(3);
        check(pc_paused === 1'b0, "再按一次 -> 恢复");

        step_count = 0;
        toggle(1);
        check(pc_sel === 2'd3 && step_count == 1, "EC1 顺时针 -> 下一首（并发出一次切曲请求）");
        toggle(1);
        check(pc_sel === 2'd0, "曲目回绕 3 -> 0");
        toggle(2);
        check(pc_sel === 2'd3, "EC1 逆时针 -> 上一首回绕 0 -> 3");

        toggle(4);
        check(pc_vol == 8'd216, "KEY04 音量 +16");
        toggle(5); toggle(5);
        check(pc_vol == 8'd184, "KEY05 音量 -16 x2");

        // 音量下界钳位：连续下调直到不再变化
        for (i = 0; i < 20; i = i + 1) toggle(5);
        check(pc_vol == 8'd32, "音量下界钳位到 VOL_MIN=32");
        for (i = 0; i < 20; i = i + 1) toggle(4);
        check(pc_vol == 8'd255, "音量上界钳位到 VOL_MAX=255");

        toggle(6);
        check(pc_active === 1'b0, "KEY07 退出播放态");

        // ---- 3) 歌词渲染 ----
        lo_time = 32'd0;
        scan_frame;
        check(hits > 200, "t=0ms 首行歌词确实点亮像素");
        lo_time = 32'd11500;      // 落在 [10000,13500) 这一行
        scan_frame;
        check(hits > 200, "t=11.5s 对应歌词行点亮像素");
        lo_time = 32'hFFFFFFFF;   // 超过最后一行时间之前仍应显示最后一行
        scan_frame;
        check(hits > 200, "超出末行时间仍显示最后一行");

        if (errors == 0)
            $display("TEST_PASS s5_play_timebase_lrc");
        else
            $display("FAIL: tb_s5_play errors=%0d", errors);
        $finish;
    end

    initial begin
        #400_000_000;
        $display("FAIL: tb_s5_play timeout");
        $finish;
    end
endmodule

`timescale 1ns/1ps

// =============================================================================
// S7-03b 回归：切歌模式(KEY07) / 返回主界面(KEY11) 归属。
//
// S7-03b 变更点（承接 S7-03 统一事件路由，纠正上板验收反馈）：
//   - 浏览态 confirm 仍不打开 2x2 缩略图（保持 S3 冻结语义）；
//   - 播放态 KEY07 直接打开缩略图选曲并同拍 play_stop，不再先回主界面；
//   - 播放态 KEY11 停止播放并 go_home 回主界面全屏，不打开缩略图。
//   thumb_mode / play_stop / go_home 全部在 sd_card_clk 单域同拍生成，
//   与旧版跨域"退出播放 + 翻转视图"竞态路径无关。
// =============================================================================
module tb_s7_browse_semantics;
    reg  clk=0, rst=0, cf=0, md=0, ht=0, playing=0;
    wire grid, stop, home;
    integer errors = 0;

    always #5 clk = ~clk;

    browse_fsm dut(
        .clk(clk), .rst_n(rst),
        .ev_prev_tgl(1'b0), .ev_next_tgl(1'b0),
        .ev_home_tgl(ht), .ev_confirm_tgl(cf), .ev_mode_tgl(md),

        .view_mode(1'b0), .mode_play(playing),
        .thumb_mode(grid), .play_stop(stop), .go_home(home));

    reg grid_seen, stop_seen, home_seen;
    always @(posedge clk) begin
        if (rst) begin
            if (grid) grid_seen <= 1'b1;
            if (stop) stop_seen <= 1'b1;
            if (home) home_seen <= 1'b1;
        end
    end

    task clear_flags; begin
        grid_seen = 1'b0; stop_seen = 1'b0; home_seen = 1'b0;
    end endtask

    initial begin
        repeat (4) @(negedge clk);
        rst = 1'b1;
        repeat (4) @(negedge clk);

        // 1) 浏览态 confirm：不得打开缩略图。
        clear_flags;
        cf = ~cf;
        repeat (12) @(posedge clk);
        if (grid_seen) begin $display("FAIL browse confirm opened grid"); errors = errors + 1; end
        if (stop_seen) begin $display("FAIL browse confirm produced play_stop"); errors = errors + 1; end

        // 2) 播放态 KEY07：直接打开缩略图 + 退出播放，不回主界面。
        clear_flags;
        playing = 1'b1;
        md = ~md;
        repeat (12) @(posedge clk);
        if (!grid_seen) begin $display("FAIL PLAY KEY7 must open grid"); errors = errors + 1; end
        if (!stop_seen) begin $display("FAIL PLAY KEY7 must stop playback"); errors = errors + 1; end
        if (home_seen)  begin $display("FAIL PLAY KEY7 must not go home"); errors = errors + 1; end

        // 3) 播放态 KEY11：停止播放 + 回主界面，不打开缩略图。
        clear_flags;
        ht = ~ht;
        repeat (12) @(posedge clk);
        if (grid_seen)  begin $display("FAIL PLAY KEY11 must not open grid"); errors = errors + 1; end
        if (!stop_seen) begin $display("FAIL PLAY KEY11 must stop playback"); errors = errors + 1; end
        if (!home_seen) begin $display("FAIL PLAY KEY11 must go home"); errors = errors + 1; end

        if (errors == 0)
            $display("PASS s7_03b_mode_home_ownership");
        else
            $display("FAIL s7_browse_semantics errors=%0d", errors);
        $finish;
    end
endmodule

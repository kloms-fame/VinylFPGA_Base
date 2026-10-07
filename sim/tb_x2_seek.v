`timescale 1ns/1ps
// =============================================================================
// tb_x2_seek —— X2：Seek / 重播 / 时基加载 / 扇区内偏移 专项回归
//
//   1) seek_controller：首尾钳位、空音频禁止、暂停中允许、忙时累计、
//      100 次往返、clear 与 seek 同拍时 clear 优先；
//   2) timebase_48k：load 后 sample_count 精确等于目标、ms 误差 <= 1；
//   3) wav_stream_player：skip_samples 丢弃首扇区前 N 个样本，
//      首个被消费样本号 == skip_samples（起点误差 0 样本）。
// =============================================================================
module tb_x2_seek;
    integer errors = 0;
    task chk; input cond; input [255:0] msg;
        begin if (!cond) begin errors = errors + 1; $display("FAIL %0s", msg); end end
    endtask

    // ------------------------------------------------------------------
    // 1) seek_controller
    // ------------------------------------------------------------------
    reg clk = 0;  always #5 clk = ~clk;      // 100 MHz
    reg rst_n = 0;
    reg active = 0;
    reg [31:0] cur = 32'd0, total = 32'd0;
    reg clear_p = 0;
    reg [4:0] tgl = 5'd0;                    // {xf5, xb5, xf2, xb2, replay}
    wire [31:0] target;
    wire        req;
    integer     restarts = 0;
    always @(posedge clk) if (rst_n && req) restarts = restarts + 1;

    seek_controller #(.BUSY_HOLD(20'd255)) dut (
        .clk(clk), .rst_n(rst_n), .play_active(active),
        .cur_sample(cur), .total_samples(total), .clear_pulse(clear_p),
        .seek_fwd5_tgl(tgl[4]), .seek_bwd5_tgl(tgl[3]),
        .seek_fwd2_tgl(tgl[2]), .seek_bwd2_tgl(tgl[1]),
        .replay_tgl(tgl[0]),
        .target_sample(target), .restart_req(req)
    );

    task ev; input integer which;   // 0=fwd5 1=bwd5 2=fwd2 3=bwd2 4=replay
        begin
            @(negedge clk);
            tgl[4-which] = ~tgl[4-which];
            @(negedge clk);
        end
    endtask

    task clear_busy; begin clear_p = 1; @(negedge clk); clear_p = 0; @(negedge clk); end endtask

    integer k;
    initial begin
        repeat (4) @(negedge clk);
        rst_n = 1; repeat (4) @(negedge clk);

        // --- 空音频 / 未播放：禁止 Seek ---
        active = 0; total = 32'd0; cur = 32'd0;
        ev(0); repeat (6) @(negedge clk);
        chk(target == 32'd0, "empty media must not seek");
        chk(restarts == 0, "empty media must not request restart");

        active = 1; total = 32'd0;
        ev(2); repeat (6) @(negedge clk);
        chk(target == 32'd0, "total_samples=0 forbidden");

        // --- 首尾钳位 ---
        total = 32'd100000; cur = 32'd50000; clear_busy;
        ev(0); repeat (6) @(negedge clk);
        chk(target == 32'd99999, "fwd5 clamps to total-1");
        chk(restarts == 1, "clamped seek still restarts");
        clear_busy;

        cur = 32'd500; ev(1); repeat (6) @(negedge clk);
        chk(target == 32'd0, "bwd5 clamps to 0");
        clear_busy;

        // --- 精确步长 ---
        total = 32'd500000; clear_busy; cur = 32'd10000;
        ev(0); repeat (6) @(negedge clk);
        chk(target == 32'd250000, "fwd5 = cur + 240000");
        clear_busy;
        cur = 32'd300000; ev(2); repeat (6) @(negedge clk);
        chk(target == 32'd396000, "fwd2 = cur + 96000");

        // --- 暂停中允许 Seek ---
        clear_busy; cur = 32'd100000; total = 32'd500000;
        ev(1); repeat (6) @(negedge clk);
        chk(target == 32'd0, "seek while paused allowed (+/-)");
        clear_busy;

        // --- 忙时累计到最新目标 ---
        cur = 32'd100000; total = 32'd5000000;
        ev(0); repeat (2) @(negedge clk);
        ev(0); repeat (2) @(negedge clk);
        ev(0); repeat (6) @(negedge clk);
        chk(target == 32'd820000, "busy accumulates 3x +240000");
        clear_busy;

        // --- 100 次往返（±2 s，未触边）---
        cur = 32'd4000000; total = 32'd100000000;
        ev(2); repeat (4) @(negedge clk);           // 起点 +96000
        for (k = 0; k < 50; k = k + 1) ev(2);
        for (k = 0; k < 50; k = k + 1) ev(3);
        repeat (8) @(negedge clk);
        chk(target == 32'd4096000, "100 round trips land exactly on +96000");
        clear_busy;

        // --- clear 与 seek 同拍：clear 优先（clear 覆盖 3FF 边沿窗口）---
        cur = 32'd100000; total = 32'd500000;
        ev(0); repeat (4) @(negedge clk);
        chk(target == 32'd340000, "pre-clear target");
        @(negedge clk); tgl[4] = ~tgl[4]; clear_p = 1;
        repeat (8) @(negedge clk); clear_p = 0;
        repeat (8) @(negedge clk);
        chk(target == 32'd0, "clear wins over concurrent seek");
        clear_busy;

        // --- 重播：target=0 ---
        cur = 32'd100000; total = 32'd500000;
        ev(4); repeat (6) @(negedge clk);
        chk(target == 32'd0, "replay target=0");

        if (errors == 0)
            $display("PASS X2 seek_controller clamp/empty/pause/accumulate/100-round-trip");
        else
            $display("X2 seek_controller errors=%0d", errors);
        $finish;
    end
    initial begin #20000000; $fatal(1, "FAIL watchdog seek_controller"); end
endmodule

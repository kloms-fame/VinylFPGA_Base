`timescale 1ns/1ps
// =============================================================================
// tb_fixF_restart —— timebase_48k 的 restart / load 优先级回归
//
// 现行契约（seek 修复后）：
//   1) load 单独脉冲           -> 时基加载到 load_sample，cur_time_ms = n/48；
//   2) restart 单独脉冲        -> 硬清零（历史路径：只有 restart 没有 load）；
//   3) restart 与 load 同拍    -> load 优先（切曲/Seek/重播共用 restart 脉冲，
//                                 区别只在 load_sample），不得被清零；
//   4) restart+load 的转换窗口 -> cur_time_ms 立刻为 0，不得出现旧时间
//                                 （旧时间会被 mv_frame_scheduler 当成音频超前而连发帧）。
// =============================================================================
module tb_fixF_restart;
    reg clk = 0, rst_n = 0, restart = 0, load = 0;
    reg [31:0] load_sample = 32'd0;
    wire [31:0] sample_count, cur_time_ms;
    wire [5:0]  sub_sample;

    always #5 clk = ~clk;

    timebase_48k dut (
        .clk(clk), .rst_n(rst_n), .sample_tick(1'b0), .running(1'b0),
        .restart(restart), .load(load), .load_sample(load_sample),
        .sample_count(sample_count), .cur_time_ms(cur_time_ms), .sub_sample(sub_sample)
    );

    task pulse;
        input r; input l; input [31:0] n;
        begin
            @(negedge clk); restart = r; load = l; load_sample = n;
            @(negedge clk); restart = 0; load = 0;
        end
    endtask

    initial begin
        repeat (2) @(negedge clk);
        rst_n = 1;

        // 1) load 单独：480000 样本 = 10000 ms
        pulse(1'b0, 1'b1, 32'd480000);
        repeat (40) @(negedge clk);
        if (cur_time_ms != 32'd10000 || sample_count != 32'd480000)
            $fatal(1, "load only failed ms=%0d cnt=%0d", cur_time_ms, sample_count);

        // 2) restart 单独：清零
        pulse(1'b1, 1'b0, 32'd0);
        repeat (40) @(negedge clk);
        if (cur_time_ms != 0 || sample_count != 0)
            $fatal(1, "restart only must clear ms=%0d cnt=%0d", cur_time_ms, sample_count);

        // 3) restart 与 load 同拍：load 优先，144000 样本 = 3000 ms
        pulse(1'b1, 1'b1, 32'd144000);
        if (cur_time_ms != 0)
            $fatal(1, "conversion window must not hold stale ms=%0d", cur_time_ms);
        if (sample_count != 32'd144000)
            $fatal(1, "load must land in one cycle cnt=%0d", sample_count);
        repeat (40) @(negedge clk);
        if (cur_time_ms != 32'd3000 || sample_count != 32'd144000 || sub_sample != 0)
            $fatal(1, "restart+load must load target ms=%0d cnt=%0d sub=%0d",
                   cur_time_ms, sample_count, sub_sample);

        $display("PASS restart/load priority (load wins, conversion window clean)");
        $finish;
    end
endmodule

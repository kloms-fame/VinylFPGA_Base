`timescale 1ns/1ps
// S7-01B：health_monitor 定向验证
// 覆盖：复位清零 / 各计数器饱和自增 / 低水位播放门控 / sticky 最近错误码 /
//       相同错误码不重复、零错误码不覆盖 / 周期 STAT 请求。
module tb_health_monitor;
    reg         clk = 1'b0;
    reg         rst_n = 1'b0;
    reg         underrun_pulse = 1'b0;
    reg         buffer_low = 1'b0;
    reg         stream_active = 1'b0;
    reg         video_failed = 1'b0;
    reg         osd_err_valid = 1'b0;
    reg  [7:0]  osd_err_code = 8'd0;
    reg         ev_overflow = 1'b0;

    wire        stat_req;
    wire        err_req;
    wire [7:0]  err_code;
    wire [15:0] cnt_underrun;
    wire [15:0] cnt_buffer_low;
    wire [15:0] cnt_video_fail;
    wire [15:0] cnt_ev_overflow;
    wire [31:0] fw_version;

    integer     errors = 0;
    integer     i;
    reg         stat_seen = 1'b0;
    reg         err_seen  = 1'b0;

    health_monitor #(
        .CLK_FREQ_HZ   (50_000_000),
        .STAT_PERIOD_MS(1),
        .FW_VERSION    (32'h0701_0001)
    ) dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .underrun_pulse(underrun_pulse),
        .buffer_low    (buffer_low),
        .stream_active (stream_active),
        .video_failed  (video_failed),
        .osd_err_valid (osd_err_valid),
        .osd_err_code  (osd_err_code),
        .ev_overflow   (ev_overflow),
        .stat_req      (stat_req),
        .err_req       (err_req),
        .err_code      (err_code),
        .cnt_underrun  (cnt_underrun),
        .cnt_buffer_low(cnt_buffer_low),
        .cnt_video_fail(cnt_video_fail),
        .cnt_ev_overflow(cnt_ev_overflow),
        .fw_version    (fw_version)
    );

    always #10 clk = ~clk;   // 50 MHz
    always @(posedge clk) begin
        if (stat_req) stat_seen <= 1'b1;
        if (err_req)  err_seen  <= 1'b1;
    end

    initial begin
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (4) @(posedge clk);

        if (fw_version !== 32'h0701_0001) begin
            $display("FAIL fw_version=%h", fw_version);
            errors = errors + 1;
        end

        // 1) 欠载 3 次（下降沿置 1、下一个下降沿清 0，保证有一个 posedge 采样到 1）
        repeat (3) begin
            @(negedge clk); underrun_pulse = 1'b1;
            @(negedge clk); underrun_pulse = 1'b0;
        end
        repeat (2) @(posedge clk);
        if (cnt_underrun !== 16'd3) begin
            $display("FAIL cnt_underrun=%0d", cnt_underrun);
            errors = errors + 1;
        end

        // 2) 低水位：仅 stream_active 期间的上升沿计数
        stream_active = 1'b1; @(posedge clk);
        buffer_low = 1'b1; @(posedge clk); buffer_low = 1'b0; @(posedge clk);
        buffer_low = 1'b1; @(posedge clk); buffer_low = 1'b0; @(posedge clk);
        if (cnt_buffer_low !== 16'd2) begin
            $display("FAIL cnt_buffer_low=%0d", cnt_buffer_low);
            errors = errors + 1;
        end
        // 非播放期间不计数
        stream_active = 1'b0; @(posedge clk);
        buffer_low = 1'b1; @(posedge clk); buffer_low = 1'b0; @(posedge clk);
        if (cnt_buffer_low !== 16'd2) begin
            $display("FAIL cnt_buffer_low gated=%0d", cnt_buffer_low);
            errors = errors + 1;
        end

        // 3) MV 失败上升沿
        video_failed = 1'b1; @(posedge clk); video_failed = 1'b0; @(posedge clk);
        if (cnt_video_fail !== 16'd1) begin
            $display("FAIL cnt_video_fail=%0d", cnt_video_fail);
            errors = errors + 1;
        end

        // 4) 事件溢出 5 次
        repeat (5) begin
            @(negedge clk); ev_overflow = 1'b1;
            @(negedge clk); ev_overflow = 1'b0;
        end
        repeat (2) @(posedge clk);
        if (cnt_ev_overflow !== 16'd5) begin
            $display("FAIL cnt_ev_overflow=%0d", cnt_ev_overflow);
            errors = errors + 1;
        end

        // 5) sticky 错误码
        osd_err_code = 8'h0A;
        @(negedge clk); osd_err_valid = 1'b1;
        @(negedge clk); osd_err_valid = 1'b0;
        repeat (2) @(posedge clk);
        if (err_code !== 8'h0A) begin
            $display("FAIL err_code=%h", err_code);
            errors = errors + 1;
        end
        if (!err_seen) begin
            $display("FAIL err_req not asserted");
            errors = errors + 1;
        end
        // 相同错误码不重复上报
        err_seen = 1'b0;
        osd_err_code = 8'h0A;
        @(negedge clk); osd_err_valid = 1'b1;
        @(negedge clk); osd_err_valid = 1'b0;
        repeat (2) @(posedge clk);
        if (err_seen) begin
            $display("FAIL err_req re-asserted for same code");
            errors = errors + 1;
        end
        // 新错误码
        err_seen = 1'b0;
        osd_err_code = 8'h0B;
        @(negedge clk); osd_err_valid = 1'b1;
        @(negedge clk); osd_err_valid = 1'b0;
        repeat (2) @(posedge clk);
        if (err_code !== 8'h0B) begin
            $display("FAIL err_code new=%h", err_code);
            errors = errors + 1;
        end
        // 零错误码不覆盖 sticky
        osd_err_code = 8'h00;
        @(negedge clk); osd_err_valid = 1'b1;
        @(negedge clk); osd_err_valid = 1'b0;
        repeat (2) @(posedge clk);
        if (err_code !== 8'h0B) begin
            $display("FAIL err_code zero=%h", err_code);
            errors = errors + 1;
        end

        // 6) 饱和：欠载 65540 次后停在 0xFFFF，不归零
        for (i = 0; i < 65540; i = i + 1) begin
            @(negedge clk); underrun_pulse = 1'b1;
            @(negedge clk); underrun_pulse = 1'b0;
        end
        repeat (2) @(posedge clk);
        if (cnt_underrun !== 16'hFFFF) begin
            $display("FAIL saturate cnt_underrun=%0d", cnt_underrun);
            errors = errors + 1;
        end

        // 7) 周期 STAT
        repeat (60000) @(posedge clk);   // 1 ms @50 MHz = 50000 cycles，留余量
        if (!stat_seen) begin
            $display("FAIL stat_req never asserted");
            errors = errors + 1;
        end

        if (errors == 0)
            $display("TEST_PASS health_monitor");
        else
            $display("TEST_FAIL health_monitor errors=%0d", errors);
        $finish;
    end

    initial begin
        #100_000_000;
        $display("TEST_FAIL health_monitor watchdog timeout");
        $finish;
    end
endmodule

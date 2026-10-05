`timescale 1ns/1ps
// 第十二讲彩点修正回归：SDRAM 读突发节奏（避让刷新/忙 + 突发间隔 + 低水位兜底）
//
// 依据《第八讲：四bank帧缓存架构》：
//   BURST_GAP_CYCLES=12、controller_busy(Sdr_busy)、refresh_active(Sdr_init_ref_vld)
// 本测试逐条验证 frame_fifo_read 的新节流逻辑：
//   A. 刷新有效(Sdr_init_ref_vld=1)且 FIFO 不低于低水位时，不得发起读突发；
//   B. 控制器忙(Sdr_busy=1)且 FIFO 不低于低水位时，不得发起读突发；
//   C. FIFO 降到低水位时，即使控制器忙/刷新，也必须发起突发（不许欠载）；
//   D. 两次突发之间的空闲间隔 >= BURST_GAP_CYCLES；
//   E. 全帧字数一个不少（不能因为节流丢数或死锁）。
module tb_frame_fifo_read_pace;
    localparam integer BURST_SIZE       = 256;
    localparam integer BURST_GAP_CYCLES = 12;
    localparam integer LOW_WATERMARK    = 128;
    localparam integer TOTAL_WORDS      = 1024;

    reg         mem_clk = 1'b0;
    reg         rst = 1'b1;
    reg         read_req = 1'b0;
    reg  [20:0] read_len = TOTAL_WORDS;
    reg  [20:0] read_addr_0 = 21'd0;
    reg  [20:0] read_addr_1 = 21'd307200;
    reg  [20:0] read_addr_2 = 21'd614400;
    reg  [20:0] read_addr_3 = 21'd921600;
    reg  [1:0]  read_addr_index = 2'd2;

    reg         Sdr_init_ref_vld = 1'b0;
    reg         Sdr_busy = 1'b0;
    reg  [9:0]  wrusedw = 10'd200;

    wire        read_req_ack;
    wire        read_finish;
    wire        App_rd_en;
    wire [20:0] App_rd_addr;
    wire        fifo_aclr;

    integer     errors = 0;
    integer     rd_pulses = 0;
    integer     idle_cycles = 0;
    integer     min_gap = 999;
    integer     burst_count = 0;
    reg         rd_en_q = 1'b0;
    reg         saw_finish = 1'b0;

    always #4 mem_clk = ~mem_clk;

    frame_fifo_read #(
        .MEM_DATA_BITS     (32),
        .ADDR_BITS         (21),
        .BURST_BITS        (9),
        .FIFO_DEPTH        (512),
        .BURST_SIZE        (BURST_SIZE),
        .BURST_GAP_CYCLES  (BURST_GAP_CYCLES),
        .FIFO_LOW_WATERMARK(LOW_WATERMARK)
    ) dut (
        .rst               (rst),
        .mem_clk           (mem_clk),
        .Sdr_init_done     (1'b1),
        .Sdr_init_ref_vld  (Sdr_init_ref_vld),
        .Sdr_busy          (Sdr_busy),
        .Sdr_rd_en         (1'b0),
        .App_wr_busy       (1'b0),
        .O_rd_busy         (),
        .App_rd_en         (App_rd_en),
        .App_rd_addr       (App_rd_addr),
        .read_req          (read_req),
        .read_req_ack      (read_req_ack),
        .read_finish       (read_finish),
        .read_addr_0       (read_addr_0),
        .read_addr_1       (read_addr_1),
        .read_addr_2       (read_addr_2),
        .read_addr_3       (read_addr_3),
        .read_addr_index   (read_addr_index),
        .read_len          (read_len),
        .fifo_aclr         (fifo_aclr),
        .wrusedw           (wrusedw)
    );

    // 统计：脉冲数、突发数、两次突发之间的最小空闲周期
    always @(posedge mem_clk) begin
        if (!rst) begin
            if (App_rd_en) begin
                rd_pulses = rd_pulses + 1;
                if (!rd_en_q) begin
                    if (burst_count > 0) begin
                        if (idle_cycles < min_gap)
                            min_gap = idle_cycles;
                        if (idle_cycles < BURST_GAP_CYCLES) begin
                            $display("FAIL: burst gap %0d < %0d", idle_cycles, BURST_GAP_CYCLES);
                            errors = errors + 1;
                        end
                    end
                    burst_count = burst_count + 1;
                end
                idle_cycles = 0;
            end else if (rd_en_q) begin
                idle_cycles = 1;
            end else begin
                idle_cycles = idle_cycles + 1;
            end
            rd_en_q <= App_rd_en;
            if (read_finish)
                saw_finish <= 1'b1;
        end
    end

    task count_bursts_in_window;
        input integer cycles;
        output integer n;
        integer i;
        begin
            n = 0;
            for (i = 0; i < cycles; i = i + 1) begin
                @(posedge mem_clk);
                if (App_rd_en)
                    n = n + 1;
            end
        end
    endtask

    integer window_pulses;
    integer guard;

    initial begin
        // ---------- 复位与启动一次整帧读请求 ----------
        repeat (4) @(posedge mem_clk);
        rst = 1'b0;
        wrusedw = 10'd200;          // 高于低水位：必须等空闲窗口
        read_req = 1'b1;
        while (!read_req_ack) @(posedge mem_clk);

        // ---------- A. 刷新期间不得起突发 ----------
        Sdr_init_ref_vld = 1'b1;    // 在撤销 read_req 之前拉高，保证进入 S_CHECK_FIFO 时已在刷新
        @(negedge mem_clk);
        read_req = 1'b0;
        count_bursts_in_window(60, window_pulses);
        if (window_pulses != 0) begin
            $display("FAIL: %0d read pulses issued while refresh active", window_pulses);
            errors = errors + 1;
        end else begin
            $display("PASS: refresh window holds off new read bursts (60 cycles, 0 pulses)");
        end

        Sdr_init_ref_vld = 1'b0;
        guard = 0;
        while (!App_rd_en && guard < 200) begin
            @(posedge mem_clk);
            guard = guard + 1;
        end
        if (guard >= 200) begin
            $display("FAIL: read burst did not resume after refresh deasserted");
            errors = errors + 1;
        end else begin
            $display("PASS: read burst resumed %0d cycles after refresh deasserted", guard);
        end

        // ---------- B. 控制器忙期间不得起突发 ----------
        // 注意：突发一旦开始就不再中途打断（保持官方行为），所以必须在
        // 上一突发刚结束的第一个空闲周期就拉高 busy，才能验证“不新起突发”。
        while (App_rd_en) @(posedge mem_clk);   // 等当前突发结束
        Sdr_busy = 1'b1;                        // 立即拉高，让下一次突发无法起跑
        count_bursts_in_window(60, window_pulses);
        if (window_pulses != 0) begin
            $display("FAIL: %0d read pulses issued while controller busy", window_pulses);
            errors = errors + 1;
        end else begin
            $display("PASS: controller-busy window holds off new read bursts (60 cycles, 0 pulses)");
        end

        // ---------- C. 低水位兜底：忙 + 刷新也必须发突发 ----------
        wrusedw = 10'd64;           // 低于低水位
        Sdr_init_ref_vld = 1'b1;
        guard = 0;
        while (!App_rd_en && guard < 200) begin
            @(posedge mem_clk);
            guard = guard + 1;
        end
        if (guard >= 200) begin
            $display("FAIL: low-watermark fallback did not issue a burst while controller busy/refreshing");
            errors = errors + 1;
        end else begin
            $display("PASS: low-watermark fallback issued a burst (%0d cycles) despite busy+refresh", guard);
        end
        Sdr_busy = 1'b0;
        Sdr_init_ref_vld = 1'b0;

        // ---------- E. 跑完整帧，字数一个不少 ----------
        wrusedw = 10'd0;
        guard = 0;
        while (!saw_finish && guard < 20000) begin
            @(posedge mem_clk);
            guard = guard + 1;
        end
        read_req = 1'b0;
        repeat (4) @(posedge mem_clk);

        if (!saw_finish) begin
            $display("FAIL: read_finish not observed (possible deadlock)");
            errors = errors + 1;
        end
        if (rd_pulses != TOTAL_WORDS) begin
            $display("FAIL: rd_pulses=%0d expected=%0d", rd_pulses, TOTAL_WORDS);
            errors = errors + 1;
        end
        if (min_gap < BURST_GAP_CYCLES) begin
            $display("FAIL: min burst gap %0d < %0d", min_gap, BURST_GAP_CYCLES);
            errors = errors + 1;
        end

        if (errors == 0) begin
            $display("PASS: tb_frame_fifo_read_pace all checks passed (pulses=%0d bursts=%0d min_gap=%0d)",
                     rd_pulses, burst_count, min_gap);
        end else begin
            $display("FAIL: tb_frame_fifo_read_pace errors=%0d", errors);
        end
        $finish;
    end

    initial begin
        #500000;
        $display("FAIL: tb_frame_fifo_read_pace timeout");
        $finish;
    end
endmodule

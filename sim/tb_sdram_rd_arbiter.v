`timescale 1ns/1ps

// =============================================================================
// 第十三讲回归：sdram_rd_arbiter（SDRAM 唯一读口换手开关）
//
// 逐条验证“不影响现有全屏功能”这一硬约束：
//   A. 全屏模式（mode_active=0）下 app_rd_en/app_rd_addr/frw_rd_valid 与
//      改动前完全等价（纯组合直通，零延迟）；
//   B. 缩略图数据必须与 valid 同拍（不能额外打一拍，否则整体错位一个像素）；
//   C. 当前占用方还在连续发请求时，绝不允许换手；
//   D. 当前占用方静默超过 QUIET_CYCLES 后才换手，且换手后请求/数据分流正确；
//   E. 缩略图 -> 全屏方向的换手同样受静默窗口约束。
// =============================================================================
module tb_sdram_rd_arbiter;
    localparam integer QUIET_CYCLES = 8;

    reg         clk = 1'b0;
    reg         rst = 1'b1;
    reg         view_mode_req = 1'b0;

    reg         frw_rd_en = 1'b0;
    reg  [20:0] frw_rd_addr = 21'd0;
    wire        frw_rd_valid;

    reg         thumb_rd_req = 1'b0;
    reg  [20:0] thumb_rd_addr = 21'd0;
    wire        thumb_rd_valid;
    wire [31:0] thumb_rd_dout;

    wire        app_rd_en;
    wire [20:0] app_rd_addr;
    reg         sdr_rd_en = 1'b0;
    reg  [31:0] sdr_rd_dout = 32'd0;

    wire        mode_active;
    wire        mem_idle;

    integer errors = 0;
    integer guard;
    integer cycles_to_switch;
    reg [31:0] latched_dout;

    always #5 clk = ~clk;

    sdram_rd_arbiter #(
        .ADDR_WIDTH   (21),
        .QUIET_CYCLES (QUIET_CYCLES),
        .SYNC_STAGES  (2)
    ) dut (
        .clk            (clk),
        .rst            (rst),
        .view_mode_req  (view_mode_req),
        .frw_rd_en      (frw_rd_en),
        .frw_rd_addr    (frw_rd_addr),
        .frw_rd_valid   (frw_rd_valid),
        .thumb_rd_req   (thumb_rd_req),
        .thumb_rd_addr  (thumb_rd_addr),
        .thumb_rd_valid (thumb_rd_valid),
        .thumb_rd_dout  (thumb_rd_dout),
        .app_rd_en      (app_rd_en),
        .app_rd_addr    (app_rd_addr),
        .sdr_rd_en      (sdr_rd_en),
        .sdr_rd_dout    (sdr_rd_dout),
        .mode_active    (mode_active),
        .mem_idle       (mem_idle)
    );

    task fail;
        input [8*40-1:0] tag;
        begin
            $display("FAIL: %0s", tag);
            errors = errors + 1;
        end
    endtask

    initial begin
        // ---------- 复位 ----------
        repeat (4) @(posedge clk);
        rst = 1'b0;
        @(posedge clk); #1;
        if (mode_active !== 1'b0 || mem_idle !== 1'b1) begin
            $display("FAIL: reset state mode_active=%b mem_idle=%b", mode_active, mem_idle);
            errors = errors + 1;
        end

        // ---------- A. 全屏直通（组合，无延迟） ----------
        frw_rd_en   = 1'b1;
        frw_rd_addr = 21'h001234;
        #1;
        if (app_rd_en !== 1'b1 || app_rd_addr !== 21'h001234)
            fail("fullscreen pass-through of app_rd_en/app_rd_addr");
        if (frw_rd_valid !== 1'b0 || thumb_rd_valid !== 1'b0)
            fail("fullscreen valid routing before sdr_rd_en");

        sdr_rd_en   = 1'b1;
        sdr_rd_dout = 32'hDEAD_BEEF;
        #1;
        if (frw_rd_valid !== 1'b1)  fail("fullscreen frw_rd_valid must follow sdr_rd_en");
        if (thumb_rd_valid !== 1'b0) fail("fullscreen thumb_rd_valid must stay low");
        if (thumb_rd_dout !== 32'hDEAD_BEEF) fail("thumb_rd_dout must be same-cycle as sdr_rd_dout");
        sdr_rd_en   = 1'b0;
        frw_rd_en   = 1'b0;
        #1;

        // ---------- C. 占用方持续请求时不得换手 ----------
        view_mode_req = 1'b1;          // 请求切到缩略图
        frw_rd_en     = 1'b1;          // 全屏仍在连发读请求
        frw_rd_addr   = 21'h000100;
        repeat (6 * QUIET_CYCLES + 20) @(posedge clk);
        #1;
        if (mode_active !== 1'b0)
            fail("handoff happened while fullscreen owner kept requesting");
        if (app_rd_en !== 1'b1 || app_rd_addr !== 21'h000100)
            fail("fullscreen owner lost the read port while still active");

        // ---------- D. 静默窗后换手，且分流正确 ----------
        frw_rd_en = 1'b0;
        thumb_rd_req  = 1'b0;
        thumb_rd_addr = 21'h0ABCDE;
        cycles_to_switch = 0;
        guard = 0;
        while (mode_active !== 1'b1 && guard < 200) begin
            @(posedge clk); #1;
            cycles_to_switch = cycles_to_switch + 1;
            guard = guard + 1;
        end
        if (mode_active !== 1'b1)
            fail("handoff to thumbnail never happened after going quiet");
        else if (cycles_to_switch < QUIET_CYCLES) begin
            $display("FAIL: handoff too early (%0d cycles < quiet %0d)", cycles_to_switch, QUIET_CYCLES);
            errors = errors + 1;
        end
        else
            $display("PASS: handoff to thumbnail took %0d cycles (quiet window %0d)",
                     cycles_to_switch, QUIET_CYCLES);

        // 换手后：请求源应是缩略图侧
        thumb_rd_req = 1'b1;
        #1;
        if (app_rd_en !== 1'b1 || app_rd_addr !== 21'h0ABCDE)
            fail("thumb request not routed to app_rd_en/app_rd_addr after handoff");
        frw_rd_en   = 1'b1;             // 全屏侧即使拉请求也不应影响占用方
        frw_rd_addr = 21'h000777;
        #1;
        if (app_rd_addr !== 21'h0ABCDE)
            fail("non-owner request leaked into app_rd_addr");

        sdr_rd_en   = 1'b1;
        sdr_rd_dout = 32'h00FF_00FF;
        #1;
        if (thumb_rd_valid !== 1'b1)  fail("thumb_rd_valid must follow sdr_rd_en in thumbnail mode");
        if (frw_rd_valid !== 1'b0)    fail("frw_rd_valid must stay low in thumbnail mode");
        if (thumb_rd_dout !== 32'h00FF_00FF) fail("thumb_rd_dout same-cycle alignment broken");
        // 换手后数据必须与 valid 同拍，绝不能慢一拍（打拍会整体错位一个像素）
        @(posedge clk); #1;
        latched_dout = thumb_rd_dout;
        if (latched_dout !== 32'h00FF_00FF)
            fail("thumb_rd_dout changed on the next clock (extra pipeline stage)");
        sdr_rd_en = 1'b0;
        frw_rd_en = 1'b0;

        // ---------- E. 缩略图 -> 全屏换手同样受静默窗约束 ----------
        view_mode_req = 1'b0;
        thumb_rd_req  = 1'b1;           // 缩略图仍在连发请求
        repeat (6 * QUIET_CYCLES + 20) @(posedge clk);
        #1;
        if (mode_active !== 1'b1)
            fail("handoff back happened while thumbnail owner kept requesting");

        thumb_rd_req = 1'b0;
        cycles_to_switch = 0;
        guard = 0;
        while (mode_active !== 1'b0 && guard < 200) begin
            @(posedge clk); #1;
            cycles_to_switch = cycles_to_switch + 1;
            guard = guard + 1;
        end
        if (mode_active !== 1'b0)
            fail("handoff back to fullscreen never happened");
        else if (cycles_to_switch < QUIET_CYCLES) begin
            $display("FAIL: handoff back too early (%0d cycles)", cycles_to_switch);
            errors = errors + 1;
        end

        // 回到全屏后必须恢复纯组合直通
        frw_rd_en   = 1'b1;
        frw_rd_addr = 21'h000ABC;
        sdr_rd_en   = 1'b1;
        sdr_rd_dout = 32'h1122_3344;
        #1;
        if (app_rd_en !== 1'b1 || app_rd_addr !== 21'h000ABC)
            fail("fullscreen pass-through not restored after handoff back");
        if (frw_rd_valid !== 1'b1 || thumb_rd_valid !== 1'b0)
            fail("valid routing not restored after handoff back");
        if (thumb_rd_dout !== 32'h1122_3344)
            fail("thumb_rd_dout alignment broken after handoff back");

        if (errors == 0)
            $display("PASS: tb_sdram_rd_arbiter all checks passed");
        else
            $display("FAIL: tb_sdram_rd_arbiter errors=%0d", errors);

        $finish;
    end

    initial begin
        #200000;
        $display("FAIL: tb_sdram_rd_arbiter timeout");
        $finish;
    end
endmodule

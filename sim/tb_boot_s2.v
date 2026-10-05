`timescale 1ns/1ps
// =============================================================================
// tb_boot_s2 —— S2 开机 Logo/启动画面最小冒烟测试
//
// 覆盖：
//   1) 复位释放后处于 STATE_BOOT（boot_active=1）；
//   2) 盒内真的画出 Logo（有非黑像素、有亮部、亮部在画面中部）；
//   3) 盒外严格纯黑（不污染整屏背景）；
//   4) 一次 skip 事件 -> 下一帧边界离开 Boot，且事件只消费一次；
//   5) 首图就绪 + 最短显示时间到 -> 自动交接（无事件也能进浏览态）。
//
// 说明：为了在仿真里跑完整帧，这里用 640x480 有效像素 + 每行 3 拍消隐的
// 精简行/场时序；boot_layer 只依赖 de/vs/pixel_x，不依赖真实消隐长度。
// =============================================================================
module tb_boot_s2;

    `include "boot_logo_geom.vh"

    localparam integer LINE_PIX   = 640;
    localparam integer LINE_BLANK = 3;
    localparam integer LINES      = 480;
    // 盒外判据直接取自几何宏（留 4 像素余量给 ROM 同步读的 1 拍延迟），
    // 这样重新生成 Logo（改尺寸/裁剪盒）后测试台无需手改。
    localparam integer BOX_L = `BOOT_LOGO_X0 - 4;
    localparam integer BOX_R = `BOOT_LOGO_X0 + `BOOT_LOGO_CROP_W + 4;
    localparam integer BOX_T = `BOOT_LOGO_Y0 - 4;
    localparam integer BOX_B = `BOOT_LOGO_Y0 + `BOOT_LOGO_CROP_H + 4;
    localparam integer WORD_TOP = `BOOT_LOGO_Y0 + (`BOOT_LOGO_CROP_H * 3) / 4;

    reg clk = 1'b0;
    always #5 clk = ~clk;          // 100 MHz 仿真时钟（只影响仿真时长）

    reg        rst_n       = 1'b0;
    reg        de          = 1'b0;
    reg        vs          = 1'b0;
    reg [9:0]  px          = 10'd0;
    reg [9:0]  lx          = 10'd0;
    reg [9:0]  ly          = 10'd0;

    reg        skip_tg_a   = 1'b0;   // DUT A：靠事件跳过
    reg        img_ready_a = 1'b0;
    reg        skip_tg_b   = 1'b0;   // DUT B：靠首图就绪自动交接
    reg        img_ready_b = 1'b1;

    wire        active_a, active_b;
    wire [23:0] rgb_a, rgb_b;

    // CLK_FREQ_HZ=1_000_000 -> MS_DIV=1000，ms_tick 每 1000 拍一次。
    // DUT A 把 HOLD/TIMEOUT 设得远大于仿真时长，只可能被事件结束；
    // DUT B 用 4 ms 的 HOLD 走"首图就绪后自动交接"。
    boot_layer #(
        .BOOT_ENABLE  (1'b1),
        .CLK_FREQ_HZ  (1_000_000),
        .HOLD_MS      (30_000),
        .TIMEOUT_MS   (60_000),
        .BREATH_FLOOR (192)
    ) dut_a (
        .clk (clk), .rst_n (rst_n), .vs (vs), .de (de), .pixel_x (px),
        .skip_toggle (skip_tg_a), .first_image_ready (img_ready_a),
        .boot_active (active_a), .rgb (rgb_a)
    );

    boot_layer #(
        .BOOT_ENABLE  (1'b1),
        .CLK_FREQ_HZ  (1_000_000),
        .HOLD_MS      (4),
        .TIMEOUT_MS   (60_000),
        .BREATH_FLOOR (192)
    ) dut_b (
        .clk (clk), .rst_n (rst_n), .vs (vs), .de (de), .pixel_x (px),
        .skip_toggle (skip_tg_b), .first_image_ready (img_ready_b),
        .boot_active (active_b), .rgb (rgb_b)
    );

    // ------------------------- 精简 640x480 行/场时序 -------------------------
    always @(negedge clk) begin
        if (!rst_n) begin
            de <= 1'b0; vs <= 1'b0; px <= 10'd0; lx <= 10'd0; ly <= 10'd0;
        end else if (lx < LINE_PIX) begin
            de <= 1'b1;
            px <= lx;
            vs <= 1'b1;              // 有效像素区 vs 保持高（VS_POL=0 低有效）
            lx <= lx + 10'd1;
        end else begin
            de <= 1'b0;
            px <= 10'd0;
            if (lx < (LINE_PIX + LINE_BLANK)) begin
                // 640x480 实测 VS_POL=0（场同步低有效，V_SYNC=2 行）：
                // 最后一行结束后把 vs 拉低 2 拍，其余时间保持高。
                vs <= ~((ly == (LINES - 1)) && (lx < (LINE_PIX + 2)));
                lx <= lx + 10'd1;
            end else begin
                vs <= 1'b1;
                lx <= 10'd0;
                ly <= (ly == (LINES - 1)) ? 10'd0 : (ly + 10'd1);
            end
        end
    end

    // ------------------------- Logo 像素统计 -------------------------
    integer nonblack_a;
    integer outside_a;
    integer lower_a;
    integer maxlum_a;
    integer mid_bright_a;   // 中部（唱片标签区）亮像素计数
    integer frame_cnt;
    reg     vs_d;

    initial begin
        nonblack_a = 0;
        outside_a  = 0;
        lower_a    = 0;
        maxlum_a   = 0;
        mid_bright_a = 0;
        frame_cnt  = 0;
        vs_d       = 1'b0;
    end

    always @(negedge clk) if (rst_n) begin
        vs_d <= vs;
        if (vs_d && !vs)
            frame_cnt = frame_cnt + 1;

        if (de) begin
            if (rgb_a !== 24'd0) begin
                nonblack_a = nonblack_a + 1;
                // 盒外（留 4 像素余量给 ROM 同步读的 1 拍延迟）
                if (lx < BOX_L || lx > BOX_R || ly < BOX_T || ly > BOX_B)
                    outside_a = outside_a + 1;
                // 底部 "VinylFPGA" 字样所在的下半区
                if (ly > WORD_TOP)
                    lower_a = lower_a + 1;
                // 中部唱片标签区（原图亮部集中在 y≈208..235）
                if ((ly > (`BOOT_LOGO_Y0 + 90)) && (ly < (`BOOT_LOGO_Y0 + 170)) &&
                    ((rgb_a[23:16] + rgb_a[15:8] + rgb_a[7:0]) > 300))
                    mid_bright_a = mid_bright_a + 1;
                if ((rgb_a[23:16] + rgb_a[15:8] + rgb_a[7:0]) > maxlum_a)
                    maxlum_a = rgb_a[23:16] + rgb_a[15:8] + rgb_a[7:0];
            end
        end
    end

    // ------------------------- 激励 -------------------------
    // 按"完整场"等待：frame_cnt 每个 vs 下降沿只加 1
    task wait_frames;
        input integer n;
        integer target;
        begin
            target = frame_cnt + n;
            wait (frame_cnt >= target);
            @(negedge clk);
        end
    endtask

    initial begin
        if ($test$plusargs("vcd")) begin
            $dumpfile("tb_boot_s2.vcd");
            $dumpvars(0, tb_boot_s2);
        end

        repeat (10) @(negedge clk);
        rst_n = 1'b1;
        @(negedge clk);

        if (active_a !== 1'b1 || active_b !== 1'b1)
            $fatal(1, "FAIL reset did not enter STATE_BOOT");

        // ---- 第 1 帧：统计 Logo 渲染 ----
        wait_frames(1);
        if (nonblack_a < 500)
            $fatal(1, "FAIL logo too sparse, nonblack=%0d", nonblack_a);
        if (outside_a != 0)
            $fatal(1, "FAIL logo pixels outside crop box, outside=%0d", outside_a);
        if (maxlum_a < 200)
            $fatal(1, "FAIL logo has no bright content, maxlum=%0d", maxlum_a);
        if (mid_bright_a < 20)
            $fatal(1, "FAIL record label area not rendered, mid_bright=%0d", mid_bright_a);
        if (lower_a < 20)
            $fatal(1, "FAIL bottom wordmark missing, lower=%0d", lower_a);
        $display("PASS boot logo rendered: nonblack=%0d maxlum=%0d mid_bright=%0d lower=%0d",
                 nonblack_a, maxlum_a, mid_bright_a, lower_a);

        // ---- DUT B：首图就绪 + HOLD 到点应自动离开 Boot ----
        wait_frames(3);
        if (active_b !== 1'b0)
            $fatal(1, "FAIL first-image handoff did not leave STATE_BOOT");
        $display("PASS first-image handoff to browse state");

        // ---- DUT A：一次事件 -> 下一帧边界离开 Boot ----
        skip_tg_a = 1'b1;
        wait_frames(3);
        if (active_a !== 1'b0)
            $fatal(1, "FAIL skip event did not leave STATE_BOOT");
        $display("PASS skip event left STATE_BOOT at frame boundary");

        // ---- 事件只消费一次：继续跑帧，状态不得回弹 ----
        wait_frames(2);
        if (active_a !== 1'b0 || active_b !== 1'b0)
            $fatal(1, "FAIL state re-entered boot after leaving");
        if (outside_a != 0)
            $fatal(1, "FAIL logo drawn after leaving boot");
        $display("PASS event consumed once, no re-entry");

        $display("TEST_PASS boot_s2_smoke");
        $finish;
    end

    initial begin
        #40_000_000;
        $fatal(1, "FAIL timeout waiting for boot_s2 smoke to finish");
    end

endmodule

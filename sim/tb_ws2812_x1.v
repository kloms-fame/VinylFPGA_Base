// =============================================================================
// tb_ws2812_x1 —— X1B WS2812 灯效 + 串行器联合仿真（25 MHz 域）
//
// 用一个"高电平宽度判别"的 WS2812 接收模型解码单线流：
//   high < 550 ns -> bit 0（T0H）；high >= 550 ns -> bit 1（T1H）。
// 每 192 bit 组成一帧（8 颗 × 24 bit GRB），解码后逐像素比对。
//
// 覆盖：mode0 全灭（含 DIP6 关断补发黑帧）/ mode1 音频律动 GRB 顺序 /
//       mode2 进度条点亮颗数。
// =============================================================================
`timescale 1ns/1ps
module tb_ws2812_x1;
    localparam integer CLK_NS = 40;      // 25 MHz

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg enable = 1'b1;
    reg mode_tgl = 1'b0;
    reg [7:0] level = 8'd0;
    reg [3:0] progress = 4'd0;
    wire ws_data;

    wire [191:0] frame_pix;
    integer frame_ready = 0;
    integer errors = 0;

    ws2812_effects #(
        .PIXEL_COUNT (8),
        .CLK_FREQ_HZ (25_000_000),
        .REFRESH_MS  (1)                 // 仿真用：1 ms 刷新
    ) dut (
        .clk      (clk),
        .rst_n    (rst_n),
        .enable   (enable),
        .mode_tgl (mode_tgl),
        .level    (level),
        .progress (progress),
        .mute     (1'b0),
        .ws_data  (ws_data)
    );

    always #(CLK_NS/2) clk = ~clk;

    // ---------------- WS2812 单线接收模型 ----------------
    reg [191:0] cap = 192'd0;
    reg [191:0] frozen = 192'd0;
    integer bitcnt = 0;
    time t_rise = 0;
    time t_last_fall = 0;
    integer high_ns = 0;

    assign frame_pix = frozen;

    always @(posedge ws_data) begin
        if (($time - t_last_fall) > 5000)     // > 5 us 低电平 = 帧复位
            bitcnt = 0;
        t_rise = $time;
    end

    always @(negedge ws_data) begin
        t_last_fall = $time;
        high_ns = $time - t_rise;
        if (bitcnt < 192) begin
            cap[191-bitcnt] = (high_ns > 550);
            bitcnt = bitcnt + 1;
            if (bitcnt == 192) begin
                frozen = cap;
                frame_ready = frame_ready + 1;
            end
        end
    end

    // ---------------- 辅助 ----------------
    task wait_next_frame;
        input integer prev;
        integer waited;
        begin
            waited = 0;
            while ((frame_ready == prev) && (waited < 4_000_000)) begin
                @(posedge clk);
                waited = waited + 1;
            end
            if (frame_ready == prev) begin
                errors = errors + 1;
                $display("FAIL no WS frame within timeout");
            end
        end
    endtask

    task expect_pixel;
        input [2:0] idx;
        input [23:0] want;
        input [255:0] name;
        reg [23:0] got;
        begin
            got = frozen[191 - idx*24 -: 24];
            if (got !== want) begin
                errors = errors + 1;
                $display("FAIL %0s: pixel%0d got %06h want %06h", name, idx, got, want);
            end
        end
    endtask

    task toggle_mode;
        begin
            @(negedge clk);
            mode_tgl = ~mode_tgl;
            repeat (6) @(posedge clk);
        end
    endtask

    integer fr;

    initial begin
        repeat (10) @(posedge clk);
        rst_n = 1'b1;

        // 1) 默认 mode0：整帧全黑
        fr = frame_ready;
        wait_next_frame(fr);
        expect_pixel(3'd0, 24'h000000, "mode0 p0 black");
        expect_pixel(3'd7, 24'h000000, "mode0 p7 black");

        // 2) KEY10 一次 -> mode1 律动；满量程 -> 8 颗全亮，RGB 顺序为 GRB
        toggle_mode;
        level = 8'd250;
        fr = frame_ready;
        wait_next_frame(fr);
        expect_pixel(3'd0, 24'hE00000, "mode1 p0 green");
        expect_pixel(3'd2, 24'hE00000, "mode1 p2 green");
        expect_pixel(3'd3, 24'hE0E000, "mode1 p3 yellow");
        expect_pixel(3'd6, 24'h20E000, "mode1 p6 red-ish");
        expect_pixel(3'd7, 24'h20E000, "mode1 p7 red-ish");

        // 3) 低包络 -> 只有前几颗亮
        level = 8'd20;                 // < 40 -> 1 颗
        fr = frame_ready;
        wait_next_frame(fr);
        expect_pixel(3'd0, 24'hE00000, "mode1 low p0 on");
        expect_pixel(3'd1, 24'h000000, "mode1 low p1 off");

        // 4) 再按一次 KEY10 -> mode2 进度条
        toggle_mode;
        progress = 4'd3;
        fr = frame_ready;
        wait_next_frame(fr);
        expect_pixel(3'd0, 24'h3000E0, "mode2 p0");
        expect_pixel(3'd2, 24'h3000E0, "mode2 p2");
        expect_pixel(3'd3, 24'h000000, "mode2 p3 off");

        // 5) DIP6 关断：必须补发一整帧黑色后才停刷新
        enable = 1'b0;
        fr = frame_ready;
        wait_next_frame(fr);
        expect_pixel(3'd0, 24'h000000, "DIP6 off p0 black");
        expect_pixel(3'd7, 24'h000000, "DIP6 off p7 black");

        if (errors == 0)
            $display("TEST_PASS ws2812_x1");
        else
            $display("TEST_FAIL ws2812_x1 errors=%0d", errors);
        $finish;
    end

    initial begin
        #200_000_000;
        $display("TEST_FAIL ws2812_x1 watchdog");
        $finish;
    end
endmodule

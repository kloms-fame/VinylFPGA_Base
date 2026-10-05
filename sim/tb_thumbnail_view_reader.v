`timescale 1ns/1ps

// =============================================================================
// 第十三讲回归：thumbnail_view_reader（本工程的“按坐标取像”引擎）
//
// 端到端验证（带一个固定延迟的假 SDRAM 模型）：
//   存储内容约定：bank b 的显示行 y、列 x 存 32 位字 {addr[23:0], 8'h00}，
//   其中 addr = b*307200 + y*640 + x。取像引擎应输出 data[31:8] = addr[23:0]，
//   于是“屏幕像素 -> source_index/source_x/source_y -> SDRAM 地址”全链路可
//   用一条公式逐像素比对。
//
// 检查项：
//   A. 2x2 区域内 thumb_active=1，且每个像素等于其源图坐标对应的存储值
//      （等价于验证布局 + 最近邻 4:1 + 地址折算 + 跨时钟 FIFO 往返 + 行内对齐）；
//   B. 焦点边框像素输出黄色 24'hFFFF00；
//   C. 缩略图区之外（x>=320 或 y>=240）thumb_active=0；
//   D. enable=0（全屏）时全程不产生取像请求，也不显示缩略图；
//   E. 行首一致性校验只在建立阶段触发极少次，之后能自愈并保持稳定。
// =============================================================================
module tb_thumbnail_view_reader;
    localparam integer DISPLAY_WIDTH  = 640;
    localparam integer DISPLAY_HEIGHT = 480;
    localparam integer BANK_WORDS     = 307200;
    localparam integer LATENCY        = 9;      // 假 SDRAM 读延迟（mem 时钟）

    reg pix_clk = 1'b0;
    reg mem_clk = 1'b0;
    always #20 pix_clk = ~pix_clk;   // 25 MHz
    always #5  mem_clk = ~mem_clk;   // 100 MHz

    reg         pix_rst_n = 1'b0;
    reg         mem_rst_n = 1'b0;
    reg         enable = 1'b0;
    reg         frame_start = 1'b0;
    reg  [1:0]  focus_index = 2'd0;
    reg  [3:0]  image_complete = 4'b1111;
    reg  [9:0]  pixel_x = 10'd0;
    reg         in_de = 1'b0;

    wire        thumb_active;
    wire [23:0] pixel_rgb;
    wire        focus_border;
    wire        line_mismatch;
    wire        rd_req;
    wire [20:0] rd_addr;
    wire        rd_valid;
    wire [31:0] rd_data;

    integer errors = 0;
    integer checks = 0;
    integer mismatch_pulses = 0;
    integer req_count = 0;
    integer l, p;

    // ---- 诊断：逐行错误统计（仅在出错时打印，PASS 时无额外输出） ----
    localparam integer DBG = 0;   // 置 1 可打印内部信号，用于定位对齐问题
    integer row_err = 0;
    integer row_first_x = -1;
    reg [23:0] row_first_exp = 24'd0;
    reg [23:0] row_first_got = 24'd0;
    integer dbg_rows_printed = 0;

    // ---------------- 假 SDRAM：固定 LATENCY 拍后返回同拍对齐的数据 ----------------
    reg [20:0] addr_pipe [0:LATENCY-1];
    reg        vld_pipe  [0:LATENCY-1];
    reg        sdr_valid;
    reg [31:0] sdr_dout;
    integer i;

    function [23:0] mem_word;
        input [20:0] a;
        begin
            mem_word = {3'b000, a};
        end
    endfunction

    always @(posedge mem_clk or negedge mem_rst_n) begin
        if (!mem_rst_n) begin
            for (i = 0; i < LATENCY; i = i + 1) begin
                addr_pipe[i] <= 21'd0;
                vld_pipe[i]  <= 1'b0;
            end
            sdr_valid <= 1'b0;
            sdr_dout  <= 32'd0;
        end else begin
            vld_pipe[0]  <= rd_req;
            addr_pipe[0] <= rd_addr;
            for (i = 1; i < LATENCY; i = i + 1) begin
                vld_pipe[i]  <= vld_pipe[i-1];
                addr_pipe[i] <= addr_pipe[i-1];
            end
            sdr_valid <= vld_pipe[LATENCY-1];
            sdr_dout  <= {mem_word(addr_pipe[LATENCY-1]), 8'h00};
        end
    end

    assign rd_valid = sdr_valid;
    assign rd_data  = sdr_dout;

    thumbnail_view_reader #(
        .DISPLAY_WIDTH  (DISPLAY_WIDTH),
        .DISPLAY_HEIGHT (DISPLAY_HEIGHT),
        .ADDR_WIDTH     (21),
        .BANK_WORDS     (BANK_WORDS),
        .THUMB_WIDTH    (160),
        .THUMB_HEIGHT   (120),
        .BORDER_RGB     (24'hff_ff_00)
    ) dut (
        .pix_clk        (pix_clk),
        .pix_rst_n      (pix_rst_n),
        .mem_clk        (mem_clk),
        .mem_rst_n      (mem_rst_n),
        .enable         (enable),
        .mem_enable     (enable),
        .frame_start    (frame_start),
        .focus_index    (focus_index),
        .image_complete (image_complete),
        .pixel_x        (pixel_x),
        .in_de          (in_de),
        .thumb_active   (thumb_active),
        .pixel_rgb      (pixel_rgb),
        .focus_border   (focus_border),
        .line_mismatch  (line_mismatch),
        .rd_req         (rd_req),
        .rd_addr        (rd_addr),
        .rd_valid       (rd_valid),
        .rd_data        (rd_data)
    );

    always @(posedge mem_clk) if (rd_req) req_count = req_count + 1;
    always @(posedge pix_clk) if (line_mismatch) mismatch_pulses = mismatch_pulses + 1;

    // ---------------- 逐像素期望值 ----------------
    task check_pixel;
        input integer yy;
        input integer xx;
        integer idx, wx0, wy0, lx, ly, sx, sy;
        reg [23:0] exp_rgb;
        reg        exp_active;
        reg        exp_border;
        begin
            exp_active = 1'b0;
            exp_border = 1'b0;
            exp_rgb    = 24'd0;
            if (yy < 240 && xx < 320) begin
                exp_active = 1'b1;
                idx = (yy >= 120) ? 2 : 0;
                wx0 = 0;
                wy0 = 0;
                if (xx >= 160) begin idx = idx + 1; wx0 = 160; end
                if (yy >= 120) wy0 = 120;
                lx = xx - wx0;
                ly = yy - wy0;
                sx = lx * 4;
                sy = ly * 4;
                exp_rgb = idx * BANK_WORDS + sy * DISPLAY_WIDTH + sx;
                exp_border = (idx == focus_index) &&
                             (lx < 2 || ly < 2 || lx >= 158 || ly >= 118);
                if (exp_border)
                    exp_rgb = 24'hff_ff_00;
            end

            checks = checks + 1;
            if (thumb_active !== exp_active) begin
                if (errors < 12)
                    $display("FAIL: (%0d,%0d) thumb_active=%b expect %b", xx, yy, thumb_active, exp_active);
                errors = errors + 1;
                row_err = row_err + 1;
            end else if (exp_active && pixel_rgb !== exp_rgb) begin
                if (errors < 12)
                    $display("FAIL: (%0d,%0d) rgb=%06h expect %06h (idx=%0d lx=%0d ly=%0d)",
                             xx, yy, pixel_rgb, exp_rgb, idx, lx, ly);
                errors = errors + 1;
                row_err = row_err + 1;
            end else if (exp_active && focus_border !== exp_border) begin
                if (errors < 12)
                    $display("FAIL: (%0d,%0d) focus_border=%b expect %b", xx, yy, focus_border, exp_border);
                errors = errors + 1;
                row_err = row_err + 1;
            end

            if (row_first_x < 0) begin
                row_first_x   = xx;
                row_first_exp = exp_rgb;
                row_first_got = pixel_rgb;
            end

            if (DBG && (yy <= 1) && (xx < 4 || (xx >= 156 && xx <= 178))) begin
                $display("DBG y=%0d x=%0d exp=%06h got=%06h act=%b | dvalid=%b dout=%08h dpop=%b | push=%b adout=%08h avalid=%b apop=%b | flush=%b under=%b line_y=%0d",
                         yy, xx, exp_rgb, pixel_rgb, exp_active,
                         dut.pix_valid, dut.pix_dout, dut.pix_pop,
                         dut.addr_push, dut.addr_dout, dut.addr_valid, dut.addr_pop,
                         dut.flush_now, dut.under_flag, dut.line_y);
            end
        end
    endtask

    // ---------------- 一帧视频时序 ----------------
    task run_frame;
        input do_check;        // 非 0 时逐像素比对
        integer line, col;
        begin
            in_de = 1'b0;
            pixel_x = 10'd0;
            @(negedge pix_clk); frame_start = 1'b1;
            @(negedge pix_clk); frame_start = 1'b0;
            repeat (8) @(negedge pix_clk);          // 垂直消隐
            for (line = 0; line < DISPLAY_HEIGHT; line = line + 1) begin
                for (col = 0; col < DISPLAY_WIDTH; col = col + 1) begin
                    @(negedge pix_clk);
                    in_de   = 1'b1;
                    pixel_x = col[9:0];
                    #1;
                    if (do_check)
                        check_pixel(line, col);
                end
                @(negedge pix_clk);
                in_de   = 1'b0;
                pixel_x = 10'd0;
                repeat (10) @(negedge pix_clk);      // 行消隐
                if (do_check && row_err > 0 && dbg_rows_printed < 40) begin
                    $display("ROW %0d errors=%0d first_x=%0d exp=%06h got=%06h flush=%b",
                             line, row_err, row_first_x, row_first_exp, row_first_got, line_mismatch);
                    dbg_rows_printed = dbg_rows_printed + 1;
                end
                row_err     = 0;
                row_first_x = -1;
            end
            repeat (12) @(negedge pix_clk);          // 场消隐
        end
    endtask

    integer req_before_fullscreen;

    initial begin
        // ---------------- 复位（仍然全屏模式） ----------------
        repeat (4) @(posedge pix_clk);
        mem_rst_n = 1'b1;
        repeat (4) @(posedge pix_clk);
        pix_rst_n = 1'b1;
        repeat (4) @(posedge pix_clk);

        // ---------------- D. 全屏（enable=0）不得发出任何取像请求 ----------------
        run_frame(1'b0);
        if (thumb_active !== 1'b0) begin
            $display("FAIL: thumb_active high while enable=0");
            errors = errors + 1;
        end
        req_before_fullscreen = req_count;
        if (req_before_fullscreen != 0) begin
            $display("FAIL: enable=0 issued %0d read requests", req_before_fullscreen);
            errors = errors + 1;
        end

        // ---------------- 切到缩略图视图（与顶层一致：frame_start 处生效） ----------------
        enable = 1'b1;
        run_frame(1'b0);       // 第 1 帧：建立阶段
        run_frame(1'b0);       // 第 2 帧：稳定
        mismatch_pulses = 0;
        run_frame(1'b1);       // 第 3 帧：逐像素比对

        if (mismatch_pulses != 0) begin
            $display("FAIL: steady-state line_mismatch pulsed %0d times", mismatch_pulses);
            errors = errors + 1;
        end
        if (req_count == 0) begin
            $display("FAIL: thumbnail mode never issued read requests");
            errors = errors + 1;
        end

        if (errors == 0)
            $display("PASS: tb_thumbnail_view_reader all checks passed (checks=%0d, requests=%0d)",
                     checks, req_count);
        else
            $display("FAIL: tb_thumbnail_view_reader errors=%0d (checks=%0d)", errors, checks);

        $finish;
    end

    initial begin
        #200000000;
        $display("FAIL: tb_thumbnail_view_reader timeout");
        $finish;
    end
endmodule

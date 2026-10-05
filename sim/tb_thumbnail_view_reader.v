`timescale 1ns/1ps

// =============================================================================
// 第十三讲回归：thumbnail_view_reader（128 字连续突发取像引擎）
//
// 假 SDRAM 只接受“连续 128 拍 rd_req + 地址逐拍 +1”的访问模型，并断言：
//   A. 每个突发必须连续发满 128 拍；mem_enable 在突发中途拉低也不能中断；
//   B. 突发起始地址 128 对齐（与第八讲 media_frame_reader 一致）；
//   C. 地址在突发内连续递增；
//   D. enable=0 时全程不发出任何读请求；
//   E. 稳态下逐像素等于 bank/source 映射，焦点边框为黄色。
//
// 存储约定：bank b 的显示行 y、列 x 存 32 位字 {addr[23:0], 8'h00}，
// 其中 addr = b*307200 + y*640 + x。取像引擎输出 data[31:8] = addr[23:0]。
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
    reg         mem_enable = 1'b1;
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
    integer full_screen_violation = 0;
    integer pop_while_blank = 0;
    integer cap_dbg = 0;
    integer we_dbg = 0;
    integer we_total = 0;
    integer full_cycles = 0;

    always @(posedge mem_clk) begin
        if (dut.fifo_we) we_total = we_total + 1;
        if (dut.u_thmb_fifo.full_flag) full_cycles = full_cycles + 1;
    end
    integer l, p;

    integer row_err = 0;
    integer row_first_x = -1;
    reg [23:0] row_first_exp = 24'd0;
    reg [23:0] row_first_got = 24'd0;
    integer dbg_rows_printed = 0;
    localparam integer DBG = 0;

    // ---------------- 假 SDRAM：固定 LATENCY 拍流水 ----------------
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
        .mem_enable     (mem_enable),
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
    always @(posedge pix_clk) begin
        if (line_mismatch) mismatch_pulses = mismatch_pulses + 1;
        if (!enable && thumb_active) full_screen_violation = full_screen_violation + 1;
        if (!in_de && dut.pop) pop_while_blank = pop_while_blank + 1;
    end

    // ---------------- 突发协议断言 ----------------
    integer total_bursts = 0;
    integer burst_errors = 0;
    integer gate_in_burst = 0;
    integer gaps_seen = 0;
    reg        burst_run = 1'b0;
    reg [8:0]  burst_len = 9'd0;
    reg [20:0] burst_last_addr = 21'd0;
    reg [20:0] burst_start_addr = 21'd0;

    always @(posedge mem_clk or negedge mem_rst_n) begin
        if (!mem_rst_n) begin
            burst_run <= 1'b0;
            burst_len <= 9'd0;
            burst_errors <= 0;
            total_bursts <= 0;
            gate_in_burst <= 0;
            gaps_seen <= 0;
        end else begin
            if (!burst_run) begin
                if (rd_req) begin
                    burst_run        <= 1'b1;
                    burst_len        <= 9'd1;
                    burst_last_addr  <= rd_addr;
                    burst_start_addr <= rd_addr;
                    total_bursts     <= total_bursts + 1;
                    if (rd_addr[6:0] != 7'd0) begin
                        $display("FAIL: burst start not 128-aligned: %0d", rd_addr);
                        burst_errors <= burst_errors + 1;
                    end
                end
            end else begin
                if (mem_enable == 1'b0)
                    gate_in_burst <= 1;

                if (!rd_req) begin
                    if (burst_len != 9'd128) begin
                        $display("FAIL: burst interrupted at %0d words (start=%0d)",
                                 burst_len, burst_start_addr);
                        burst_errors <= burst_errors + 1;
                    end
                    burst_run <= 1'b0;
                    gaps_seen <= gaps_seen + 1;
                end else begin
                    if (rd_addr != (burst_last_addr + 21'd1)) begin
                        $display("FAIL: burst address discontinuity: %0d -> %0d",
                                 burst_last_addr, rd_addr);
                        burst_errors <= burst_errors + 1;
                    end
                    burst_last_addr <= rd_addr;
                    burst_len <= burst_len + 9'd1;
                end
            end
        end
    end

    // 可选刷新/忙门控回归：周期性把 mem_enable 拉低 180 个 mem 周期，
    // 必然覆盖某个正在进行的突发，验证“中途不停”。
    initial begin
        if ($test$plusargs("gate")) begin
            mem_enable = 1'b1;
            forever begin
                repeat (300) @(posedge mem_clk);
                mem_enable = 1'b0;
                repeat (180) @(posedge mem_clk);
                mem_enable = 1'b1;
            end
        end else begin
            mem_enable = 1'b1;
        end
    end

    // ---------------- 逐像素期望值 ----------------
    function [23:0] exp_rgb_for;
        input integer yy;
        input integer xx;
        integer idx, wx0, wy0, lx, ly, sx, sy;
        begin
            idx = (yy >= 120) ? 2 : 0;
            wx0 = 0;
            wy0 = 0;
            if (xx >= 160) begin idx = idx + 1; wx0 = 160; end
            if (yy >= 120) wy0 = 120;
            lx = xx - wx0;
            ly = yy - wy0;
            sx = lx * 4;
            sy = ly * 4;
            exp_rgb_for = (idx * BANK_WORDS + sy * DISPLAY_WIDTH + sx) & 24'hffffff;
        end
    endfunction

    function exp_border_for;
        input integer yy;
        input integer xx;
        integer idx, wx0, wy0, lx, ly;
        begin
            idx = (yy >= 120) ? 2 : 0;
            wx0 = 0;
            wy0 = 0;
            if (xx >= 160) begin idx = idx + 1; wx0 = 160; end
            if (yy >= 120) wy0 = 120;
            lx = xx - wx0;
            ly = yy - wy0;
            exp_border_for = (idx == focus_index) &&
                             (lx < 2 || ly < 2 || lx >= 158 || ly >= 118);
        end
    endfunction

    task check_pixel;
        input integer yy;
        input integer xx;
        reg        exp_active;
        reg        exp_border;
        reg [23:0] exp_rgb;
        begin
            exp_active = (yy < 240 && xx < 320);
            exp_border = exp_active ? exp_border_for(yy, xx) : 1'b0;
            exp_rgb    = exp_active ? exp_rgb_for(yy, xx) : 24'd0;
            if (exp_border)
                exp_rgb = 24'hff_ff_00;

            checks = checks + 1;
            if (thumb_active !== exp_active) begin
                if (errors < 12)
                    $display("FAIL: (%0d,%0d) thumb_active=%b expect %b",
                             xx, yy, thumb_active, exp_active);
                errors = errors + 1;
                row_err = row_err + 1;
            end else if (exp_active && pixel_rgb !== exp_rgb) begin
                if (errors < 12)
                    $display("FAIL: (%0d,%0d) rgb=%06h expect %06h",
                             xx, yy, pixel_rgb, exp_rgb);
                errors = errors + 1;
                row_err = row_err + 1;
            end else if (exp_active && focus_border !== exp_border) begin
                if (errors < 12)
                    $display("FAIL: (%0d,%0d) focus_border=%b expect %b",
                             xx, yy, focus_border, exp_border);
                errors = errors + 1;
                row_err = row_err + 1;
            end

            if ((dut.line_y !== yy[11:0]) && (errors < 12)) begin
                $display("FAIL: line_y=%0d expect %0d at pixel (%0d,%0d)",
                         dut.line_y, yy, xx, yy);
                errors = errors + 1;
                row_err = row_err + 1;
            end

            if (row_first_x < 0) begin
                row_first_x   = xx;
                row_first_exp = exp_rgb;
                row_first_got = pixel_rgb;
            end

            if (DBG && (yy <= 8) && (xx == 0 || (yy <= 2 && xx >= 156 && xx < 164))) begin
                $display("DBG y=%0d x=%0d exp=%06h got=%06h act=%b | cnt=%0d s0=%08h s1=%08h pop=%b cons=%b outv=%b rre=%b rempty=%b rvld=%b rdout=%08h | fwe=%b ret=%0d under=%b | burst=%0d task=%b iss=%0d rtn=%0d | wetot=%0d fullcyc=%0d water=%0d",
                         yy, xx, exp_rgb, pixel_rgb, thumb_active,
                         dut.count, dut.slot0, dut.slot1, dut.pop, dut.consume,
                         dut.out_valid, dut.raw_read_en, dut.fifo_empty,
                         dut.fifo_valid, dut.fifo_dout, dut.fifo_we, dut.ret_index_mem,
                         dut.under_flag, dut.burst_idx_mem, dut.task_active_mem,
                         dut.issued_count_mem, dut.returned_count_mem,
                         we_total, full_cycles,
                         ({1'b0, dut.u_thmb_fifo.wptr} - {1'b0, dut.u_thmb_fifo.rptr}));
            end
        end
    endtask

    // ---------------- 一帧视频时序 ----------------
    task run_frame;
        input do_check;
        integer line, col;
        begin
            in_de = 1'b0;
            pixel_x = 10'd0;
            @(negedge pix_clk); frame_start = 1'b1;
            @(negedge pix_clk); frame_start = 1'b0;
            repeat (8) @(posedge pix_clk);          // 垂直消隐

            for (line = 0; line < DISPLAY_HEIGHT; line = line + 1) begin
                for (col = 0; col < DISPLAY_WIDTH; col = col + 1) begin
                    @(negedge pix_clk);
                    in_de   = 1'b1;
                    pixel_x = col[9:0];
                    #1;
                    if (do_check)
                        check_pixel(line, col);
                    @(posedge pix_clk);
                end
                @(negedge pix_clk);
                in_de   = 1'b0;
                pixel_x = 10'd0;
                repeat (10) @(posedge pix_clk);      // 行消隐
                if (do_check && row_err > 0 && dbg_rows_printed < 40) begin
                    $display("ROW %0d errors=%0d first_x=%0d exp=%06h got=%06h mismatch=%b",
                             line, row_err, row_first_x, row_first_exp,
                             row_first_got, line_mismatch);
                    dbg_rows_printed = dbg_rows_printed + 1;
                end
                row_err     = 0;
                row_first_x = -1;
            end
            repeat (12) @(posedge pix_clk);          // 场消隐
        end
    endtask

    integer req_before_fullscreen;

    initial begin
        repeat (4) @(posedge pix_clk);
        mem_rst_n = 1'b1;
        repeat (4) @(posedge pix_clk);
        pix_rst_n = 1'b1;
        repeat (4) @(posedge pix_clk);

        // ---------------- D. 全屏（enable=0）不得发出任何取像请求 ----------------
        run_frame(1'b0);
        req_before_fullscreen = req_count;
        if (req_before_fullscreen != 0) begin
            $display("FAIL: enable=0 issued %0d read requests", req_before_fullscreen);
            errors = errors + 1;
        end

        // ---------------- 切到缩略图视图，先跑两帧建立预取水位 ----------------
        enable = 1'b1;
        run_frame(1'b0);
        run_frame(1'b0);

        mismatch_pulses = 0;
        run_frame(1'b1);

        if (mismatch_pulses != 0) begin
            $display("FAIL: steady-state line_mismatch pulsed %0d times", mismatch_pulses);
            errors = errors + 1;
        end
        if (req_count == 0) begin
            $display("FAIL: thumbnail mode never issued read requests");
            errors = errors + 1;
        end
        if (burst_errors != 0) begin
            $display("FAIL: burst protocol errors=%0d", burst_errors);
            errors = errors + 1;
        end
        if (full_screen_violation != 0) begin
            $display("FAIL: thumb_active high while enable=0 (%0d cycles)", full_screen_violation);
            errors = errors + 1;
        end
        if ($test$plusargs("gate") && (gate_in_burst == 0)) begin
            $display("FAIL: gate mode never overlapped a burst");
            errors = errors + 1;
        end
        if (pop_while_blank != 0) begin
            $display("FAIL: pop asserted while in_de=0 (%0d cycles)", pop_while_blank);
            errors = errors + 1;
        end

        if (errors == 0)
            $display("PASS: tb_thumbnail_view_reader all checks passed (checks=%0d, bursts=%0d, requests=%0d, gaps=%0d, blankpop=%0d)",
                     checks, total_bursts, req_count, gaps_seen, pop_while_blank);
        else
            $display("FAIL: tb_thumbnail_view_reader errors=%0d (checks=%0d, bursts=%0d)",
                     errors, checks, total_bursts);

        $finish;
    end

    initial begin
        #800000000;
        $display("FAIL: tb_thumbnail_view_reader timeout");
        $finish;
    end
endmodule

// =============================================================================
// rfifo_32_32_512 仿真行为模型（仅 TB 使用，不加入 TD 工程）
// 标准模式：re 之后一拍 valid/dout 有效。
// =============================================================================
module rfifo_32_32_512 #(
    parameter DATA_WIDTH_W = 32,
    parameter DATA_WIDTH_R = 32,
    parameter ADDR_WIDTH_W = 9,
    parameter ADDR_WIDTH_R = 9,
    parameter AL_FULL_NUM = 509,
    parameter AL_EMPTY_NUM = 2,
    parameter SHOW_AHEAD_EN = 1'b0,
    parameter OUTREG_EN = "NOREG"
) (
    input  wire                  rst,
    input  wire                  clkw,
    input  wire                  clkr,
    input  wire                  we,
    input  wire [31:0]           di,
    input  wire                  re,
    output wire [31:0]           dout,
    output wire                  valid,
    output wire                  full_flag,
    output wire                  empty_flag,
    output wire                  afull,
    output wire                  aempty,
    output wire [8:0]            wrusedw,
    output wire [8:0]            rdusedw
);
    reg [31:0] mem [0:511];
    reg [31:0] wptr;
    reg [31:0] rptr;
    reg [31:0] wptr_sync1, wptr_sync2;
    reg [31:0] rptr_sync1, rptr_sync2;
    reg [31:0] dout_r;
    reg        valid_r;
    reg        full_r;

    assign dout       = dout_r;
    assign valid      = valid_r;
    assign full_flag  = full_r;
    assign empty_flag = (wptr_sync2 == rptr);
    assign afull      = full_r;
    assign aempty     = (wptr_sync2 == rptr) ||
                        ((wptr_sync2 - rptr) <= AL_EMPTY_NUM);
    assign wrusedw    = wptr - rptr_sync2;
    assign rdusedw    = wptr_sync2 - rptr;

    always @(posedge clkw or posedge rst) begin
        if (rst) begin
            wptr    <= 32'd0;
            full_r  <= 1'b0;
            rptr_sync1 <= 32'd0;
            rptr_sync2 <= 32'd0;
        end else begin
            rptr_sync1 <= rptr;
            rptr_sync2 <= rptr_sync1;
            if (we && !full_r) begin
                mem[wptr[8:0]] <= di;
                wptr <= wptr + 32'd1;
            end
            full_r <= ((wptr - rptr_sync2) >= 32'd509);
        end
    end

    always @(posedge clkr or posedge rst) begin
        if (rst) begin
            rptr     <= 32'd0;
            dout_r   <= 32'd0;
            valid_r  <= 1'b0;
            wptr_sync1 <= 32'd0;
            wptr_sync2 <= 32'd0;
        end else begin
            wptr_sync1 <= wptr;
            wptr_sync2 <= wptr_sync1;
            if (re && !empty_flag) begin
                dout_r <= mem[rptr[8:0]];
                rptr   <= rptr + 32'd1;
            end
            valid_r <= re && !empty_flag;
        end
    end
endmodule

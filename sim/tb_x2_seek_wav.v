`timescale 1ns/1ps
// =============================================================================
// tb_x2_seek_wav —— X2：时基加载 + 扇区内丢弃样本
//
//   1) timebase_48k.load：sample_count 精确等于目标样本，cur_time_ms 误差 <=1；
//   2) wav_stream_player.skip_samples=N：首扇区丢弃前 N 个样本，
//      首个被消费样本号 == N（起点误差 0 样本），LBA 序列从目标扇区开始。
// =============================================================================
module tb_x2_seek_wav;
    integer errors = 0;
    task chk; input cond; input [255:0] msg;
        begin if (!cond) begin errors = errors + 1; $display("FAIL %0s", msg); end end
    endtask

    reg clk = 0;    always #5  clk  = ~clk;   // 100 MHz
    reg pix = 0;    always #20 pix  = ~pix;   // 25 MHz

    // ---------------- 1) timebase_48k ----------------
    reg rst_n = 0, tick = 0, load = 0, run = 0;
    reg [31:0] load_sample = 32'd0;
    wire [31:0] samp_cnt, ms;
    wire [5:0]  sub;
    timebase_48k u_tb (
        .clk(clk), .rst_n(rst_n), .sample_tick(tick), .running(run),
        .restart(1'b0), .load(load), .load_sample(load_sample),
        .sample_count(samp_cnt), .cur_time_ms(ms), .sub_sample(sub)
    );

    // ---------------- 2) wav_stream_player ----------------
    parameter SKIP = 5;
    reg         wr_rst = 0, play = 0;
    reg  [31:0] start_lba = 32'd200, total_sec = 32'd4;
    reg  [31:0] valid_samples = 32'd1000;
    reg  [7:0]  skip_samples = SKIP[7:0];
    reg  [31:0] sample_base = 32'd5;
    wire        sd_req, sd_busy, sd_valid, sd_done;
    wire [31:0] sd_lba;
    wire [7:0]  sd_byte;
    wire [7:0]  sd_error = 8'd0;
    wire [8:0]  sd_idx;
    wire signed [15:0] sample_out;
    wire        sample_valid;
    wire        sample_ready = 1'b1;
    wire [31:0] sample_counter;
    wire        stream_active, stream_end, reader_idle, consumed, buf_low, underrun;

    // 48 kHz 消费节拍（25 MHz / 520 ≈ 48.08 kHz）
    reg [9:0] tick_div = 0;
    reg       tick_wav = 0;
    always @(posedge pix) begin
        tick_wav <= 1'b0;
        if (tick_div == 10'd519) begin tick_div <= 0; tick_wav <= 1'b1; end
        else tick_div <= tick_div + 1'b1;
    end

    wav_stream_player #(.ADDR_WIDTH(12), .SAMPLES_PER_SECTOR(256)) u_wav (
        .wr_clk(clk), .wr_rst_n(wr_rst), .play_enable(play),
        .start_lba(start_lba), .total_sectors(total_sec),
        .valid_samples(valid_samples),
        .skip_samples(skip_samples),
        .sd_req(sd_req), .sd_lba(sd_lba), .sd_busy(sd_busy),
        .sd_valid(sd_valid), .sd_byte(sd_byte), .sd_byte_index(sd_idx),
        .sd_done(sd_done), .sd_error(sd_error),
        .rd_clk(pix), .rd_rst_n(wr_rst), .sample_tick(tick_wav),
        .sample_out(sample_out), .sample_valid(sample_valid), .sample_ready(sample_ready),
        .sample_counter(sample_counter), .stream_active(stream_active),
        .stream_end(stream_end), .reader_idle(reader_idle),
        .sample_consumed(consumed), .buffer_low(buf_low),
        .sample_base(sample_base), .underrun_pulse(underrun)
    );

    // SD 扇区模型：第 s 扇区第 k 个样本 = 全局样本号 (s*256+k)[15:0]
    reg        busy = 0, valid = 0, done = 0;
    reg [8:0]  bidx = 0;
    reg [31:0] cur = 0;
    reg [2:0]  st = 0;
    assign sd_busy  = busy;
    assign sd_valid = (st == 3'd2);
    assign sd_done  = (st == 3'd3);
    assign sd_idx   = bidx;
    wire [15:0] sd_sample = cur[15:0];
    assign sd_byte = bidx[0] ? sd_sample[15:8] : sd_sample[7:0];

    always @(posedge clk or negedge wr_rst) begin
        if (!wr_rst) begin busy<=0; bidx<=0; st<=0; cur<=0; end
        else begin
            case (st)
            3'd0: if (sd_req && !busy) begin busy<=1; st<=1; end
            // sd_lba 在 WS_REQ 那一拍才被写侧寄存，故延后一拍再取
            3'd1: begin cur<=(sd_lba - 32'd200)*32'd256; bidx<=0; st<=2; end
            3'd2: begin
                bidx <= bidx + 1'b1;
                if (bidx[0]) cur <= cur + 1'b1;
                if (bidx == 9'd511) st <= 3;
            end
            3'd3: begin busy<=0; st<=0; end
            default: st<=0;
            endcase
        end
    end

    // 采样收集
    integer idx = 0;
    integer bad = 0;
    reg [31:0] first_count = 32'hFFFFFFFF;
    always @(posedge pix) begin
        if (wr_rst && consumed) begin
            if (idx == 0) first_count <= sample_counter;
            if (idx < 300) begin
                // 读数据比消费指针晚一拍：本次消费看到的是上一个样本
                if ((idx > 0) && (sample_out[15:0] !== (SKIP + idx - 1))) begin
                    bad <= bad + 1;
                    if (bad < 4)
                        $display("  mismatch idx=%0d got=%0d want=%0d",
                                 idx, $signed(sample_out), SKIP + idx - 1);
                end
            end
            idx <= idx + 1;
        end
    end

    // ---------------- 主流程 ----------------
    integer i;
    initial begin
        repeat (4) @(negedge clk);
        rst_n = 1; wr_rst = 1;

        // --- timebase 加载 ---
        load_sample = 32'd12345; load = 1; @(negedge clk); load = 0;
        repeat (2) @(negedge clk);
        chk(samp_cnt == 32'd12345, "timebase load sample_count exact");
        chk(ms == 32'd257, "timebase load ms ~= 12345/48");
        run = 1;
        for (i = 0; i < 48; i = i + 1) begin
            @(negedge clk); tick = 1; @(negedge clk); tick = 0;
        end
        chk(samp_cnt == 32'd12393, "timebase advances from loaded base");
        chk(ms == 32'd258, "timebase ms carries after +48 samples");
        run = 0; tick = 0;

        // --- wav skip_samples ---
        play = 1;
        repeat (600000) @(negedge pix);
        play = 0;
        repeat (20) @(negedge pix);
        chk(idx == 1000, "wav stops at real valid_samples (padding truncated)");
        chk(bad == 0, "first sample after skip has value == skip (0 err)");
        chk(first_count == 32'd5, "sample_counter starts at seek target");

        if (errors == 0) $display("TEST_PASS x2_seek_wav timebase load + sector skip");
        else $display("TEST_FAIL x2_seek_wav errors=%0d", errors);
        $finish;
    end
    initial begin #80000000; $fatal(1, "FAIL watchdog x2_seek_wav"); end
endmodule

`timescale 1ns/1ps
// 第十一讲 WAV 流式播放器仿真：
// 覆盖小端字节组装、256样本预填充、残样排空以及流结束握手。
module tb_wav_stream_player;
    reg         wr_clk = 1'b0;
    reg         rd_clk = 1'b0;
    reg         wr_rst_n = 1'b0;
    reg         rd_rst_n = 1'b0;

    reg         play_enable = 1'b0;
    reg  [31:0] start_lba = 32'd100;
    reg  [31:0] total_sectors = 32'd1;

    wire        sd_req;
    wire [31:0] sd_lba;
    reg         sd_busy = 1'b0;
    reg         sd_valid = 1'b0;
    reg  [7:0]  sd_byte = 8'd0;
    reg  [8:0]  sd_byte_index = 9'd0;
    reg         sd_done = 1'b0;
    reg  [7:0]  sd_error = 8'd0;

    reg         sample_tick = 1'b0;
    wire signed [15:0] sample_out;
    wire        sample_valid;
    wire        sample_ready = 1'b1;
    wire [31:0] sample_counter;
    wire        stream_active;
    wire        stream_end;
    wire        buffer_low;

    reg [7:0]   tx_bytes [0:511];
    reg signed [15:0] expected_samples [0:255];
    integer     i;
    integer     tx_index = 0;
    integer     rd_cycle = 0;
    integer     samples_seen = 0;
    integer     errors = 0;
    reg         feeding = 1'b0;
    reg         stream_active_seen = 1'b0;
    reg         stream_end_seen = 1'b0;

    wav_stream_player #(
        .ADDR_WIDTH        (12),
        .SAMPLES_PER_SECTOR(256)
    ) dut (
        .wr_clk            (wr_clk),
        .wr_rst_n          (wr_rst_n),
        .play_enable       (play_enable),
        .start_lba         (start_lba),
        .total_sectors     (total_sectors),
        .sd_req            (sd_req),
        .sd_lba            (sd_lba),
        .sd_busy           (sd_busy),
        .sd_valid          (sd_valid),
        .sd_byte           (sd_byte),
        .sd_byte_index     (sd_byte_index),
        .sd_done           (sd_done),
        .sd_error          (sd_error),
        .rd_clk            (rd_clk),
        .rd_rst_n          (rd_rst_n),
        .sample_tick       (sample_tick),
        .sample_out        (sample_out),
        .sample_valid      (sample_valid),
        .sample_ready      (sample_ready),
        .sample_counter    (sample_counter),
        .stream_active     (stream_active),
        .stream_end        (stream_end),
        .buffer_low        (buffer_low)
    );

    always #5 wr_clk = ~wr_clk;   // 100 MHz
    always #20 rd_clk = ~rd_clk;  // 25 MHz

    // 测试用扇区数据：16bit signed little-endian。
    initial begin
        for (i = 0; i < 256; i = i + 1) begin
            expected_samples[i] = (i < 128) ? i : -(i - 128);
            tx_bytes[i*2]   = expected_samples[i][7:0];
            tx_bytes[i*2+1] = expected_samples[i][15:8];
        end
    end

    // SD 扇区模型：收到请求后按字节产生 sd_valid，最后拉高一拍 sd_done。
    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            feeding     <= 1'b0;
            tx_index    <= 0;
            sd_busy     <= 1'b0;
            sd_valid    <= 1'b0;
            sd_done     <= 1'b0;
            sd_byte     <= 8'd0;
            sd_byte_index <= 9'd0;
        end else begin
            sd_valid <= 1'b0;
            sd_done  <= 1'b0;

            if (!feeding && sd_req && !sd_busy) begin
                feeding  <= 1'b1;
                tx_index <= 0;
                sd_busy  <= 1'b1;
            end else if (feeding) begin
                if (tx_index < 512) begin
                    sd_byte       <= tx_bytes[tx_index];
                    sd_byte_index <= tx_index[8:0];
                    sd_valid      <= 1'b1;
                    tx_index      <= tx_index + 1;
                end else begin
                    feeding  <= 1'b0;
                    sd_busy  <= 1'b0;
                    sd_done  <= 1'b1;
                end
            end
        end
    end

    // 读侧每 8 个 rd_clk 产生一个样本节拍；仅用于验证流水，不模拟 48kHz。
    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            rd_cycle    <= 0;
            sample_tick <= 1'b0;
        end else begin
            sample_tick <= (rd_cycle == 0);
            rd_cycle    <= (rd_cycle == 7) ? 0 : rd_cycle + 1;
        end
    end

    // 在 rd_clk 下降沿采样已稳定的非阻塞赋值结果。WAV 播放器在下溢/预填充
    // 阶段也会给出 valid=1 的静音样本，这里只在 sample_counter 前进时核对
    // 真实PCM样本，避免把预填充静音误判为数据。
    always @(negedge rd_clk) begin
        if (stream_active)
            stream_active_seen <= 1'b1;
        if (stream_end)
            stream_end_seen <= 1'b1;

        if (sample_valid && sample_ready &&
            (sample_counter > samples_seen) && (sample_counter <= 256)) begin
            if (sample_out !== expected_samples[sample_counter - 1]) begin
                $display("FAIL sample[%0d]=%0d expected=%0d",
                         sample_counter - 1, sample_out,
                         expected_samples[sample_counter - 1]);
                errors = errors + 1;
            end
            samples_seen = sample_counter;
        end
    end

    initial begin
        repeat (8) @(posedge wr_clk);
        wr_rst_n = 1'b1;
        repeat (8) @(posedge rd_clk);
        rd_rst_n = 1'b1;
        repeat (4) @(posedge wr_clk);

        play_enable = 1'b1;

        wait (samples_seen == 256);
        repeat (16) @(posedge rd_clk);

        if (!stream_active_seen) begin
            $display("FAIL stream_active never asserted");
            errors = errors + 1;
        end
        if (!stream_end_seen || stream_active) begin
            $display("FAIL stream end handshake end=%b active=%b",
                     stream_end_seen, stream_active);
            errors = errors + 1;
        end
        if (sample_counter != 32'd256) begin
            $display("FAIL sample_counter=%0d expected=256", sample_counter);
            errors = errors + 1;
        end

        if (errors == 0)
            $display("PASS: wav stream player little-endian/prefill/drain/end");
        else
            $display("FAIL: wav stream player errors=%0d", errors);
        $finish;
    end

    initial begin
        #10_000_000;
        $display("FAIL: wav stream player timeout");
        $finish;
    end
endmodule

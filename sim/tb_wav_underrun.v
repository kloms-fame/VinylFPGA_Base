`timescale 1ns/1ps
// S7-01B：WAV 播放器欠载脉冲定向验证。
// 只喂一个扇区（256 样本），随后停住数据源，读侧把缓冲排空后应打出
// underrun_pulse；且在正常完整喂数路径上不应误报。
module tb_wav_underrun;
    reg         wr_clk = 1'b0;
    reg         rd_clk = 1'b0;
    reg         wr_rst_n = 1'b0;
    reg         rd_rst_n = 1'b0;
    reg         play_enable = 1'b0;
    reg  [31:0] start_lba = 32'd100;
    reg  [31:0] total_sectors = 32'd2;   // 两个扇区：只喂第一个，制造欠载

    wire        sd_req;
    wire [31:0] sd_lba;
    reg         sd_busy = 1'b0;
    reg         sd_valid = 1'b0;
    reg  [7:0]  sd_byte = 8'd0;
    reg  [8:0]  sd_byte_index = 9'd0;
    reg         sd_done = 1'b0;
    reg  [7:0]  sd_error = 8'd0;

    reg         sample_tick = 1'b0;
    wire        sample_valid;
    wire        sample_ready = 1'b1;
    wire [31:0] sample_counter;
    wire        stream_active;
    wire        buffer_low;
    wire        underrun_pulse;

    reg  [7:0]  tx_bytes [0:511];
    integer     i;
    integer     j;
    integer     tx_index = 0;
    integer     rd_cycle = 0;
    reg         feeding = 1'b0;
    reg         fed_first = 1'b0;
    integer     errors = 0;

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
        .sample_out        (),
        .sample_valid      (sample_valid),
        .sample_ready      (sample_ready),
        .sample_counter    (sample_counter),
        .stream_active     (stream_active),
        .stream_end        (),
        .buffer_low        (buffer_low),
        .underrun_pulse    (underrun_pulse)
    );

    always #5 wr_clk = ~wr_clk;    // 100 MHz
    always #20 rd_clk = ~rd_clk;   // 25 MHz

    initial begin
        for (i = 0; i < 256; i = i + 1) begin
            tx_bytes[i*2]   = (i & 8'hFF);
            tx_bytes[i*2+1] = 8'h00;
        end
    end

    // 只喂第一个扇区，第二个扇区请求后停住数据源（不产生 sd_valid/done）
    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            feeding   <= 1'b0;
            fed_first <= 1'b0;
            tx_index  <= 0;
            sd_busy   <= 1'b0;
            sd_valid  <= 1'b0;
            sd_done   <= 1'b0;
            sd_byte   <= 8'd0;
            sd_byte_index <= 9'd0;
        end else begin
            sd_valid <= 1'b0;
            sd_done  <= 1'b0;

            if (!feeding && sd_req && !sd_busy && !fed_first) begin
                feeding   <= 1'b1;
                fed_first <= 1'b1;
                tx_index  <= 0;
                sd_busy   <= 1'b1;
            end else if (feeding) begin
                if (tx_index < 512) begin
                    sd_byte       <= tx_bytes[tx_index];
                    sd_byte_index <= tx_index[8:0];
                    sd_valid      <= 1'b1;
                    tx_index      <= tx_index + 1;
                end else begin
                    feeding <= 1'b0;
                    sd_busy <= 1'b0;
                    sd_done <= 1'b1;
                end
            end
        end
    end

    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            rd_cycle    <= 0;
            sample_tick <= 1'b0;
        end else begin
            sample_tick <= (rd_cycle == 0);
            rd_cycle    <= (rd_cycle == 1) ? 0 : rd_cycle + 1;  // 每 2 个 rd_clk 一个样本，加快排空
        end
    end

    reg underrun_seen = 1'b0;
    always @(posedge rd_clk)
        if (underrun_pulse) underrun_seen <= 1'b1;

    initial begin
        repeat (8) @(posedge wr_clk);
        wr_rst_n = 1'b1;
        repeat (8) @(posedge rd_clk);
        rd_rst_n = 1'b1;
        repeat (4) @(posedge wr_clk);

        play_enable = 1'b1;

        // 数据源只喂第一个扇区后停住；读侧把缓冲消耗到不足一个扇区
        // （欠载阈值）后应打出 underrun_pulse。用有限拍等待避免悬挂。
        for (j = 0; j < 2000 && !underrun_seen; j = j + 1)
            @(posedge rd_clk);

        if (!underrun_seen) begin
            $display("FAIL underrun_pulse never asserted (sample_counter=%0d)", sample_counter);
            errors = errors + 1;
        end else begin
            $display("PASS underrun_pulse asserted after drain (sample_counter=%0d)", sample_counter);
        end

        if (errors == 0)
            $display("TEST_PASS wav_underrun");
        else
            $display("TEST_FAIL wav_underrun errors=%0d", errors);
        $finish;
    end

    initial begin
        #20_000_000;
        $display("TEST_FAIL wav_underrun watchdog timeout");
        $finish;
    end
endmodule

`timescale 1ns/1ps
// Multi-sector flow-control regression for wav_stream_player.
//
// The original single-sector test proves byte assembly, prefill, drain, and
// end handshake. This test adds 12 back-to-back sectors so the write side is
// forced into WS_WAIT by the BRAM high-water mark. It verifies that:
//   1. the player really pauses sector requests at high water;
//   2. all 3072 samples are emitted in the correct order;
//   3. no sample is overwritten when the circular pointer wraps;
//   4. stream_active falls only after the final sample drains.
module tb_wav_stream_player_flow;
    localparam integer SECTORS = 12;
    localparam integer SAMPLES = SECTORS * 256;
    localparam integer ADDR_WIDTH = 12;

    reg wr_clk = 0;
    reg rd_clk = 0;
    reg wr_rst_n = 0;
    reg rd_rst_n = 0;

    reg         play_enable = 0;
    reg  [31:0] start_lba = 32'd1000;
    reg  [31:0] total_sectors = SECTORS;

    wire        sd_req;
    wire [31:0] sd_lba;
    reg         sd_busy = 0;
    reg         sd_valid = 0;
    reg  [7:0]  sd_byte = 0;
    reg  [8:0]  sd_byte_index = 0;
    reg         sd_done = 0;
    reg  [7:0]  sd_error = 0;

    reg         sample_tick = 0;
    wire signed [15:0] sample_out;
    wire        sample_valid;
    wire        sample_ready = 1'b1;
    wire [31:0] sample_counter;
    wire        stream_active;
    wire        stream_end;
    wire        buffer_low;

    integer i;
    integer tx_index = 0;
    integer tx_sector = 0;
    integer tx_sector_next = 0;
    integer rd_cycle = 0;
    integer errors = 0;
    integer errors_printed = 0;
    integer samples_seen = 0;
    integer wait_cycles = 0;
    integer max_wait_cycles = 0;
    reg feeding = 0;
    reg signed [15:0] tx_sample;
    reg wait_seen = 0;
    reg end_seen = 0;
    reg active_seen = 0;

    wav_stream_player #(
        .ADDR_WIDTH        (ADDR_WIDTH),
        .SAMPLES_PER_SECTOR(256)
    ) dut (
        .wr_clk            (wr_clk),
        .wr_rst_n          (wr_rst_n),
        .play_enable       (play_enable),
        .start_lba         (start_lba),
        .total_sectors     (total_sectors),
        .valid_samples     (SAMPLES),
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
        .buffer_low        (buffer_low),
        .skip_samples      (8'd0),
        .sample_base       (32'd0)
    );

    always #5 wr_clk = ~wr_clk;   // 100 MHz
    always #20 rd_clk = ~rd_clk;  // 25 MHz

    function signed [15:0] sample_value;
        input integer sector;
        input integer index;
        begin
            sample_value = ((sector * 251) + (index * 7)) & 16'hffff;
        end
    endfunction

    // SD sector model. The requested LBA selects a deterministic sector
    // pattern so a circular-buffer overwrite becomes a sample mismatch.
    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            feeding       <= 0;
            tx_index      <= 0;
            tx_sector     <= 0;
            tx_sector_next <= 0;
            sd_busy       <= 0;
            sd_valid      <= 0;
            sd_done       <= 0;
            sd_byte       <= 0;
            sd_byte_index <= 0;
        end else begin
            sd_valid <= 0;
            sd_done  <= 0;

            if (!feeding && sd_req && !sd_busy) begin
                feeding   <= 1;
                tx_index  <= 0;
                tx_sector <= tx_sector_next;
                sd_busy   <= 1;
            end else if (feeding) begin
                if (tx_index < 512) begin
                    tx_sample = sample_value(tx_sector, tx_index >> 1);
                    sd_byte       <= (tx_index & 1) ?
                                     tx_sample[15:8] : tx_sample[7:0];
                    sd_byte_index <= tx_index[8:0];
                    sd_valid      <= 1;
                    tx_index      <= tx_index + 1;
                end else begin
                    feeding  <= 0;
                    sd_busy  <= 0;
                    sd_done  <= 1;
                    tx_sector_next <= tx_sector_next + 1;
                end
            end
        end
    end

    // Faster than the real 48 kHz tick, but still 256x slower than a
    // sector burst. This guarantees the write side hits the high-water mark.
    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            rd_cycle    <= 0;
            sample_tick <= 0;
        end else begin
            sample_tick <= (rd_cycle == 0);
            rd_cycle    <= (rd_cycle == 7) ? 0 : rd_cycle + 1;
        end
    end

    // Observe the actual write-side state so a broken flow-control path
    // cannot silently pass just because the test bench stopped requesting.
    always @(posedge wr_clk) begin
        if (wr_rst_n) begin
            if (dut.wstate == 3'd5) begin
                wait_seen   <= 1;
                wait_cycles <= wait_cycles + 1;
                if ((wait_cycles + 1) > max_wait_cycles)
                    max_wait_cycles <= wait_cycles + 1;
            end else begin
                wait_cycles <= 0;
            end
        end
    end

    always @(negedge rd_clk) begin
        if (stream_active)
            active_seen <= 1;
        if (stream_end)
            end_seen <= 1;

        if (sample_valid && sample_ready &&
            (sample_counter > samples_seen) && (sample_counter <= SAMPLES)) begin
            if (sample_out !== sample_value((sample_counter - 1) / 256,
                                            (sample_counter - 1) % 256)) begin
                if (errors_printed < 10) begin
                    $display("FAIL sample[%0d]=%0d expected=%0d",
                             sample_counter - 1, sample_out,
                             sample_value((sample_counter - 1) / 256,
                                          (sample_counter - 1) % 256));
                    errors_printed = errors_printed + 1;
                end
                errors = errors + 1;
            end
            samples_seen = sample_counter;
        end
    end

    initial begin
        repeat (8) @(posedge wr_clk);
        wr_rst_n = 1;
        repeat (8) @(posedge rd_clk);
        rd_rst_n = 1;
        repeat (4) @(posedge wr_clk);

        play_enable = 1;

        wait (samples_seen == SAMPLES);
        repeat (32) @(posedge rd_clk);

        if (!active_seen) begin
            $display("FAIL stream_active never asserted");
            errors = errors + 1;
        end
        if (!wait_seen) begin
            $display("FAIL high-water WS_WAIT was never observed");
            errors = errors + 1;
        end
        if (!end_seen || stream_active) begin
            $display("FAIL end handshake end=%b active=%b", end_seen, stream_active);
            errors = errors + 1;
        end
        if (sample_counter != SAMPLES) begin
            $display("FAIL sample_counter=%0d expected=%0d", sample_counter, SAMPLES);
            errors = errors + 1;
        end

        if (errors == 0)
            $display("PASS: wav stream multi-sector high-water/order/drain");
        else
            $display("FAIL: wav stream multi-sector errors=%0d", errors);
        $finish;
    end

    initial begin
        #200_000_000;
        $display("FAIL: wav stream multi-sector timeout");
        $finish;
    end
endmodule

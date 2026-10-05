`timescale 1ns/1ps
// Regression for the read burst gap that gives the SDRAM controller
// deterministic idle cycles for auto-refresh.
//
// The official frame_fifo_read state machine already leaves a natural gap
// because rd_delay waits 10 cycles after the last App_rd_en, then the FSM
// takes several cycles to start the next burst. This test pins that natural
// gap to the tutorial's BURST_GAP_CYCLES=12 requirement.
module tb_frame_fifo_read_gap;
    // Top-level frame_read_write uses its default BURST_SIZE=256 for the
    // read path, so the regression matches that operating point.
    localparam integer BURST_SIZE       = 256;
    localparam integer BURST_GAP_CYCLES = 12;
    localparam integer TOTAL_WORDS      = 1024;

    reg         mem_clk = 1'b0;
    reg         rst = 1'b1;
    reg         read_req = 1'b0;
    reg  [20:0] read_len = TOTAL_WORDS;
    reg  [20:0] read_addr_0 = 21'd0;
    reg  [20:0] read_addr_1 = 21'd307200;
    reg  [20:0] read_addr_2 = 21'd614400;
    reg  [20:0] read_addr_3 = 21'd921600;
    reg  [1:0]  read_addr_index = 2'd1;

    wire        read_req_ack;
    wire        read_finish;
    wire        App_rd_en;
    wire [20:0] App_rd_addr;
    wire        fifo_aclr;

    integer     rd_pulses = 0;
    integer     burst_count = 0;
    integer     idle_cycles = 0;
    integer     min_gap = 999;
    integer     errors = 0;
    reg         saw_finish = 1'b0;
    reg         rd_en_q = 1'b0;

    always #4 mem_clk = ~mem_clk;

    frame_fifo_read #(
        .MEM_DATA_BITS    (32),
        .ADDR_BITS        (21),
        .BURST_BITS       (9),
        .FIFO_DEPTH       (512),
        .BURST_SIZE       (BURST_SIZE)
    ) dut (
        .rst               (rst),
        .mem_clk           (mem_clk),
        .Sdr_init_done     (1'b1),
        .Sdr_init_ref_vld  (1'b0),
        .Sdr_busy          (1'b0),
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
        .wrusedw           (10'd0)
    );

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

    initial begin
        repeat (4) @(posedge mem_clk);
        rst = 1'b0;
        read_req = 1'b1;
        while (!read_req_ack) @(posedge mem_clk);
        @(negedge mem_clk);
        read_req = 1'b0;
        while (!saw_finish) @(posedge mem_clk);
        repeat (4) @(posedge mem_clk);

        if (rd_pulses != TOTAL_WORDS) begin
            $display("FAIL: frame_fifo_read rd_pulses=%0d expected=%0d", rd_pulses, TOTAL_WORDS);
            errors = errors + 1;
        end
        if (burst_count != (TOTAL_WORDS / BURST_SIZE)) begin
            $display("FAIL: frame_fifo_read burst_count=%0d expected=%0d", burst_count, TOTAL_WORDS / BURST_SIZE);
            errors = errors + 1;
        end
        if (!saw_finish) begin
            $display("FAIL: frame_fifo_read read_finish not observed");
            errors = errors + 1;
        end
        if (!(App_rd_addr == (read_addr_1 + TOTAL_WORDS))) begin
            $display("FAIL: frame_fifo_read final address mismatch");
            errors = errors + 1;
        end
        if (errors == 0)
            $display("PASS: frame_fifo_read burst gap min=%0d cycles", min_gap);
        else
            $display("FAIL: frame_fifo_read errors=%0d", errors);
        $finish;
    end
endmodule

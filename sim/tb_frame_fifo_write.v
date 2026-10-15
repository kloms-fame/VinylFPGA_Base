`timescale 1ns/1ps
// =============================================================================
// frame_fifo_write burst regression
//
// Validates that the registered FIFO-level burst decision still emits exactly
// one 128-word burst, keeps a continuous write address, and reaches write_finish.
// =============================================================================
module tb_frame_fifo_write;
    reg         mem_clk = 1'b0;
    reg         rst = 1'b1;
    reg         write_req = 1'b0;
    reg         sdr_init_done = 1'b0;
    reg         sdr_init_ref_vld = 1'b0;
    reg         sdr_busy = 1'b0;
    reg  [20:0] write_len = 21'd128;
    reg  [20:0] write_addr_0 = 21'd0;
    reg  [20:0] write_addr_1 = 21'd307200;
    reg  [20:0] write_addr_2 = 21'd614400;
    reg  [20:0] write_addr_3 = 21'd921600;
    reg  [1:0]  write_addr_index = 2'd0;

    wire        write_req_ack;
    wire        write_finish;
    wire        App_wr_en;
    wire [20:0] App_wr_addr;
    wire        fifo_aclr;

    integer     wr_count = 0;
    integer     errors = 0;
    reg         saw_finish = 1'b0;
    reg  [20:0] last_addr = 21'd0;
    reg         first_addr_seen = 1'b0;

    always #4 mem_clk = ~mem_clk;

    frame_fifo_write #(
        .MEM_DATA_BITS (32),
        .ADDR_BITS     (21),
        .BURST_BITS    (9),
        .BURST_SIZE    (128),
        .WRITE_V_FLIP  (0),
        .FRAME_WIDTH   (640),
        .FRAME_HEIGHT  (480)
    ) dut (
        .write_hold(1'b0),.write_cancel(1'b0),
        .rst                 (rst),
        .mem_clk             (mem_clk),
        .Sdr_init_done       (sdr_init_done),
        .Sdr_init_ref_vld    (sdr_init_ref_vld),
        .Sdr_busy            (sdr_busy),
        .App_rd_busy         (1'b0),
        .O_wr_busy           (),
        .App_wr_en           (App_wr_en),
        .App_wr_addr         (App_wr_addr),
        .write_req           (write_req),
        .write_req_ack       (write_req_ack),
        .write_finish        (write_finish),
        .write_addr_0        (write_addr_0),
        .write_addr_1        (write_addr_1),
        .write_addr_2        (write_addr_2),
        .write_addr_3        (write_addr_3),
        .write_addr_index    (write_addr_index),
        .write_len           (write_len),
        .fifo_aclr           (fifo_aclr),
        .rdusedw             (10'd200)
    );

    always @(posedge mem_clk) begin
        if (App_wr_en) begin
            if (!first_addr_seen) begin
                first_addr_seen <= 1'b1;
                last_addr       <= App_wr_addr;
            end else if (App_wr_addr != (last_addr + 21'd1)) begin
                errors = errors + 1;
            end else begin
                last_addr <= App_wr_addr;
            end
            wr_count <= wr_count + 1;
        end
        if (write_finish)
            saw_finish <= 1'b1;
    end

    initial begin
        repeat (4) @(posedge mem_clk);
        rst = 1'b0;
        write_req = 1'b1;
        repeat (8) @(posedge mem_clk);
        if (write_req_ack || App_wr_en) begin
            $display("FAIL: write accepted before SDRAM initialization");
            errors = errors + 1;
        end
        sdr_init_done = 1'b1;
        while (!write_req_ack) @(posedge mem_clk);
        @(negedge mem_clk);
        write_req = 1'b0;
        sdr_busy = 1'b1;
        repeat (8) @(posedge mem_clk);
        if (App_wr_en || wr_count != 0) begin
            $display("FAIL: FIFO dequeued while SDRAM controller busy");
            errors = errors + 1;
        end
        sdr_busy = 1'b0;
        sdr_init_ref_vld = 1'b1;
        repeat (8) @(posedge mem_clk);
        if (App_wr_en || wr_count != 0) begin
            $display("FAIL: FIFO dequeued during SDRAM refresh window");
            errors = errors + 1;
        end
        sdr_init_ref_vld = 1'b0;
        while (!saw_finish) @(posedge mem_clk);
        repeat (4) @(posedge mem_clk);

        if (wr_count != 128) begin
            $display("FAIL: frame_fifo_write wr_count=%0d expected=128", wr_count);
            errors = errors + 1;
        end
        if (!saw_finish) begin
            $display("FAIL: frame_fifo_write write_finish not observed");
            errors = errors + 1;
        end
        if (!first_addr_seen) begin
            $display("FAIL: frame_fifo_write no App_wr_en pulses");
            errors = errors + 1;
        end
        if (errors == 0)
            $display("PASS: frame_fifo_write init/busy/refresh gating and exact dequeue");
        else
            $display("FAIL: frame_fifo_write errors=%0d", errors);
        $finish;
    end
endmodule

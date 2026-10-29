`ifndef VINYL_AUDIO_SDRAM_DMA_V
`define VINYL_AUDIO_SDRAM_DMA_V
`timescale 1ns/1ps
// The request payload is a bundled-data mailbox: keep sector and toggle stable
// until the matching acknowledgement returns. No command backpressure exists on
// this SDRAM user port: acquire ownership before issuing a contiguous chunk.
module audio_sdram_dma #(
    parameter integer BURST_WORDS = 32,
    parameter integer DRAIN_CYCLES = 16,
    parameter integer YIELD_CYCLES = 16,
    parameter integer WATCHDOG_BITS = 18
)(
    input mem_clk, rst_n,
    input write_request_toggle,
    input [9:0] write_sector,
    output reg write_ack_toggle = 1'b0,
    output reg [7:0] write_error = 8'd0,
    input read_request_toggle,
    input [9:0] read_sector,
    output reg read_ack_toggle = 1'b0,
    output reg [7:0] read_error = 8'd0,
    output stage_en, stage_we,
    output [9:0] stage_addr,
    output [7:0] stage_din,
    input [7:0] stage_dout,
    input video_read_busy, video_write_busy, controller_busy, refresh_active,
    input mem_read_valid,
    input [31:0] mem_read_data,
    output access_lock, read_owner,
    output mem_wr_en,
    output [20:0] mem_wr_addr,
    output [31:0] mem_wr_data,
    output [3:0] mem_wr_mask,
    output mem_rd_en,
    output [20:0] mem_rd_addr
);
    localparam [3:0] S_IDLE=0, S_LOCK=1, S_WRITE=2, S_READ=3,
                     S_WRITE_DRAIN=4, S_READ_DRAIN=5, S_YIELD=6,
                     S_DONE=7, S_FAIL=8;
    localparam integer COUNT_BITS = (BURST_WORDS < 2) ? 1 : $clog2(BURST_WORDS+1);
    localparam integer QUIET_BITS = (DRAIN_CYCLES < 2) ? 1 : $clog2(DRAIN_CYCLES+1);
    localparam integer YIELD_BITS = (YIELD_CYCLES < 2) ? 1 : $clog2(YIELD_CYCLES+1);
    reg write_sync0=0, write_sync1=0, read_sync0=0, read_sync1=0;
    reg [3:0] state = S_IDLE;
    reg operation_read=0, operation_token=0;
    reg [9:0] sector=0;
    reg [8:0] chunk_base=0;
    reg [COUNT_BITS-1:0] sent_count=0, received_count=0;
    reg [QUIET_BITS-1:0] quiet_count=0;
    reg [YIELD_BITS-1:0] yield_count=0;
    reg [WATCHDOG_BITS-1:0] watchdog=0;
    reg write_valid=0;
    reg [20:0] write_address=0;
    wire take_read = state == S_IDLE && read_sync1 != read_ack_toggle;
    wire take_write = state == S_IDLE && !take_read && write_sync1 != write_ack_toggle;
    wire [9:0] remaining_words = 10'd512 - {1'b0,chunk_base};
    wire [COUNT_BITS-1:0] chunk_limit = remaining_words < BURST_WORDS
                                                   ? remaining_words : BURST_WORDS;
    wire [9:0] next_base = {1'b0,chunk_base} + chunk_limit;
    wire [8:0] sent_offset = chunk_base + sent_count;
    wire [8:0] received_offset = chunk_base + received_count;
    wire quiet = !video_read_busy && !video_write_busy && !controller_busy &&
                 !refresh_active && !mem_read_valid && !mem_wr_en && !mem_rd_en;
    wire drain_ready = quiet && (DRAIN_CYCLES == 0 || quiet_count >= DRAIN_CYCLES-1);
    wire read_complete = received_count == chunk_limit;
    wire chunk_done = (state == S_WRITE_DRAIN && drain_ready) ||
                      (state == S_READ_DRAIN && read_complete && drain_ready);
    wire active = state == S_LOCK || state == S_WRITE || state == S_READ ||
                  state == S_WRITE_DRAIN || state == S_READ_DRAIN;
    wire expired = &watchdog;
    wire received_word = read_owner && mem_read_valid && !read_complete;

    // Both outputs depend only on registered state, never on live busy inputs.
    // In S_LOCK old video returns still belong to the video reader.
    assign access_lock = active;
    assign read_owner = state == S_READ || state == S_READ_DRAIN;
    assign mem_rd_en = state == S_READ;
    assign mem_rd_addr = {2'b00,sector,sent_offset};
    assign mem_wr_en = write_valid;
    assign mem_wr_addr = write_address;
    assign mem_wr_data = {24'd0,stage_dout};
    assign mem_wr_mask = 4'b1110;
    assign stage_en = state == S_WRITE || received_word;
    assign stage_we = received_word;
    assign stage_addr = received_word ? {1'b1,received_offset} : {1'b0,sent_offset};
    assign stage_din = mem_read_data[7:0];

    always @(posedge mem_clk or negedge rst_n) begin
        if (!rst_n) write_sync0 <= 0; else write_sync0 <= write_request_toggle;
    end
    always @(posedge mem_clk or negedge rst_n) begin
        if (!rst_n) write_sync1 <= 0; else write_sync1 <= write_sync0;
    end
    always @(posedge mem_clk or negedge rst_n) begin
        if (!rst_n) read_sync0 <= 0; else read_sync0 <= read_request_toggle;
    end
    always @(posedge mem_clk or negedge rst_n) begin
        if (!rst_n) read_sync1 <= 0; else read_sync1 <= read_sync0;
    end
    always @(posedge mem_clk or negedge rst_n) begin
        if (!rst_n) operation_read <= 0;
        else if (take_read || take_write) operation_read <= take_read;
    end
    always @(posedge mem_clk or negedge rst_n) begin
        if (!rst_n) operation_token <= 0;
        else if (take_read || take_write) operation_token <= take_read ? read_sync1 : write_sync1;
    end
    // Payload has already been stable for the two toggle synchronizer clocks.
    always @(posedge mem_clk or negedge rst_n) begin
        if (!rst_n) sector <= 0;
        else if (take_read || take_write) sector <= take_read ? read_sector : write_sector;
    end
    always @(posedge mem_clk or negedge rst_n) begin
        if (!rst_n) state <= S_IDLE;
        else if (active && expired) state <= S_FAIL;
        else case (state)
            S_IDLE: if (take_read || take_write) state <= S_LOCK;
            S_LOCK: if (drain_ready) state <= operation_read ? S_READ : S_WRITE;
            S_WRITE: if (sent_count == chunk_limit-1'b1) state <= S_WRITE_DRAIN;
            S_READ: if (sent_count == chunk_limit-1'b1) state <= S_READ_DRAIN;
            S_WRITE_DRAIN, S_READ_DRAIN:
                if (chunk_done) state <= next_base == 10'd512 ? S_DONE : S_YIELD;
            S_YIELD: if (YIELD_CYCLES == 0 || yield_count >= YIELD_CYCLES-1) state <= S_LOCK;
            S_DONE, S_FAIL: state <= S_IDLE;
            default: state <= S_IDLE;
        endcase
    end
    always @(posedge mem_clk or negedge rst_n) begin
        if (!rst_n) chunk_base <= 0;
        else if (take_read || take_write) chunk_base <= 0;
        else if (chunk_done) chunk_base <= next_base[8:0];
    end
    always @(posedge mem_clk or negedge rst_n) begin
        if (!rst_n) sent_count <= 0;
        else if (state == S_LOCK) sent_count <= 0;
        else if (state == S_WRITE || state == S_READ) sent_count <= sent_count + 1'b1;
    end
    always @(posedge mem_clk or negedge rst_n) begin
        if (!rst_n) received_count <= 0;
        else if (state == S_LOCK) received_count <= 0;
        else if (received_word) received_count <= received_count + 1'b1;
    end
    always @(posedge mem_clk or negedge rst_n) begin
        if (!rst_n) quiet_count <= 0;
        else if (!active || !quiet || (state == S_READ_DRAIN && !read_complete)) quiet_count <= 0;
        else if (!drain_ready) quiet_count <= quiet_count + 1'b1;
    end
    always @(posedge mem_clk or negedge rst_n) begin
        if (!rst_n) yield_count <= 0;
        else if (state != S_YIELD) yield_count <= 0;
        else if (yield_count < YIELD_CYCLES) yield_count <= yield_count + 1'b1;
    end
    always @(posedge mem_clk or negedge rst_n) begin
        if (!rst_n) watchdog <= 0;
        else if (!active || mem_wr_en || mem_rd_en || received_word || chunk_done) watchdog <= 0;
        else if (!expired) watchdog <= watchdog + 1'b1;
    end
    // The synchronous staging RAM and this register advance on the same edge.
    // Thus stage_dout and write_address refer to the same preceding RAM read.
    always @(posedge mem_clk or negedge rst_n) begin
        if (!rst_n) write_valid <= 0;
        else write_valid <= state == S_WRITE;
    end
    always @(posedge mem_clk or negedge rst_n) begin
        if (!rst_n) write_address <= 0;
        else if (state == S_WRITE) write_address <= {2'b00,sector,sent_offset};
    end
    always @(posedge mem_clk or negedge rst_n) begin
        if (!rst_n) write_ack_toggle <= 0;
        else if ((state == S_DONE || state == S_FAIL) && !operation_read) write_ack_toggle <= operation_token;
    end
    always @(posedge mem_clk or negedge rst_n) begin
        if (!rst_n) read_ack_toggle <= 0;
        else if ((state == S_DONE || state == S_FAIL) && operation_read) read_ack_toggle <= operation_token;
    end
    always @(posedge mem_clk or negedge rst_n) begin
        if (!rst_n) write_error <= 0;
        else if (take_write) write_error <= 0;
        else if (active && expired && !operation_read) write_error <= 8'h01;
    end
    always @(posedge mem_clk or negedge rst_n) begin
        if (!rst_n) read_error <= 0;
        else if (take_read) read_error <= 0;
        else if (active && expired && operation_read) read_error <= 8'h02;
    end
endmodule
`endif

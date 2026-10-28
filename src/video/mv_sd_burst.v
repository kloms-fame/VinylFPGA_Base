`ifndef VINYL_MV_SD_BURST_V
`define VINYL_MV_SD_BURST_V
// Presents the existing one-sector MV player interface while prefetching a
// bounded CMD18 burst into two 512-byte banks. The SD stream is paused at a
// block boundary when both banks are full, so an 8-sector CMD18 command is
// amortized without needing an 8-sector elastic buffer.
module mv_sd_burst(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        abort,
    input  wire        allow,
    input  wire        stream_active,

    input  wire        sector_req,
    input  wire [31:0] sector_lba,
    output wire        sector_busy,
    output wire        sector_valid,
    output wire [7:0]  sector_byte,
    output wire [8:0]  sector_byte_index,
    output reg         sector_done,
    output reg  [7:0]  sector_error,

    output reg         burst_req,
    output reg  [31:0] burst_lba,
    output reg  [7:0]  burst_len,
    output wire        burst_pause,
    input  wire        burst_active,
    input  wire        burst_valid,
    input  wire [7:0]  burst_data,
    input  wire        burst_sector_done,
    input  wire        burst_done,
    input  wire [7:0]  burst_error,
    output reg         burst_stop,
    output wire [1:0]  debug_buf_count
);
    localparam [7:0] BURST_SECTORS = 8'd8;

    reg [1:0]  full;
    reg [1:0]  buf_count;
    reg        rd_buf, wr_buf;
    reg [9:0]  wr_cnt;
    reg [8:0]  out_idx;
    reg [7:0]  rd_data;
    reg [31:0] buf_lba0, buf_lba1, wr_lba;
    reg        out_active, out_last, out_pending, err_pending;
    reg [11:0] idle_cnt;
    // The grant comes from the SD owner in another hierarchy level and is
    // combinational through the audio low-water flags. Sampling it once here
    // keeps that long chain off the burst_lba load enable.
    reg        allow_q;
    always @(posedge clk or negedge rst_n)
        if (!rst_n) allow_q <= 1'b0;
        else        allow_q <= allow;
    assign debug_buf_count = buf_count;

    // Select the bank that actually holds the requested LBA. A fixed
    // read-bank toggle is wrong when the player consumes a bank before the
    // other bank is filled: the freed bank is refilled with the next sector
    // and must become the next read bank.
    wire        rd_match0 = full[0] && (buf_lba0 == sector_lba);
    wire        rd_match1 = full[1] && (buf_lba1 == sector_lba);
    wire        rd_sel = rd_match0 ? 1'b0 : (rd_match1 ? 1'b1 : rd_buf);
    wire [31:0] rd_lba = rd_sel ? buf_lba1 : buf_lba0;
    wire        buf_ready = sector_req && (rd_match0 || rd_match1) && !out_active && !out_pending;
    wire        lba_mismatch = (buf_count != 2'd0) && (sector_lba != wr_lba);
    wire        start_burst = allow_q && stream_active && sector_req && !buf_ready && !burst_req &&
                              !burst_active && !out_active && !out_pending &&
                              !err_pending && (buf_count != 2'd2);
    wire [31:0] start_lba = (buf_count == 2'd0 || lba_mismatch) ?
                            sector_lba : wr_lba;
    wire        fill_ev  = burst_sector_done && (buf_count != 2'd2);
    wire        consume_ev = out_active && out_last;
    wire [1:0]  count_next = buf_count + (fill_ev ? 2'd1 : 2'd0) -
                             (consume_ev ? 2'd1 : 2'd0);
    // A frame ends after its last 300-sector request. If prefetch has already
    // filled both banks, the CMD18 reader is paused at a block boundary and
    // would otherwise hold the card forever. Only stop in that paused state:
    // aborting mid-block would leave the card streaming while CMD12 is sent.
    // A request for an LBA that is in neither bank means the player restarted
    // (track change / seek). Both banks are then stale and the reader is also
    // paused, so the only safe recovery is to stop and flush them.
    wire        stale_full = (buf_count == 2'd2) && sector_req &&
                             (buf_lba0 != sector_lba) && (buf_lba1 != sector_lba);
    wire        pause_stop = burst_req && burst_pause &&
                             (!stream_active ||
                              (!sector_req && !out_active && !out_pending &&
                               (idle_cnt == 12'd4095)));
    wire        stop_burst = stale_full || pause_stop;
    wire        idle_clear = !burst_req || !burst_pause || sector_req ||
                            out_active || out_pending;

    // Packet RAM lives in one explicit 32K block. The device has only 64 9K
    // blocks and every one of them is already assigned (frame FIFOs, audio
    // staging, vendor ROM/FIFO macros, ASCII font), so an inferred 1024x8 RAM
    // would push the design to 65/64. A DP16K 32K block is used in 16-bit mode
    // with the byte in the low half: 1024 words of 2048, 14 blocks free.
    // Read latency stays one cycle (NOREG), identical to the behavioural model.
    wire        mem_wr_en = burst_valid && (buf_count != 2'd2);
    wire [9:0]  mem_wr_addr = {wr_buf, wr_cnt[8:0]};
    wire        mem_rd_en = out_pending || out_active;
    // The read data is registered, so address the byte that will be needed on
    // the next clock. At the first active cycle this is index 0; afterwards the
    // index advances by one each cycle.
    wire [9:0]  mem_rd_addr = out_active ? {rd_buf, out_idx + 9'd1} : {rd_buf, 9'd0};

`ifdef VINYL_MV_BURST_BEHAV
    // Functional-simulation model: same one-cycle read contract as the block.
    reg [7:0] mem [0:1023];
    always @(posedge clk)
        if (mem_wr_en)
            mem[mem_wr_addr] <= burst_data;
    always @(posedge clk)
        if (mem_rd_en)
            rd_data <= mem[mem_rd_addr];
`else
    wire [15:0] packet_q;
    EG_PHY_BRAM32K #(
        .MODE("DP16K"), .DATA_WIDTH_A("16"), .DATA_WIDTH_B("16"),
        .REGMODE_A("NOREG"), .REGMODE_B("NOREG"),
        .WRITEMODE_A("NORMAL"), .WRITEMODE_B("NORMAL"), .SRMODE("SYNC")
    ) packet_ram (
        .clka(clk), .csa(mem_wr_en), .wea(1'b1), .addra({1'b0, mem_wr_addr}),
        .dia({8'd0, burst_data}), .doa(), .bytea(1'b0), .bytewea(1'b0),
        .rsta(1'b0), .ocea(1'b1),
        .clkb(clk), .csb(mem_rd_en), .web(1'b0), .addrb({1'b0, mem_rd_addr}),
        .dib(16'd0), .dob(packet_q), .byteb(1'b0), .byteweb(1'b0),
        .rstb(1'b0), .oceb(1'b1)
    );
    always @(*) rd_data = packet_q[7:0];
`endif

    assign sector_byte       = rd_data;
    assign sector_byte_index = out_idx;
    assign sector_valid      = out_active && !out_last;
    assign sector_busy       = sector_req && !out_pending && !out_active && !err_pending;
    assign burst_pause       = (buf_count == 2'd2);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            full        <= 2'd0;
            buf_count   <= 2'd0;
            rd_buf      <= 1'b0;
            wr_buf      <= 1'b0;
            wr_cnt      <= 10'd0;
            out_idx     <= 9'd0;
            buf_lba0    <= 32'd0;
            buf_lba1    <= 32'd0;
            wr_lba      <= 32'd0;
            out_active  <= 1'b0;
            out_last    <= 1'b0;
            out_pending <= 1'b0;
            err_pending <= 1'b0;
            idle_cnt    <= 12'd0;
            burst_stop  <= 1'b0;
            sector_done <= 1'b0;
            sector_error<= 8'd0;
            burst_req   <= 1'b0;
            burst_lba   <= 32'd0;
            burst_len   <= 8'd0;
        end else begin
            sector_done <= 1'b0;

            if (abort) begin
                idle_cnt    <= 12'd0;
                burst_stop  <= 1'b0;
                burst_req   <= 1'b0;
                full        <= 2'd0;
                buf_count   <= 2'd0;
                rd_buf      <= 1'b0;
                wr_buf      <= 1'b0;
                wr_cnt      <= 10'd0;
                out_idx     <= 9'd0;
                out_active  <= 1'b0;
                out_last    <= 1'b0;
                out_pending <= 1'b0;
                err_pending <= 1'b0;
                sector_error<= 8'd0;
                burst_lba   <= 32'd0;
                burst_len   <= 8'd0;
            end else begin
                burst_stop <= 1'b0;
                if (idle_clear) idle_cnt <= 12'd0;
                else idle_cnt <= idle_cnt + 12'd1;
                if (stop_burst) begin
                    burst_req   <= 1'b0;
                    burst_stop  <= 1'b1;
                    full        <= 2'd0;
                    buf_count   <= 2'd0;
                    rd_buf      <= 1'b0;
                    wr_buf      <= 1'b0;
                end
                // Fill the current bank from the CMD18 stream.
                // Guard the RAM write as well as the metadata: a late/spurious
                // sector after both banks are full must not overwrite a bank
                // that still has unread data.
                if (burst_valid && (buf_count != 2'd2))
                    wr_cnt <= wr_cnt + 10'd1;

                if (fill_ev) begin
                    if (wr_buf)
                        buf_lba1 <= wr_lba;
                    else
                        buf_lba0 <= wr_lba;
                    full[wr_buf] <= 1'b1;
                    wr_lba      <= wr_lba + 32'd1;
                    wr_cnt      <= 10'd0;
                    wr_buf      <= ~wr_buf;
                end

                if (burst_done) begin
                    burst_req <= 1'b0;
                    if (burst_error != 8'd0) begin
                        sector_error <= burst_error;
                        err_pending  <= 1'b1;
                    end
                end

                // One-cycle handoff: deassert busy, then start byte output in
                // the cycle where the player has entered READ.
                if (buf_ready && !out_pending) begin
                    out_pending <= 1'b1;
                    rd_buf      <= rd_sel;
                end else if (out_pending) begin
                    out_pending <= 1'b0;
                    out_active  <= 1'b1;
                    out_idx     <= 9'd0;
                end else if (out_active) begin
                    if (out_last) begin
                        out_active  <= 1'b0;
                        out_last    <= 1'b0;
                        sector_done <= 1'b1;
                        full[rd_buf]<= 1'b0;
                        // Do not move the write pointer here: a sector may be
                        // in flight into the other bank. At a block boundary
                        // wr_buf already points at the freed (oldest) bank,
                        // because it toggles only when a fill completes.
                    end else if (out_idx == 9'd511) begin
                        out_last <= 1'b1;
                    end else begin
                        out_idx <= out_idx + 9'd1;
                    end
                end

                if (err_pending) begin
                    err_pending <= 1'b0;
                    sector_done <= 1'b1;
                end

                // Start the next CMD18 burst only when the player has no bank
                // ready. A mismatched LBA means the player restarted; discard
                // stale prefetched sectors rather than crossing a track.
                if (start_burst) begin
                    if (lba_mismatch || (buf_count == 2'd0)) begin
                        full      <= 2'd0;
                        rd_buf    <= 1'b0;
                        wr_buf    <= 1'b0;
                        wr_lba    <= sector_lba;
                    end
                    burst_req <= 1'b1;
                    burst_lba <= start_lba;
                    burst_len <= BURST_SECTORS;
                    sector_error <= 8'd0;
                end

                // Single-owner count update: a block can retire in the same
                // cycle that the consumer retires a bank. An increment and a
                // decrement must net to zero instead of one assignment winning.
                if (stop_burst)
                    buf_count <= 2'd0;
                else if (start_burst && (lba_mismatch || (buf_count == 2'd0)))
                    buf_count <= 2'd0;
                else
                    buf_count <= count_next;
            end
        end
    end
endmodule
`endif
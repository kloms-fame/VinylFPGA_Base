`ifndef VINYL_SD_CMD18_READER_V
`define VINYL_SD_CMD18_READER_V
// Bounded multi-block read owner for the MV path.
// CMD18 streams `sectors` blocks; the bridge may pause the SPI clock at a block
// boundary (multi_pause) and the reader stops the stream with CMD12. Audio and
// background keep using the existing CMD17 owner in sd_card_sec_read_write.
module sd_cmd18_reader #(parameter [25:0] TIMEOUT_CYCLES = 26'd50_000_000)(
    input  wire        clk,
    input  wire        rst,
    input  wire        start,
    input  wire [31:0] lba,
    input  wire [7:0]  sectors,
    input  wire        pause,
    input  wire        abort,

    output reg         cmd_req,
    output reg  [47:0] cmd,
    output reg  [7:0]  cmd_r1,
    output reg  [15:0] cmd_data_len,
    output reg         cmd_keep_cs,
    output reg         cmd_wait_busy,
    input  wire        cmd_req_ack,
    input  wire        cmd_req_error,

    output reg         block_read_req,
    output reg         multi_read,
    output reg  [7:0]  multi_sectors,
    output wire        multi_pause,
    output reg         multi_abort,
    input  wire        block_read_valid,
    input  wire [7:0]  block_read_data,
    input  wire        multi_sector_done,
    input  wire        multi_read_done,

    output wire        valid,
    output wire [7:0]  data,
    output wire        sector_done,
    output wire        active,
    output reg         done,
    output reg  [7:0]  error,
    output wire [3:0]  debug_state
);
    localparam S_IDLE    = 4'd0;
    localparam S_CMD18   = 4'd1;
    localparam S_DATA    = 4'd2;
    localparam S_CMD12   = 4'd3;
    localparam S_DONE    = 4'd4;
    localparam S_ERR     = 4'd5;

    // 500 ms at 100 MHz. The counter is held while the bridge intentionally
    // pauses the card, so a full 8-sector burst can wait for the MV buffer.

    reg [3:0]  state;
    reg [3:0]  state_d;
    reg [31:0] lba_lat;
    reg [7:0]  sectors_lat;
    reg [25:0] timeout_cnt;
    reg        abort_lat;
    reg        start_d;
    // Registered owner flag. The synthesis tool may one-hot encode the state
    // vector, so comparing the encoded state against literal 0 is unsafe.
    reg        active_r;

    assign valid       = (state == S_DATA) && block_read_valid;
    assign data        = block_read_data;
    assign sector_done = (state == S_DATA) && multi_sector_done;
    assign multi_pause = pause;
    assign active      = active_r;
    assign debug_state = state;

    always @(posedge clk or posedge rst) begin
        if (rst) state_d <= S_IDLE;
        else state_d <= state;
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state          <= S_IDLE;
            cmd_req        <= 1'b0;
            cmd            <= 48'd0;
            cmd_r1         <= 8'd0;
            cmd_data_len   <= 16'd0;
            cmd_keep_cs    <= 1'b0;
            cmd_wait_busy  <= 1'b0;
            block_read_req <= 1'b0;
            multi_read     <= 1'b0;
            multi_sectors  <= 8'd0;
            multi_abort    <= 1'b0;
            done           <= 1'b0;
            error          <= 8'd0;
            lba_lat        <= 32'd0;
            sectors_lat    <= 8'd0;
            timeout_cnt    <= 26'd0;
            abort_lat      <= 1'b0;
            start_d       <= 1'b0;
            active_r       <= 1'b0;
        end else begin
            done <= 1'b0;
            start_d <= start;

            // Watchdog only runs while the card is actually being clocked.
            // CMD12 is a bus recovery command and must not be blocked by a
            // stale multi-block pause.
            if (state != state_d) timeout_cnt <= 26'd0;
            else if (state == S_CMD12 ||
                ((state == S_CMD18 || state == S_DATA) && !pause))
                timeout_cnt <= timeout_cnt + 26'd1;
            else
                timeout_cnt <= 26'd0;

            case (state)
                S_IDLE: begin
                    cmd_req        <= 1'b0;
                    block_read_req <= 1'b0;
                    multi_read     <= 1'b0;
                    multi_abort    <= 1'b0;
                    cmd_keep_cs    <= 1'b0;
                    cmd_wait_busy  <= 1'b0;
                    error          <= 8'd0;
                    timeout_cnt    <= 26'd0;
                    abort_lat      <= 1'b0;
                    if (start && !start_d) begin
                        lba_lat     <= lba;
                        sectors_lat <= (sectors == 8'd0) ? 8'd1 : sectors;
                        cmd         <= {8'd18, lba, 8'hff};
                        cmd_r1      <= 8'h00;
                        cmd_data_len<= 16'd0;
                        cmd_keep_cs <= 1'b0;
                        cmd_wait_busy <= 1'b0;
                        cmd_req     <= 1'b1;
                        active_r    <= 1'b1;
                        state       <= S_CMD18;
                    end
                end

                S_CMD18: begin
                    if (abort)
                        abort_lat <= 1'b1;
                    if (state == state_d && timeout_cnt >= TIMEOUT_CYCLES) begin
                        cmd_req <= 1'b0;
                        error   <= 8'h06;
                        state   <= S_DONE;
                    end else if (cmd_req_ack) begin
                        cmd_req <= 1'b0;
                        if (cmd_req_error) begin
                            error <= 8'h06;
                            state <= S_DONE;
                        end else if (abort_lat || abort) begin
                            // The command is already on the wire; stop it with
                            // CMD12 as soon as the command phase retires.
                            block_read_req <= 1'b0;
                            multi_read     <= 1'b0;
                            cmd          <= {8'd12, 32'd0, 8'hff};
                            cmd_r1       <= 8'h00;
                            cmd_data_len <= 16'd0;
                            cmd_keep_cs  <= 1'b1;
                            cmd_wait_busy<= 1'b1;
                            cmd_req      <= 1'b1;
                            state        <= S_CMD12;
                        end else begin
                            block_read_req <= 1'b1;
                            multi_read     <= 1'b1;
                            multi_sectors  <= sectors_lat;
                            state          <= S_DATA;
                        end
                    end
                end

                S_DATA: begin
                    if (abort) abort_lat <= 1'b1;
                    if ((abort || abort_lat) && (multi_sector_done || pause)) begin
                        abort_lat      <= 1'b1;
                        block_read_req <= 1'b0;
                        multi_read     <= 1'b0;
                        multi_abort    <= 1'b1;
                        cmd          <= {8'd12, 32'd0, 8'hff};
                        cmd_r1       <= 8'h00;
                        cmd_data_len <= 16'd0;
                        cmd_keep_cs  <= 1'b1;
                        cmd_wait_busy<= 1'b1;
                        cmd_req      <= 1'b1;
                        state        <= S_CMD12;
                    end else if (state == state_d && timeout_cnt >= TIMEOUT_CYCLES) begin
                        error          <= 8'h06;
                        block_read_req <= 1'b0;
                        multi_read     <= 1'b0;
                        multi_abort    <= 1'b1;
                        cmd          <= {8'd12, 32'd0, 8'hff};
                        cmd_r1       <= 8'h00;
                        cmd_data_len <= 16'd0;
                        cmd_keep_cs  <= 1'b1;
                        cmd_wait_busy<= 1'b1;
                        cmd_req      <= 1'b1;
                        state        <= S_CMD12;
                    end else if (multi_read_done) begin
                        block_read_req <= 1'b0;
                        multi_read     <= 1'b0;
                        cmd          <= {8'd12, 32'd0, 8'hff};
                        cmd_r1       <= 8'h00;
                        cmd_data_len <= 16'd0;
                        cmd_keep_cs  <= 1'b1;
                        cmd_wait_busy<= 1'b1;
                        cmd_req      <= 1'b1;
                        state        <= S_CMD12;
                    end
                end

                S_CMD12: begin
                    if (state == state_d && timeout_cnt >= TIMEOUT_CYCLES) begin
                        // Never hold the shared card after a failed stop.
                        cmd_req     <= 1'b0;
                        multi_abort <= 1'b0;
                        error       <= 8'h08;
                        state       <= S_DONE;
                    end else if (cmd_req_ack) begin
                        cmd_req <= 1'b0;
                        multi_abort <= 1'b0;
                        if (cmd_req_error)
                            error <= 8'h07;
                        state <= S_DONE;
                    end
                end

                S_DONE: begin
                    done     <= 1'b1;
                    active_r <= 1'b0;
                    state    <= S_IDLE;
                end

                S_ERR: begin
                    error    <= 8'h06;
                    done     <= 1'b1;
                    active_r <= 1'b0;
                    state    <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
`endif
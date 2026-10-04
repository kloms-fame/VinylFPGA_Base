`timescale 1ns/1ps

module tb_bmp_read_stability;
    localparam integer CLK_PERIOD = 10;
    localparam integer BMP_W = 4;
    localparam integer BMP_H = 2;
    localparam integer PIXEL_BYTES = BMP_W * BMP_H * 3;
    localparam integer FILE_LEN = 54 + PIXEL_BYTES;

    localparam [2:0] ERR_NONE      = 3'd0;
    localparam [2:0] ERR_HEADER    = 3'd1;
    localparam [2:0] ERR_TIMEOUT   = 3'd2;
    localparam [2:0] ERR_TRUNCATED = 3'd3;

    localparam [2:0] SCEN_VALID       = 3'd0;
    localparam [2:0] SCEN_BAD_DIB     = 3'd1;
    localparam [2:0] SCEN_BAD_PLANES  = 3'd2;
    localparam [2:0] SCEN_BAD_FILELEN = 3'd3;
    localparam [2:0] SCEN_TRUNCATED   = 3'd4;
    localparam [2:0] SCEN_FASTSKIP    = 3'd5;
    localparam [2:0] SCEN_TIMEOUT     = 3'd6;
    localparam [2:0] SCEN_LONG_SCAN   = 3'd7;

    // 30 个空扇区 × 约 513 个时钟/扇区 ≈ 15,390 周期，已超过
    // TIMEOUT_CYCLES=10,000。用于验证超时按"单个扇区"而非"整段扫描"计时。
    localparam [31:0] LONG_SCAN_TARGET = 32'd30;

    reg        clk;
    reg        rst;
    wire       ready;
    reg        scan_start;
    reg [31:0] scan_start_sector;
    reg [31:0] scan_max_sector;
    reg [2:0]  scan_target_count;
    wire       scan_done;
    wire       scan_found_valid;
    wire [31:0] scan_found_sector;
    wire [2:0] scan_found_total;
    reg        load_start;
    reg [31:0] load_sector;
    reg        sd_init_done;
    wire [3:0] state_code;
    wire [2:0] bmp_error;
    wire       load_error;
    wire       write_req;
    reg        write_req_ack;
    wire       sd_sec_read;
    wire [31:0] sd_sec_read_addr;
    wire [7:0] sd_sec_read_data;
    wire       sd_sec_read_data_valid;
    wire       sd_sec_read_end;
    wire       bmp_data_wr_en;
    wire [23:0] bmp_data;

    integer fails;
    integer pixel_writes;
    reg     seen_load_error;
    reg [2:0] captured_error;
    reg [2:0] scenario;
    reg       withhold_response;
    reg       skip_valid;
    reg [15:0] skip_offset;

    reg [31:0] card_addr;
    reg [15:0] card_idx;
    reg        card_active;
    reg        card_data_valid;
    reg [7:0]  card_data;
    reg        card_end;
    reg [15:0] exp_width;
    reg [15:0] exp_height;

    bmp_read #(
        .CLK_FREQ_HZ        (10_000_000),
        .SD_READ_TIMEOUT_MS (1)
    ) dut (
        .clk                    (clk),
        .rst                    (rst),
        .ready                  (ready),
        .scan_start             (scan_start),
        .scan_start_sector      (scan_start_sector),
        .scan_max_sector        (scan_max_sector),
        .scan_target_count      (scan_target_count),
        .scan_done              (scan_done),
        .scan_found_valid       (scan_found_valid),
        .scan_found_sector      (scan_found_sector),
        .scan_found_total       (scan_found_total),
        .load_start             (load_start),
        .load_sector            (load_sector),
        .sd_init_done           (sd_init_done),
        .state_code             (state_code),
        .bmp_width              (exp_width),
        .bmp_height             (exp_height),
        .bmp_error              (bmp_error),
        .load_error             (load_error),
        .write_req              (write_req),
        .write_req_ack          (write_req_ack),
        .sd_sec_read            (sd_sec_read),
        .sd_sec_read_addr       (sd_sec_read_addr),
        .sd_sec_read_data       (sd_sec_read_data),
        .sd_sec_read_data_valid (sd_sec_read_data_valid),
        .sd_sec_read_end        (sd_sec_read_end),
        .bmp_data_wr_en         (bmp_data_wr_en),
        .bmp_data               (bmp_data)
    );

    assign sd_sec_read_data       = card_data;
    assign sd_sec_read_data_valid = card_data_valid;
    assign sd_sec_read_end        = card_end;

    function [7:0] le_byte;
        input [31:0] value;
        input integer idx;
        begin
            case (idx)
                0: le_byte = value[7:0];
                1: le_byte = value[15:8];
                2: le_byte = value[23:16];
                3: le_byte = value[31:24];
                default: le_byte = 8'h00;
            endcase
        end
    endfunction

    function [7:0] bmp_byte;
        input [15:0] off;
        input [31:0] f_len;
        input [31:0] pix_off;
        input [31:0] dib;
        input [31:0] w;
        input [31:0] h;
        input [15:0] pl;
        input [15:0] bpp;
        input [31:0] comp;
        begin
            if (off == 0)
                bmp_byte = "B";
            else if (off == 1)
                bmp_byte = "M";
            else if ((off >= 2) && (off <= 5))
                bmp_byte = le_byte(f_len, off - 2);
            else if ((off >= 10) && (off <= 13))
                bmp_byte = le_byte(pix_off, off - 10);
            else if ((off >= 14) && (off <= 17))
                bmp_byte = le_byte(dib, off - 14);
            else if ((off >= 18) && (off <= 21))
                bmp_byte = le_byte(w, off - 18);
            else if ((off >= 22) && (off <= 25))
                bmp_byte = le_byte(h, off - 22);
            else if ((off >= 26) && (off <= 27))
                bmp_byte = le_byte({16'd0, pl}, off - 26);
            else if ((off >= 28) && (off <= 29))
                bmp_byte = le_byte({16'd0, bpp}, off - 28);
            else if ((off >= 30) && (off <= 33))
                bmp_byte = le_byte(comp, off - 30);
            else if ((off >= pix_off) && (off < (pix_off + PIXEL_BYTES)))
                bmp_byte = 8'h80;
            else
                bmp_byte = 8'h00;
        end
    endfunction

    function [7:0] card_byte;
        input [2:0]  scen;
        input [31:0] addr;
        input [15:0] off;
        begin
            case (scen)
                SCEN_VALID:
                    card_byte = bmp_byte(off, FILE_LEN, 54, 40, BMP_W, BMP_H, 1, 24, 0);
                SCEN_BAD_DIB:
                    card_byte = bmp_byte(off, FILE_LEN, 54, 12, BMP_W, BMP_H, 1, 24, 0);
                SCEN_BAD_PLANES:
                    card_byte = bmp_byte(off, FILE_LEN, 54, 40, BMP_W, BMP_H, 2, 24, 0);
                SCEN_BAD_FILELEN:
                    card_byte = bmp_byte(off, 76, 54, 40, BMP_W, BMP_H, 1, 24, 0);
                SCEN_TRUNCATED:
                    card_byte = bmp_byte(off, FILE_LEN, 54, 40, BMP_W, BMP_H, 1, 24, 0);
                SCEN_FASTSKIP: begin
                    if (addr == 32'd0)
                        card_byte = bmp_byte(off, 600, 54, 40, 8, BMP_H, 1, 24, 0);
                    else if (addr == 32'd2)
                        card_byte = bmp_byte(off, FILE_LEN, 54, 40, BMP_W, BMP_H, 1, 24, 0);
                    else
                        card_byte = 8'h00;
                end
                SCEN_TIMEOUT:
                    card_byte = bmp_byte(off, FILE_LEN, 54, 40, BMP_W, BMP_H, 1, 24, 0);
                SCEN_LONG_SCAN: begin
                    if (addr == LONG_SCAN_TARGET)
                        card_byte = bmp_byte(off, FILE_LEN, 54, 40, BMP_W, BMP_H, 1, 24, 0);
                    else
                        card_byte = 8'h00;
                end
                default:
                    card_byte = 8'h00;
            endcase
        end
    endfunction

    always #(CLK_PERIOD/2) clk = ~clk;

    // Simple ack model for the SDRAM write request handshake.
    always @(posedge clk or posedge rst) begin
        if (rst)
            write_req_ack <= 1'b0;
        else
            write_req_ack <= write_req;
    end

    // Monitor error pulses and pixel writes.
    always @(negedge clk or posedge rst) begin
        if (rst) begin
            seen_load_error <= 1'b0;
            captured_error  <= ERR_NONE;
        end else begin
            if (load_error) begin
                seen_load_error <= 1'b1;
                captured_error  <= bmp_error;
            end
            if (bmp_data_wr_en)
                pixel_writes <= pixel_writes + 1;
        end
    end

    // Fake SD sector reader: 512 bytes per sector, then one end pulse.
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            card_addr       <= 32'd0;
            card_idx        <= 16'd0;
            card_active     <= 1'b0;
            card_data_valid <= 1'b0;
            card_data       <= 8'h00;
            card_end        <= 1'b0;
        end else begin
            card_data_valid <= 1'b0;
            card_end        <= 1'b0;

            if (!card_active) begin
                if (sd_sec_read && !withhold_response && !card_end) begin
                    card_active <= 1'b1;
                    card_addr   <= sd_sec_read_addr;
                    card_idx    <= 16'd0;
                    if (!(skip_valid && (skip_offset == 16'd0))) begin
                        card_data_valid <= 1'b1;
                        card_data       <= card_byte(scenario, sd_sec_read_addr, 16'd0);
                    end
                end
            end else begin
                if (!withhold_response) begin
                    if (card_idx < 16'd511) begin
                        card_idx <= card_idx + 16'd1;
                        if (!(skip_valid && ((card_idx + 16'd1) == skip_offset))) begin
                            card_data_valid <= 1'b1;
                            card_data       <= card_byte(scenario, card_addr, card_idx + 16'd1);
                        end
                    end else begin
                        card_active <= 1'b0;
                        card_idx    <= 16'd0;
                        card_end    <= 1'b1;
                    end
                end
            end
        end
    end

    task reset_dut;
        begin
            rst               = 1'b1;
            scan_start        = 1'b0;
            load_start        = 1'b0;
            sd_init_done      = 1'b0;
            scan_start_sector = 32'd0;
            scan_max_sector   = 32'd0;
            scan_target_count = 3'd0;
            load_sector       = 32'd0;
            scenario          = SCEN_VALID;
            withhold_response = 1'b0;
            skip_valid        = 1'b0;
            skip_offset       = 16'd0;
            exp_width         = BMP_W[15:0];
            exp_height        = BMP_H[15:0];
            pixel_writes      = 0;
            seen_load_error   = 1'b0;
            captured_error    = ERR_NONE;
            repeat (5) @(posedge clk);
            rst = 1'b0;
            sd_init_done = 1'b1;
            repeat (3) @(posedge clk);
        end
    endtask

    task start_scan;
        input [31:0] start_sec;
        input [31:0] max_sec;
        input [2:0]  target_count;
        begin
            @(posedge clk);
            scan_start_sector = start_sec;
            scan_max_sector   = max_sec;
            scan_target_count = target_count;
            scan_start        = 1'b1;
            @(posedge clk);
            scan_start = 1'b0;
        end
    endtask

    task start_load;
        input [31:0] sector;
        begin
            @(posedge clk);
            load_sector = sector;
            load_start  = 1'b1;
            @(posedge clk);
            load_start = 1'b0;
        end
    endtask

    task wait_scan_done;
        integer timeout;
        begin
            timeout = 0;
            while (!scan_done && (timeout < 200000)) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (timeout >= 200000) begin
                $display("FAIL: testbench scan wait timeout");
                fails = fails + 1;
            end
        end
    endtask

    task wait_load_done;
        integer timeout;
        begin
            timeout = 0;
            while (ready && (timeout < 100)) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            timeout = 0;
            while (!ready && !seen_load_error && (timeout < 200000)) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (timeout >= 200000) begin
                $display("FAIL: testbench load wait timeout");
                fails = fails + 1;
            end
        end
    endtask

    task check;
        input cond;
        input [255:0] msg;
        begin
            if (!cond) begin
                $display("FAIL: %0s", msg);
                fails = fails + 1;
            end else begin
                $display("PASS: %0s", msg);
            end
        end
    endtask

    initial begin
        clk               = 1'b0;
        rst               = 1'b1;
        scan_start        = 1'b0;
        load_start        = 1'b0;
        sd_init_done      = 1'b0;
        scan_start_sector = 32'd0;
        scan_max_sector   = 32'd0;
        scan_target_count = 3'd0;
        load_sector       = 32'd0;
        scenario          = SCEN_VALID;
        withhold_response = 1'b0;
        skip_valid        = 1'b0;
        skip_offset       = 16'd0;
        exp_width         = BMP_W[15:0];
        exp_height        = BMP_H[15:0];
        fails             = 0;
        pixel_writes      = 0;
        seen_load_error   = 1'b0;
        captured_error    = ERR_NONE;

        // 1. Scan a valid BMP at sector 0.
        reset_dut();
        scenario = SCEN_VALID;
        start_scan(32'd0, 32'd16, 3'd1);
        wait_scan_done();
        check(scan_found_sector == 32'd0, "valid scan finds sector 0");
        check(scan_found_total == 3'd1, "valid scan reports one image");

        // 2. Load a valid BMP and verify all 8 pixels are written.
        reset_dut();
        scenario = SCEN_VALID;
        start_load(32'd0);
        wait_load_done();
        check(!seen_load_error, "valid load has no error");
        check(pixel_writes == 8, "valid load writes 8 pixels");

        // 3. Bad DIB header must be rejected.
        reset_dut();
        scenario = SCEN_BAD_DIB;
        start_load(32'd0);
        wait_load_done();
        check(seen_load_error && (captured_error == ERR_HEADER), "bad DIB reports ERR_HEADER");

        // 4. Bad planes field must be rejected.
        reset_dut();
        scenario = SCEN_BAD_PLANES;
        start_load(32'd0);
        wait_load_done();
        check(seen_load_error && (captured_error == ERR_HEADER), "bad planes reports ERR_HEADER");

        // 5. file_len smaller than pixel payload must be rejected.
        reset_dut();
        scenario = SCEN_BAD_FILELEN;
        start_load(32'd0);
        wait_load_done();
        check(seen_load_error && (captured_error == ERR_HEADER), "short file_len reports ERR_HEADER");

        // 6. A completed frame with fewer pixels than expected must be
        //    reported as truncated.  The expected dimensions are widened
        //    only after the header has been accepted so that this focused
        //    test exercises the pixel-completeness check itself.
        reset_dut();
        scenario = SCEN_TRUNCATED;
        start_load(32'd0);
        while (state_code != 4'd4)
            @(posedge clk);
        exp_height = BMP_H[15:0] + 16'd1;
        wait_load_done();
        check(seen_load_error && (captured_error == ERR_TRUNCATED), "short pixel stream reports ERR_TRUNCATED");

        // 7. A bad BMP with a valid signature and file_len=600 is skipped by 2 sectors.
        reset_dut();
        scenario = SCEN_FASTSKIP;
        start_scan(32'd0, 32'd16, 3'd1);
        wait_scan_done();
        check(scan_found_sector == 32'd2, "bad BMP fast-skip lands on sector 2");
        check(scan_found_total == 3'd1, "fast-skip finds the valid image");

        // 8. A withheld SD response must raise ERR_TIMEOUT.
        reset_dut();
        scenario          = SCEN_TIMEOUT;
        withhold_response = 1'b1;
        start_load(32'd0);
        wait_load_done();
        check(seen_load_error && (captured_error == ERR_TIMEOUT), "withheld SD response reports ERR_TIMEOUT");

        // 9. Scan timeout must also pulse load_error with ERR_TIMEOUT.
        reset_dut();
        scenario          = SCEN_TIMEOUT;
        withhold_response = 1'b1;
        start_scan(32'd0, 32'd16, 3'd1);
        repeat (20000) @(posedge clk);
        check(seen_load_error && (captured_error == ERR_TIMEOUT), "scan timeout reports ERR_TIMEOUT");

        // 10. A long multi-sector scan must not be killed by the per-operation
        //     timeout.  The scan spends >TIMEOUT_CYCLES before reaching the
        //     target sector; the fix resets the timer after every sector.
        reset_dut();
        scenario = SCEN_LONG_SCAN;
        start_scan(32'd0, 32'd100, 3'd1);
        wait_scan_done();
        check((scan_found_total == 3'd1) && !seen_load_error,
              "long multi-sector scan is not falsely timed out");

        if (fails == 0)
            $display("PASS: bmp_read stability tests completed");
        else
            $display("FAIL: bmp_read stability tests had %0d failure(s)", fails);
        $finish;
    end

endmodule

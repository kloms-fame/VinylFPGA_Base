`timescale 1ns/1ps
// 定向验证 S7-02 的 sd_sector_adapter 扇区事务看门狗：
// 底层 SD 控制器持续不应答（无 data_valid、无 end）时，adapter 必须在
// SECTOR_TIMEOUT_CYCLES 到期后主动释放 busy、返回 Err-05，并给出单拍
// sector_done 脉冲，交由 media_supervisor 复位恢复。
module tb_sd_sector_adapter_timeout;
    localparam integer TMO = 100; // 加速超时，便于仿真

    reg clk = 0;
    reg rst_n = 0;
    reg sector_req = 0;
    reg [31:0] sector_lba = 32'hBEEF;
    wire sector_busy;
    wire sector_valid;
    wire [7:0] sector_byte;
    wire [8:0] sector_byte_index;
    wire sector_done;
    wire [7:0] sector_error;
    wire sd_sec_read;
    wire [31:0] sd_sec_read_addr;
    reg sd_sec_read_data_valid = 0;
    reg [7:0] sd_sec_read_data = 0;
    reg sd_sec_read_end = 0;

    integer errors = 0;
    integer done_pulses = 0;
    integer t;

    sd_sector_adapter #(
        .SECTOR_TIMEOUT_CYCLES (TMO)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .sector_req(sector_req), .sector_lba(sector_lba),
        .sector_busy(sector_busy), .sector_valid(sector_valid),
        .sector_byte(sector_byte), .sector_byte_index(sector_byte_index),
        .sector_done(sector_done), .sector_error(sector_error),
        .sd_sec_read(sd_sec_read), .sd_sec_read_addr(sd_sec_read_addr),
        .sd_sec_read_data_valid(sd_sec_read_data_valid),
        .sd_sec_read_data(sd_sec_read_data), .sd_sec_read_end(sd_sec_read_end)
    );

    always #5 clk = ~clk;

    // 统计 sector_done 脉冲数，确认超时只产生一次单拍 done。
    always @(posedge clk) begin
        if (rst_n && sector_done)
            done_pulses = done_pulses + 1;
    end

    task check;
        input condition;
        input [255:0] name;
        begin
            if (!condition) begin
                $display("FAIL: %0s", name);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (2) @(posedge clk);
        sector_req = 1;
        wait (sd_sec_read == 1'b1);
        check(sd_sec_read_addr == 32'hBEEF, "LBA should be latched");
        check(sector_busy == 1'b1, "busy should assert");
        @(posedge clk);
        sector_req = 0;

        // 底层 SD 控制器完全不应答：一直不给 data_valid 也不给 end。
        // 等待超过 SECTOR_TIMEOUT_CYCLES，观察看门狗是否超时释放。
        for (t = 0; t < TMO + 8; t = t + 1)
            @(posedge clk);

        check(sector_busy == 1'b0, "busy should be released by watchdog");
        check(sd_sec_read == 1'b0, "sd_sec_read should deassert on timeout");
        check(sector_error == 8'h05, "sector_error should be Err-05");
        check(done_pulses == 1, "timeout should produce exactly one done pulse");

        // 超时后错误码 sticky，直到下一次成功事务才清 0；先验证 sticky。
        @(posedge clk);
        check(sector_error == 8'h05, "sector_error should remain sticky after timeout");

        if (errors == 0) $display("PASS: sd_sector_adapter timeout");
        else $display("FAIL: %0d errors", errors);
        $finish;
    end
endmodule

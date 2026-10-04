`timescale 1ns/1ps
module tb_sd_sector_adapter;
    reg clk = 0;
    reg rst_n = 0;
    reg sector_req = 0;
    reg [31:0] sector_lba = 32'h1234;
    wire sector_busy;
    wire sector_valid;
    wire [7:0] sector_byte;
    wire [8:0] sector_byte_index;
    wire sector_done;
    wire [7:0] sector_error;
    wire sd_sec_read;
    wire [31:0] sd_sec_read_addr;
    reg sd_sec_read_data_valid;
    reg [7:0] sd_sec_read_data;
    reg sd_sec_read_end;
    integer i;
    integer errors = 0;

    sd_sector_adapter dut (
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
        sd_sec_read_data_valid = 0;
        sd_sec_read_data = 0;
        sd_sec_read_end = 0;
        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (2) @(posedge clk);
        sector_req = 1;
        wait (sd_sec_read == 1'b1);
        check(sd_sec_read_addr == 32'h1234, "LBA should be latched");
        check(sector_busy == 1'b1, "busy should assert");
        @(posedge clk);
        for (i = 0; i < 512; i = i + 1) begin
            sd_sec_read_data_valid = 1;
            sd_sec_read_data = i[7:0];
            @(posedge clk);
        end
        sd_sec_read_data_valid = 0;
        sd_sec_read_end = 1;
        check(sector_byte_index == 9'd0, "index should wrap after 512");
        @(posedge clk);
        sd_sec_read_end = 0;
        sector_req = 0;
        repeat (2) @(posedge clk);
        check(sector_busy == 1'b0, "busy should clear");

        if (errors == 0) $display("PASS: sd sector adapter");
        else $display("FAIL: %0d errors", errors);
        $finish;
    end
endmodule

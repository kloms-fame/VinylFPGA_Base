`timescale 1ns/1ps
module tb_fat32_file_streamer;
    reg clk = 0;
    reg rst_n = 0;
    reg file_start = 0;
    reg [31:0] first_cluster = 5;
    reg [31:0] file_size = 1536;
    reg [7:0] sectors_per_cluster = 1;
    reg [31:0] fat_start_lba = 10;
    reg [31:0] data_start_lba = 30;
    reg [31:0] max_cluster = 32;
    wire file_busy;
    wire file_done;
    wire file_valid;
    wire [7:0] file_byte;
    wire [31:0] file_byte_offset;
    wire [7:0] fs_error;
    wire sector_req;
    wire [31:0] sector_lba;
    wire sector_busy;
    wire sector_valid;
    wire [7:0] sector_byte;
    wire [8:0] sector_byte_index;
    wire sector_done;
    wire [7:0] sector_error = 0;

    reg [7:0] mem [0:262143];
    reg [31:0] served_lba = 0;
    reg [9:0] byte_no = 0;
    reg reading = 0;
    integer errors = 0;
    integer got = 0;
    integer i;
    reg [7:0] expect;

    fat32_file_streamer dut (
        .clk(clk), .rst_n(rst_n), .file_start(file_start),
        .first_cluster(first_cluster), .file_size(file_size),
        .sectors_per_cluster(sectors_per_cluster),
        .fat_start_lba(fat_start_lba), .data_start_lba(data_start_lba),
        .max_cluster(max_cluster), .file_busy(file_busy),
        .file_done(file_done), .file_valid(file_valid), .file_byte(file_byte),
        .file_byte_offset(file_byte_offset), .fs_error(fs_error),
        .sector_req(sector_req), .sector_lba(sector_lba),
        .sector_busy(sector_busy), .sector_valid(sector_valid),
        .sector_byte(sector_byte), .sector_byte_index(sector_byte_index),
        .sector_done(sector_done), .sector_error(sector_error)
    );

    always #5 clk = ~clk;
    assign sector_busy = reading;
    assign sector_valid = reading && (byte_no < 512);
    assign sector_byte = mem[sector_lba * 512 + byte_no];
    assign sector_byte_index = byte_no;
    assign sector_done = reading && (byte_no == 512);

    always @(posedge clk) begin
        if (!reading && sector_req) begin
            reading <= 1;
            served_lba <= sector_lba;
            byte_no <= 0;
        end else if (reading) begin
            if (byte_no == 512)
                reading <= 0;
            else
                byte_no <= byte_no + 1;
        end
    end

    always @(posedge clk) begin
        if (file_valid) begin
            if (got < 512)
                expect = mem[(data_start_lba + 3)*512 + got];
            else if (got < 1024)
                expect = mem[(data_start_lba + 7)*512 + (got - 512)];
            else
                expect = mem[(data_start_lba + 1)*512 + (got - 1024)];
            if (file_byte !== expect) begin
                $display("FAIL byte[%0d]=%02x expected %02x", got, file_byte, expect);
                errors = errors + 1;
            end
            got = got + 1;
        end
    end

    initial begin
        for (i = 0; i < 262144; i = i + 1) mem[i] = 8'h00;

        // FAT 链：簇5->簇9->簇3->EOF。数据区每个簇 1 扇区。
        mem[fat_start_lba*512 + 5*4 + 0] = 9;
        mem[fat_start_lba*512 + 9*4 + 0] = 3;
        mem[fat_start_lba*512 + 3*4 + 0] = 8'hFF;
        mem[fat_start_lba*512 + 3*4 + 1] = 8'hFF;
        mem[fat_start_lba*512 + 3*4 + 2] = 8'hFF;
        mem[fat_start_lba*512 + 3*4 + 3] = 8'h0F;
        for (i = 0; i < 512; i = i + 1) begin
            mem[(data_start_lba+3)*512 + i] = i[7:0];
            mem[(data_start_lba+7)*512 + i] = i[7:0] ^ 8'h55;
            mem[(data_start_lba+1)*512 + i] = i[7:0] ^ 8'hAA;
        end

        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (5) @(posedge clk);
        @(posedge clk); file_start = 1;
        @(posedge clk); file_start = 0;
        wait (file_done == 1'b1);
        repeat (2) @(posedge clk);

        if (errors != 0 || got != 1536 || fs_error != 0) begin
            $display("FAIL: FAT32 streamer errors=%0d got=%0d fs_error=%02x",
                     errors, got, fs_error);
        end else begin
            $display("PASS: FAT32 fragmented FAT chain");
        end
        $finish;
    end

    initial begin
        #5_000_000;
        $display("FAIL: timeout");
        $finish;
    end
endmodule

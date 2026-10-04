`timescale 1ns/1ps
module tb_fat32_volume_scanner;
    reg clk = 0;
    reg rst_n = 0;
    reg scan_start = 0;
    wire scan_busy;
    wire scan_done;
    wire [7:0] fs_error;
    wire [31:0] partition_lba;
    wire [7:0] sectors_per_cluster;
    wire [31:0] fat_start_lba;
    wire [31:0] data_start_lba;
    wire [31:0] max_cluster;
    wire [3:0] resource_valid;
    wire [31:0] c0,c1,c2,c3,s0,s1,s2,s3;
    wire audio_valid;
    wire [31:0] audio_cluster;
    wire [31:0] audio_size;
    wire sector_req;
    wire [31:0] sector_lba;
    wire sector_busy;
    wire sector_valid;
    wire [7:0] sector_byte;
    wire [8:0] sector_byte_index;
    wire sector_done;
    wire [7:0] sector_error = 0;

    reg [7:0] mem [0:262143];
    integer i;
    integer errors = 0;
    integer read_index = 0;
    reg [31:0] served_lba = 0;
    reg [9:0] byte_no = 0;
    reg reading = 0;

    fat32_volume_scanner dut (
        .clk(clk), .rst_n(rst_n), .scan_start(scan_start),
        .scan_busy(scan_busy), .scan_done(scan_done), .fs_error(fs_error),
        .partition_lba(partition_lba), .sectors_per_cluster(sectors_per_cluster),
        .fat_start_lba(fat_start_lba), .data_start_lba(data_start_lba),
        .max_cluster(max_cluster), .resource_valid(resource_valid),
        .resource0_cluster(c0), .resource1_cluster(c1),
        .resource2_cluster(c2), .resource3_cluster(c3),
        .resource0_size(s0), .resource1_size(s1),
        .resource2_size(s2), .resource3_size(s3),
        .audio_valid(audio_valid), .audio_cluster(audio_cluster),
        .audio_size(audio_size),
        .sector_req(sector_req), .sector_lba(sector_lba),
        .sector_busy(sector_busy), .sector_valid(sector_valid),
        .sector_byte(sector_byte), .sector_byte_index(sector_byte_index),
        .sector_done(sector_done), .sector_error(sector_error)
    );

    always #5 clk = ~clk;

    // 模拟同步 RAM 的扇区读：req 维持高电平直到 done。
    assign sector_busy = reading;
    assign sector_valid = reading && (byte_no < 512);
    assign sector_byte = mem[sector_lba * 512 + byte_no];
    assign sector_byte_index = byte_no;
    assign sector_done = reading && (byte_no == 512);

    always @(posedge clk) begin
        if (!reading && sector_req) begin
            reading <= 1'b1;
            served_lba <= sector_lba;
            byte_no <= 0;
        end else if (reading) begin
            if (byte_no == 512)
                reading <= 0;
            else
                byte_no <= byte_no + 1;
        end
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
        for (i = 0; i < 262144; i = i + 1) mem[i] = 8'h00;

        // LBA0: 直接 FAT32 引导扇区（无 MBR）。
        mem[0*512 + 0] = 8'hEB;
        mem[0*512 + 11] = 8'h00; mem[0*512 + 12] = 8'h02; // 512 B/sector
        mem[0*512 + 13] = 8'd1;                            // 1 sector/cluster
        mem[0*512 + 14] = 8'd32; mem[0*512 + 15] = 8'h00; // reserved=32
        mem[0*512 + 16] = 8'd2;                            // FAT count=2
        mem[0*512 + 17] = 8'h00; mem[0*512 + 18] = 8'h00;
        mem[0*512 + 22] = 8'h00; mem[0*512 + 23] = 8'h00;
        mem[0*512 + 32] = 8'h00; mem[0*512 + 33] = 8'h04;
        mem[0*512 + 34] = 8'h00; mem[0*512 + 35] = 8'h00; // 1024 sectors
        mem[0*512 + 36] = 8'd1;  mem[0*512 + 37] = 8'h00;
        mem[0*512 + 38] = 8'h00; mem[0*512 + 39] = 8'h00; // fat=1
        mem[0*512 + 44] = 8'd2;  mem[0*512 + 45] = 8'h00;
        mem[0*512 + 510] = 8'h55; mem[0*512 + 511] = 8'hAA;

        // 根目录: LBA=32+2=34，簇2，目录项从偏移0开始。
        // PIC1.BMP: 起始簇5，大小=54+640*480*3 = 921654 = 0x000E1016
        mem[34*512 + 0]="P"; mem[34*512 + 1]="I"; mem[34*512 + 2]="C";
        mem[34*512 + 3]="1"; mem[34*512 + 4]=" "; mem[34*512 + 5]=" ";
        mem[34*512 + 6]=" "; mem[34*512 + 7]=" "; mem[34*512 + 8]="B";
        mem[34*512 + 9]="M"; mem[34*512 + 10]="P";
        mem[34*512 + 11]=8'h20;
        mem[34*512 + 20]=8'h00; mem[34*512 + 21]=8'h00;
        mem[34*512 + 26]=8'd5;  mem[34*512 + 27]=8'h00;
        mem[34*512 + 28]=8'h16; mem[34*512 + 29]=8'h10;
        mem[34*512 + 30]=8'h0E; mem[34*512 + 31]=8'h00;

        // PIC2~PIC4 各提供一个合法目录项。
        for (i = 0; i < 3; i = i + 1) begin
            mem[34*512 + (i+1)*32 + 0]="P";
            mem[34*512 + (i+1)*32 + 1]="I";
            mem[34*512 + (i+1)*32 + 2]="C";
            mem[34*512 + (i+1)*32 + 3]="2"+i;
            mem[34*512 + (i+1)*32 + 4]=" ";
            mem[34*512 + (i+1)*32 + 5]=" ";
            mem[34*512 + (i+1)*32 + 6]=" ";
            mem[34*512 + (i+1)*32 + 7]=" ";
            mem[34*512 + (i+1)*32 + 8]="B";
            mem[34*512 + (i+1)*32 + 9]="M";
            mem[34*512 + (i+1)*32 +10]="P";
            mem[34*512 + (i+1)*32 +11]=8'h20;
            mem[34*512 + (i+1)*32 +26]=(6+i);
            mem[34*512 + (i+1)*32 +28]=8'h16;
            mem[34*512 + (i+1)*32 +29]=8'h10;
            mem[34*512 + (i+1)*32 +30]=8'h0E;
        end

        // AUDIO.PCM: 根目录第5个目录项，验证第十一讲短文件名和元数据。
        mem[34*512 + 4*32 + 0]="A";
        mem[34*512 + 4*32 + 1]="U";
        mem[34*512 + 4*32 + 2]="D";
        mem[34*512 + 4*32 + 3]="I";
        mem[34*512 + 4*32 + 4]="O";
        mem[34*512 + 4*32 + 5]=" ";
        mem[34*512 + 4*32 + 6]=" ";
        mem[34*512 + 4*32 + 7]=" ";
        mem[34*512 + 4*32 + 8]="P";
        mem[34*512 + 4*32 + 9]="C";
        mem[34*512 + 4*32 +10]="M";
        mem[34*512 + 4*32 +11]=8'h20;
        mem[34*512 + 4*32 +20]=8'h00;
        mem[34*512 + 4*32 +21]=8'h00;
        mem[34*512 + 4*32 +26]=8'd9;
        mem[34*512 + 4*32 +27]=8'h00;
        mem[34*512 + 4*32 +28]=8'h00;
        mem[34*512 + 4*32 +29]=8'h04;
        mem[34*512 + 4*32 +30]=8'h00;
        mem[34*512 + 4*32 +31]=8'h00;

        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (5) @(posedge clk);
        @(posedge clk); scan_start = 1;
        @(posedge clk); scan_start = 0;
        wait (scan_done == 1'b1);
        repeat (3) @(posedge clk);

        check(fs_error == 8'h00, "fs_error should be 0");
        check(resource_valid == 4'hf, "all four PIC files should be found");
        check(c0 == 5 && c1 == 6 && c2 == 7 && c3 == 8,
              "directory clusters should match");
        check(s0 == 32'h000E1016, "PIC1 size should match");
        check(audio_valid, "AUDIO.PCM should be found");
        check(audio_cluster == 9, "AUDIO.PCM cluster should match");
        check(audio_size == 32'h00000400, "AUDIO.PCM size should match");
        check(fat_start_lba == 32 && data_start_lba == 34,
              "FAT/data layout should match");

        if (errors == 0) $display("PASS: FAT32 volume scanner");
        else $display("FAIL: %0d errors", errors);
        $finish;
    end

    initial begin
        #5_000_000;
        $display("FAIL: timeout");
        $finish;
    end
endmodule

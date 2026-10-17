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
    wire index_valid;
    wire [31:0] index_cluster;
    wire [31:0] index_size;
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
        .index_valid(index_valid), .index_cluster(index_cluster),
        .index_size(index_size),
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

    task write_directory_entry;
        input integer slot;
        input [87:0] short_name;
        input [7:0] attributes;
        input [31:0] first_cluster;
        input [31:0] file_bytes;
        integer base;
        integer n;
        begin
            base = 42*512 + slot*32;
            for (n = 0; n < 11; n = n + 1)
                mem[base+n] = short_name[87-(n*8) -: 8];
            mem[base+11] = attributes;
            mem[base+20] = first_cluster[16 +: 8];
            mem[base+21] = first_cluster[24 +: 8];
            mem[base+26] = first_cluster[0 +: 8];
            mem[base+27] = first_cluster[8 +: 8];
            mem[base+28] = file_bytes[0 +: 8];
            mem[base+29] = file_bytes[8 +: 8];
            mem[base+30] = file_bytes[16 +: 8];
            mem[base+31] = file_bytes[24 +: 8];
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

        if (errors == 0) $display("PASS: FAT32 volume scanner, direct boot sector");
        else $display("FAIL: %0d errors", errors);

        // 第二轮扫描覆盖 MBR 分区偏移，BPB 与根目录布局沿用同一份介质。
        for (i = 0; i < 512; i = i + 1) begin
            mem[8*512 + i] = mem[i];
            mem[42*512 + i] = mem[34*512 + i];
            mem[i] = 8'h00;
        end
        mem[0] = 8'hEB; // MBR boot code may also begin with a jump opcode.
        mem[446] = 8'h80; // bootable partition entry
        mem[450] = 8'h0B;
        mem[454] = 8'd8; mem[455] = 0; mem[456] = 0; mem[457] = 0;
        mem[458] = 0; mem[459] = 8'h10; mem[460] = 0; mem[461] = 0;
        mem[510] = 8'h55; mem[511] = 8'hAA;

        @(negedge clk); scan_start = 1;
        @(negedge clk); scan_start = 0;
        wait (scan_done == 1'b1);
        repeat (3) @(posedge clk);

        check(fs_error == 8'h00, "MBR scan should succeed");
        check(partition_lba == 8, "MBR partition start should be decoded");
        check(fat_start_lba == 40 && data_start_lba == 42,
              "partition-relative FAT/data layout should match");
        check(resource_valid == 4'hf && audio_valid,
              "MBR scan should find image and audio directory entries");
        if (errors == 0) $display("PASS: FAT32 volume scanner, MBR partition");
        else $display("FAIL: %0d errors", errors);

        // Look-alike names must not pass when deleted, long-name, directory,
        // or a one-byte filename mismatch is present. A valid INDEX.BIN lets
        // the scan finish while proving none of those entries set resources.
        for (i = 0; i < 512; i = i + 1) mem[42*512 + i] = 8'h00;
        write_directory_entry(0, "PIC1    BMP", 8'h20, 32'd11, 32'd111);
        mem[42*512 + 0] = 8'he5;
        write_directory_entry(1, "PIC2    BMP", 8'h0f, 32'd12, 32'd112);
        write_directory_entry(2, "PIC3    BMP", 8'h10, 32'd13, 32'd113);
        write_directory_entry(3, "AUDIO   PCM", 8'h0f, 32'd14, 32'd114);
        write_directory_entry(4, "INDEX   BIN", 8'h10, 32'd15, 32'd115);
        write_directory_entry(5, "PIC1    BMZ", 8'h20, 32'd16, 32'd116);
        write_directory_entry(6, "AUDIO   PCN", 8'h20, 32'd17, 32'd117);
        write_directory_entry(7, "INDEX   BIQ", 8'h20, 32'd18, 32'd118);
        write_directory_entry(8, "INDEX   BIN", 8'h20, 32'd20, 32'd1234);

        @(negedge clk); scan_start = 1;
        @(negedge clk); scan_start = 0;
        wait (scan_done == 1'b1);
        repeat (3) @(posedge clk);
        check(fs_error == 8'h00, "look-alike directory entries should not fail scan");
        check(resource_valid == 0 && !audio_valid,
              "deleted, wrong-attribute, and near-match files must stay invalid");
        check(index_valid && index_cluster == 20 && index_size == 1234,
              "only the exact INDEX.BIN entry should be accepted");
        if (errors == 0) $display("PASS: FAT32 volume scanner, directory match boundaries");
        else $display("FAIL: %0d errors", errors);

        // Early failure on a new scan must not expose results from the last scan.
        mem[510] = 8'h00; mem[511] = 8'h00;
        @(negedge clk); scan_start = 1;
        @(negedge clk); scan_start = 0;
        wait (scan_done == 1'b1);
        repeat (3) @(posedge clk);
        check(fs_error == 8'h20, "bad signature should fail the new scan");
        check(resource_valid == 0 && !audio_valid && !dut.index_valid,
              "early scan failure must clear previous valid flags");
        check(audio_cluster == 9 && audio_size == 32'h00000400 &&
              c0 == 5 && s0 == 32'h000E1016,
              "invalid result payload may retain prior values behind low valid flags");
        if (errors == 0) $display("PASS: FAT32 volume scanner, failure clears prior result");
        else $display("FAIL: %0d errors", errors);
        $finish;
    end

    initial begin
        #5_000_000;
        $display("FAIL: timeout");
        $finish;
    end
endmodule

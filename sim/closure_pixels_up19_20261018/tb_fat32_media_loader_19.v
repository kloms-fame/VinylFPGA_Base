`timescale 1ns/1ps
// 第七讲兼容层集成仿真：直接 FAT32 引导扇区 -> 根目录扫描 ->
// PIC1.BMP 文件流 -> BMP 头校验 -> 2x2 RGB 像素输出。
module tb_fat32_media_loader;
    localparam integer FILE_SIZE = 54 + 2*2*3;

    reg clk = 0;
    reg rst = 1;
    reg scan_start = 0;
    reg load_start = 0;
    reg [1:0] load_index = 0;
    reg sd_init_done = 0;
    reg write_req_ack = 0;

    wire ready;
    wire scan_done;
    wire scan_found_valid;
    wire [1:0] scan_found_index;
    wire scan_found_total;
    wire [3:0] state_code;
    wire [3:0] bmp_error;
    wire load_error;
    wire write_req;
    wire sd_sec_read;
    wire [31:0] sd_sec_read_addr;
    reg  [7:0] sd_sec_read_data = 0;
    reg  sd_sec_read_data_valid = 0;
    reg  sd_sec_read_end = 0;
    wire bmp_data_wr_en;
    wire [23:0] bmp_data;
    wire        audio_file_valid;
    wire [31:0] audio_start_lba;
    wire [31:0] audio_total_sectors;
    wire [31:0] audio_size_bytes;
    wire        audio_sec_busy;
    wire        audio_sec_valid;
    wire [7:0]  audio_sec_byte;
    wire [8:0]  audio_sec_byte_index;
    wire        audio_sec_done;
    wire [7:0]  audio_sec_error;

    reg [7:0] mem [0:262143];
    reg [31:0] served_lba = 0;
    reg [9:0] byte_no = 0;
    reg reading = 0;
    integer i;
    integer errors = 0;
    integer found_count = 0;
    integer pixel_count = 0;
    reg [23:0] expected_pixel [0:3];

    fat32_media_loader #(.PIXEL_COUNT_BITS(19)) dut (
        .clk(clk), .rst(rst), .ready(ready),
        .scan_start(scan_start), .scan_done(scan_done),
        .scan_found_valid(scan_found_valid),
        .scan_found_index(scan_found_index),
        .scan_found_total(scan_found_total),
        .load_start(load_start), .load_index(load_index),
        .sd_init_done(sd_init_done), .state_code(state_code),
        .bmp_width(16'd2), .bmp_height(16'd2),
        .bmp_error(bmp_error), .load_error(load_error),
        .write_req(write_req), .write_req_ack(write_req_ack),
        .sd_sec_read(sd_sec_read), .sd_sec_read_addr(sd_sec_read_addr),
        .sd_sec_read_data(sd_sec_read_data),
        .sd_sec_read_data_valid(sd_sec_read_data_valid),
        .sd_sec_read_end(sd_sec_read_end),
        .bmp_data_wr_en(bmp_data_wr_en), .bmp_data(bmp_data),
        .audio_file_valid(audio_file_valid),
        .audio_start_lba(audio_start_lba),
        .audio_total_sectors(audio_total_sectors),
        .audio_size_bytes(audio_size_bytes),
        .audio_sec_req(1'b0), .audio_sec_lba(32'd0),
        .audio_sec_busy(audio_sec_busy),
        .audio_sec_valid(audio_sec_valid),
        .audio_sec_byte(audio_sec_byte),
        .audio_sec_byte_index(audio_sec_byte_index),
        .audio_sec_done(audio_sec_done),
        .audio_sec_error(audio_sec_error)
    );

    always #5 clk = ~clk;

    // 模拟 SD 电平请求：地址变化只发生一次，读完整扇区后 end 一拍。
    always @(posedge clk) begin
        sd_sec_read_end <= 1'b0;
        sd_sec_read_data_valid <= 1'b0;
        if (!reading && sd_sec_read && !sd_sec_read_end) begin
            reading <= 1'b1;
            served_lba <= sd_sec_read_addr;
            byte_no <= 0;
        end else if (reading) begin
            if (byte_no < 512) begin
                sd_sec_read_data <= mem[served_lba*512 + byte_no];
                sd_sec_read_data_valid <= 1'b1;
                byte_no <= byte_no + 1;
            end else begin
                sd_sec_read_end <= 1'b1;
                reading <= 1'b0;
                byte_no <= 0;
            end
        end
    end

    always @(posedge clk) begin
        if (write_req && !write_req_ack)
            write_req_ack <= 1'b1;
        else
            write_req_ack <= 1'b0;
    end

    always @(posedge clk) begin
        if (scan_found_valid)
            found_count = found_count + 1;

        if (bmp_data_wr_en) begin
            if (pixel_count < 4 && bmp_data !== expected_pixel[pixel_count]) begin
                $display("FAIL pixel[%0d]=%06x expected %06x",
                         pixel_count, bmp_data, expected_pixel[pixel_count]);
                errors = errors + 1;
            end
            pixel_count = pixel_count + 1;
        end
    end

    initial begin
        for (i = 0; i < 262144; i = i + 1)
            mem[i] = 8'h00;

        // LBA0 直接 FAT32 引导扇区。
        mem[0] = 8'hEB;
        mem[11] = 8'h00; mem[12] = 8'h02;
        mem[13] = 8'd1;
        mem[14] = 8'd32; mem[15] = 8'h00;
        mem[16] = 8'd1;
        mem[32] = 8'h00; mem[33] = 8'h04;
        mem[34] = 8'h00; mem[35] = 8'h00;
        mem[36] = 8'd1; mem[37] = 8'h00;
        mem[44] = 8'd2; mem[45] = 8'h00;
        mem[510] = 8'h55; mem[511] = 8'hAA;

        // 根目录第一簇（簇2，LBA=33）内含 PIC1.BMP，起始簇5。
        mem[33*512 + 0] = "P";
        mem[33*512 + 1] = "I";
        mem[33*512 + 2] = "C";
        mem[33*512 + 3] = "1";
        mem[33*512 + 4] = " ";
        mem[33*512 + 5] = " ";
        mem[33*512 + 6] = " ";
        mem[33*512 + 7] = " ";
        mem[33*512 + 8] = "B";
        mem[33*512 + 9] = "M";
        mem[33*512 +10] = "P";
        mem[33*512 +11] = 8'h20;
        mem[33*512 +26] = 8'd5;
        mem[33*512 +28] = FILE_SIZE[7:0];
        mem[33*512 +29] = FILE_SIZE[15:8];
        mem[33*512 +30] = FILE_SIZE[23:16];
        mem[33*512 +31] = FILE_SIZE[31:24];

        // 第七讲扫描器要求 PIC1~PIC4 都出现；其余三张只验证扫描结果。
        for (i = 1; i < 4; i = i + 1) begin
            mem[33*512 + i*32 + 0] = "P";
            mem[33*512 + i*32 + 1] = "I";
            mem[33*512 + i*32 + 2] = "C";
            mem[33*512 + i*32 + 3] = "1" + i;
            mem[33*512 + i*32 + 4] = " ";
            mem[33*512 + i*32 + 5] = " ";
            mem[33*512 + i*32 + 6] = " ";
            mem[33*512 + i*32 + 7] = " ";
            mem[33*512 + i*32 + 8] = "B";
            mem[33*512 + i*32 + 9] = "M";
            mem[33*512 + i*32 +10] = "P";
            mem[33*512 + i*32 +11] = 8'h20;
            mem[33*512 + i*32 +26] = 8'd5 + i;
            mem[33*512 + i*32 +28] = FILE_SIZE[7:0];
            mem[33*512 + i*32 +29] = FILE_SIZE[15:8];
            mem[33*512 + i*32 +30] = FILE_SIZE[23:16];
            mem[33*512 + i*32 +31] = FILE_SIZE[31:24];
        end

        // AUDIO.PCM: 根目录第5个目录项，只验证元数据，不触发音频读取。
        mem[33*512 + 4*32 + 0] = "A";
        mem[33*512 + 4*32 + 1] = "U";
        mem[33*512 + 4*32 + 2] = "D";
        mem[33*512 + 4*32 + 3] = "I";
        mem[33*512 + 4*32 + 4] = "O";
        mem[33*512 + 4*32 + 5] = " ";
        mem[33*512 + 4*32 + 6] = " ";
        mem[33*512 + 4*32 + 7] = " ";
        mem[33*512 + 4*32 + 8] = "P";
        mem[33*512 + 4*32 + 9] = "C";
        mem[33*512 + 4*32 +10] = "M";
        mem[33*512 + 4*32 +11] = 8'h20;
        mem[33*512 + 4*32 +26] = 8'd9;
        mem[33*512 + 4*32 +27] = 8'h00;
        mem[33*512 + 4*32 +28] = 8'h00;
        mem[33*512 + 4*32 +29] = 8'h04;
        mem[33*512 + 4*32 +30] = 8'h00;
        mem[33*512 + 4*32 +31] = 8'h00;

        // FAT 项：簇5 -> EOF。
        mem[32*512 + 5*4 + 0] = 8'hFF;
        mem[32*512 + 5*4 + 1] = 8'hFF;
        mem[32*512 + 5*4 + 2] = 8'hFF;
        mem[32*512 + 5*4 + 3] = 8'h0F;

        // BMP 头：2x2、24bit、54 字节数据偏移。
        mem[(33 + (5-2))*512 + 0] = "B";
        mem[(33 + (5-2))*512 + 1] = "M";
        mem[(33 + (5-2))*512 + 2] = FILE_SIZE[7:0];
        mem[(33 + (5-2))*512 + 3] = FILE_SIZE[15:8];
        mem[(33 + (5-2))*512 + 4] = FILE_SIZE[23:16];
        mem[(33 + (5-2))*512 + 5] = FILE_SIZE[31:24];
        mem[(33 + (5-2))*512 +10] = 8'd54;
        mem[(33 + (5-2))*512 +14] = 8'd40;
        mem[(33 + (5-2))*512 +18] = 8'd2;
        mem[(33 + (5-2))*512 +22] = 8'd2;
        mem[(33 + (5-2))*512 +26] = 8'd1;
        mem[(33 + (5-2))*512 +28] = 8'd24;

        // 每像素 BGR -> 输出 RGB 高 24bit。
        mem[(33 + (5-2))*512 +54] = 8'h11;
        mem[(33 + (5-2))*512 +55] = 8'h22;
        mem[(33 + (5-2))*512 +56] = 8'h33;
        expected_pixel[0] = 24'h332211;
        mem[(33 + (5-2))*512 +57] = 8'h44;
        mem[(33 + (5-2))*512 +58] = 8'h55;
        mem[(33 + (5-2))*512 +59] = 8'h66;
        expected_pixel[1] = 24'h665544;
        mem[(33 + (5-2))*512 +60] = 8'h77;
        mem[(33 + (5-2))*512 +61] = 8'h88;
        mem[(33 + (5-2))*512 +62] = 8'h99;
        expected_pixel[2] = 24'h998877;
        mem[(33 + (5-2))*512 +63] = 8'hAA;
        mem[(33 + (5-2))*512 +64] = 8'hBB;
        mem[(33 + (5-2))*512 +65] = 8'hCC;
        expected_pixel[3] = 24'hCCBBAA;

        repeat (5) @(posedge clk);
        rst = 0;
        sd_init_done = 1;
        repeat (5) @(posedge clk);

        @(posedge clk); scan_start = 1;
        @(posedge clk); scan_start = 0;
        wait (scan_done == 1'b1);
        repeat (3) @(posedge clk);
        if (found_count != 4) begin
            $display("FAIL scan found_count=%0d fs_error=%02x scan_valid=%b",
                     found_count, dut.u_volume_scanner.fs_error,
                     dut.u_volume_scanner.resource_valid);
            $display("      root_lba=%0d partition_lba=%0d data_lba=%0d",
                     dut.u_volume_scanner.sector_lba,
                     dut.u_volume_scanner.partition_lba,
                     dut.u_volume_scanner.data_start_lba);
            errors = errors + 1;
        end

        if (!audio_file_valid || audio_start_lba != 40 ||
            audio_total_sectors != 2) begin
            $display("FAIL audio metadata valid=%b start_lba=%0d sectors=%0d",
                     audio_file_valid, audio_start_lba, audio_total_sectors);
            errors = errors + 1;
        end

        @(posedge clk); load_start = 1;
        @(posedge clk); load_start = 0;
        wait (load_error || (pixel_count == 4));
        repeat (20) @(posedge clk);

        if (load_error || bmp_error != 0) begin
            $display("FAIL loader load_error=%0d bmp_error=%0d",
                     load_error, bmp_error);
            errors = errors + 1;
        end
        if (pixel_count != 4) begin
            $display("FAIL pixel_count=%0d", pixel_count);
            errors = errors + 1;
        end

        // 扫描完成后 scan_done 必须保持有效，否则上层 KEY1/KEY2 和自动轮播
        // 调度条件会在首图提交后永久失效。
        if (!scan_done) begin
            $display("FAIL scan_done dropped after first image commit");
            errors = errors + 1;
        end

        // 首图完成后再次请求加载，验证兼容层没有在首次加载后锁死。
        pixel_count = 0;
        load_index = 2'd0;
        @(posedge clk); load_start = 1;
        @(posedge clk); load_start = 0;
        wait (load_error || (pixel_count == 4));
        repeat (20) @(posedge clk);

        if (load_error || bmp_error != 0) begin
            $display("FAIL replay loader load_error=%0d bmp_error=%0d",
                     load_error, bmp_error);
            errors = errors + 1;
        end
        if (pixel_count != 4) begin
            $display("FAIL replay pixel_count=%0d", pixel_count);
            errors = errors + 1;
        end

        // A failed rescan may leave the scanner's old payload behind its low
        // valid flags, but the media-loader outputs must not publish that data.
        mem[510] = 8'h00;
        mem[511] = 8'h00;
        wait (ready);
        @(negedge clk); scan_start = 1;
        @(negedge clk); scan_start = 0;
        wait (scan_done == 1'b1);
        repeat (3) @(posedge clk);
        if (dut.u_volume_scanner.fs_error != 8'h20 || audio_file_valid ||
            audio_start_lba != 0 || audio_total_sectors != 0 ||
            audio_size_bytes != 0) begin
            $display("FAIL failed rescan published stale audio metadata: error=%02x valid=%b lba=%0d sectors=%0d size=%0d",
                     dut.u_volume_scanner.fs_error, audio_file_valid,
                     audio_start_lba, audio_total_sectors, audio_size_bytes);
            errors = errors + 1;
        end

        if (errors == 0)
            $display("PASS: FAT32 media loader scan/load/pixel pipeline");
        else
            $display("FAIL: %0d errors", errors);
        $finish;
    end

    initial begin
        #50_000_000;
        $display("FAIL: timeout");
        $finish;
    end
endmodule


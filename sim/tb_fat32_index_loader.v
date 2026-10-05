`timescale 1ns/1ps

// =============================================================================
// S4 集成回归：扫描器 + INDEX.BIN 索引 + 取数（同一份 PC 工具产出的卡镜像）
//
// 用例：
//   1) 有 PIC1~4 + INDEX.BIN：走索引路径 -> 4 张、音频来自索引、碎片封面
//      仍能完整取出 64x4=256 像素且不报错
//   2) 同一镜像把索引条目改坏（CRC 错）：回退到 PIC1~4 旧路径，仍 4 张且可加载
//   3) 封面命名为 SONG1~4（没有 PIC1~4）：只有索引能提供 4 张 -> 证明封面
//      确实来自索引而不是旧 PIC 分支
//   4) 同一 SONG 镜像把索引改坏：无旧路径可退 -> 扫描结束且 0 张（可见错误、不挂死）
// =============================================================================
module tb_fat32_index_loader;
    localparam integer MEM_BYTES   = 32768;
    localparam integer INDEX_LBA_PIC  = 48;   // card.img      的 INDEX.BIN 物理 LBA
    localparam integer INDEX_LBA_SONG = 47;   // card_song.img 的 INDEX.BIN 物理 LBA

    reg clk = 1'b0;
    reg rst = 1'b1;
    reg scan_start = 1'b0;
    reg load_start = 1'b0;
    reg [1:0] load_index = 2'd0;
    reg use_song = 1'b0;

    wire        ready;
    wire        scan_done;
    wire        scan_found_valid;
    wire [1:0]  scan_found_index;
    wire        scan_found_total;
    wire [3:0]  state_code;
    wire [3:0]  bmp_error;
    wire        load_error;
    wire        write_req;
    wire        write_req_ack;
    wire        sd_sec_read;
    wire [31:0] sd_sec_read_addr;
    wire [7:0]  sd_sec_read_data;
    wire        sd_sec_read_data_valid;
    wire        sd_sec_read_end;
    wire        bmp_data_wr_en;
    wire [23:0] bmp_data;
    wire        audio_file_valid;
    wire [31:0] audio_start_lba;
    wire [31:0] audio_total_sectors;
    wire        audio_sec_busy, audio_sec_valid, audio_sec_done;
    wire [7:0]  audio_sec_byte, audio_sec_error;
    wire [8:0]  audio_sec_byte_index;

    reg [7:0] mem_pic  [0:MEM_BYTES-1];
    reg [7:0] mem_song [0:MEM_BYTES-1];

    integer errors = 0;
    integer found = 0;
    integer pix = 0;
    integer i;
    integer fd;
    reg [8*80:1] hex_path;
    integer tmo;

    fat32_media_loader dut (
        .clk                    (clk),
        .rst                    (rst),
        .ready                  (ready),
        .scan_start             (scan_start),
        .scan_done              (scan_done),
        .scan_found_valid       (scan_found_valid),
        .scan_found_index       (scan_found_index),
        .scan_found_total       (scan_found_total),
        .load_start             (load_start),
        .load_index             (load_index),
        .sd_init_done           (1'b1),
        .state_code             (state_code),
        .bmp_width              (16'd64),
        .bmp_height             (16'd4),
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
        .bmp_data               (bmp_data),
        .audio_file_valid       (audio_file_valid),
        .audio_start_lba        (audio_start_lba),
        .audio_total_sectors    (audio_total_sectors),
        .audio_sec_req          (1'b0),
        .audio_sec_lba          (32'd0),
        .audio_sec_busy         (audio_sec_busy),
        .audio_sec_valid        (audio_sec_valid),
        .audio_sec_byte         (audio_sec_byte),
        .audio_sec_byte_index   (audio_sec_byte_index),
        .audio_sec_done         (audio_sec_done),
        .audio_sec_error        (audio_sec_error)
    );

    assign write_req_ack = write_req;      // 简化握手：请求当拍即被接受

    always #5 clk = ~clk;

    // ---- 扇区读模型（同既有 FAT32 测试台的时序约定）----
    reg        reading = 1'b0;
    reg        armed   = 1'b1;   // sd_sec_read 是电平协议：必须等它拉低才接受下一次
    reg [9:0]  byte_no = 10'd0;  // 必须能表示 512，否则 end 永不触发
    reg [31:0] served_lba = 32'd0;

    wire [7:0] cur_byte = use_song ? mem_song[served_lba*512 + byte_no]
                                   : mem_pic [served_lba*512 + byte_no];

    assign sd_sec_read_data_valid = reading && (byte_no < 512);
    assign sd_sec_read_data       = cur_byte;
    assign sd_sec_read_end        = reading && (byte_no == 512);

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            reading <= 1'b0;
            armed <= 1'b1;
            byte_no <= 10'd0;
            served_lba <= 32'd0;
        end else begin
            if (!sd_sec_read)
                armed <= 1'b1;
            if (armed && !reading && sd_sec_read) begin
                reading <= 1'b1;
                armed <= 1'b0;
                served_lba <= sd_sec_read_addr;
                byte_no <= 10'd0;
            end else if (reading) begin
                if (byte_no == 512)
                    reading <= 1'b0;
                else
                    byte_no <= byte_no + 10'd1;
            end
        end
    end

    always @(posedge clk) begin
        if (!rst) begin
            if (scan_found_valid) found = found + 1;
            if (bmp_data_wr_en)   pix   = pix + 1;
        end
    end

    task check;
        input cond;
        input [8*56:1] name;
        begin
            if (!cond) begin
                $display("FAIL: %0s", name);
                errors = errors + 1;
            end
        end
    endtask

    // 复位并重新扫描，返回后统计量 found/pix 已清零
    task rescan;
        begin
            rst = 1'b1;
            repeat (4) @(posedge clk);
            rst = 1'b0;
            found = 0;
            pix = 0;
            repeat (4) @(posedge clk);
            @(negedge clk); scan_start = 1'b1;
            @(negedge clk); scan_start = 1'b0;
            tmo = 0;
            while (!scan_done && tmo < 200000) begin
                @(posedge clk);
                tmo = tmo + 1;
            end
            repeat (40) @(posedge clk);     // 等 found 脉冲与音频元数据流水完成
        end
    endtask

    task do_load;
        input [1:0] idx;
        begin
            pix = 0;
            @(negedge clk); load_index = idx; load_start = 1'b1;
            @(negedge clk); load_start = 1'b0;
            tmo = 0;
            while ((pix < 256) && (tmo < 400000)) begin
                @(posedge clk);
                tmo = tmo + 1;
            end
            repeat (40) @(posedge clk);
        end
    endtask

    initial begin
        for (i = 0; i < MEM_BYTES; i = i + 1) begin
            mem_pic[i]  = 8'h00;
            mem_song[i] = 8'h00;
        end

        hex_path = "sim/s4_fixture/card_mem.hex";
        fd = $fopen(hex_path, "r");
        if (fd == 0) begin
            hex_path = "../sim/s4_fixture/card_mem.hex";
            fd = $fopen(hex_path, "r");
        end
        if (fd == 0) begin
            hex_path = "s4_fixture/card_mem.hex";
            fd = $fopen(hex_path, "r");
        end
        if (fd == 0) begin
            hex_path = "../../sim/s4_fixture/card_mem.hex";
            fd = $fopen(hex_path, "r");
        end
        if (fd == 0) begin
            $display("FAIL: 找不到 card_mem.hex 夹具");
            $finish;
        end
        $fclose(fd);
        $readmemh(hex_path, mem_pic);

        hex_path = "sim/s4_fixture/card_song_mem.hex";
        fd = $fopen(hex_path, "r");
        if (fd == 0) begin
            hex_path = "../sim/s4_fixture/card_song_mem.hex";
            fd = $fopen(hex_path, "r");
        end
        if (fd == 0) begin
            hex_path = "s4_fixture/card_song_mem.hex";
            fd = $fopen(hex_path, "r");
        end
        if (fd == 0) begin
            hex_path = "../../sim/s4_fixture/card_song_mem.hex";
            fd = $fopen(hex_path, "r");
        end
        if (fd == 0) begin
            $display("FAIL: 找不到 card_song_mem.hex 夹具");
            $finish;
        end
        $fclose(fd);
        $readmemh(hex_path, mem_song);

        // ---- 用例 1：PIC1~4 + INDEX.BIN，走索引 ----
        use_song = 1'b0;
        rescan;
        check(scan_done === 1'b1, "用例1 扫描完成");
        check(found == 4, "用例1 索引给出 4 张封面");
        check(audio_file_valid === 1'b1, "用例1 音频有效（来自索引）");
        check(audio_start_lba === 32'd44, "用例1 音频起始 LBA=44（索引条目）");
        check(audio_total_sectors === 32'd4, "用例1 音频扇区数=4");
        do_load(2'd0);
        check(pix == 256, "用例1 碎片封面取满 256 像素");
        check(load_error === 1'b0 && bmp_error === 4'd0, "用例1 无加载错误");

        // ---- 用例 2：索引条目被改坏 -> 回退旧 PIC 路径 ----
        mem_pic[INDEX_LBA_PIC*512 + 64 + 5] = mem_pic[INDEX_LBA_PIC*512 + 64 + 5] ^ 8'h01;
        use_song = 1'b0;
        rescan;
        check(found == 4, "用例2 索引 CRC 错 -> 回退 PIC1~4 仍 4 张");
        do_load(2'd0);
        check(pix == 256, "用例2 回退后仍能取满 256 像素");
        check(load_error === 1'b0, "用例2 回退后无加载错误");
        mem_pic[INDEX_LBA_PIC*512 + 64 + 5] = mem_pic[INDEX_LBA_PIC*512 + 64 + 5] ^ 8'h01;

        // ---- 用例 3：封面叫 SONG1~4（无 PIC），只有索引能供图 ----
        use_song = 1'b1;
        rescan;
        check(scan_done === 1'b1, "用例3 扫描完成");
        check(found == 4, "用例3 无 PIC 文件时索引仍提供 4 张");
        do_load(2'd0);
        check(pix == 256, "用例3 索引封面取满 256 像素");
        check(load_error === 1'b0, "用例3 无加载错误");

        // ---- 用例 4：SONG 镜像索引也坏 -> 无路可退，须可见报错且不挂死 ----
        mem_song[INDEX_LBA_SONG*512 + 64 + 5] = mem_song[INDEX_LBA_SONG*512 + 64 + 5] ^ 8'h01;
        use_song = 1'b1;
        rescan;
        check(scan_done === 1'b1, "用例4 坏索引仍结束扫描（不挂死）");
        check(found == 0, "用例4 无索引且无 PIC -> 0 张（错误可见）");

        if (errors == 0)
            $display("TEST_PASS fat32_index_loader_s4");
        else
            $display("FAIL: tb_fat32_index_loader errors=%0d", errors);
        $finish;
    end

    initial begin
        #200_000_000;
        $display("FAIL: tb_fat32_index_loader timeout");
        $finish;
    end
endmodule

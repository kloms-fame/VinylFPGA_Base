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
module tb_s7_media_lifecycle;
    localparam integer MEM_BYTES   = 32768;
    localparam integer INDEX_LBA_PIC  = 48;   // card.img      的 INDEX.BIN 物理 LBA
    localparam integer INDEX_LBA_SONG = 47;   // card_song.img 的 INDEX.BIN 物理 LBA

    reg clk = 1'b0;
    reg global_reset=1,card_present=1;
    wire media_reset_n,err_toggle,storage_done;
    wire rst=global_reset || !media_reset_n;
    wire [7:0] active_error,storage_error;
    reg scan_kicked=0;
    reg scan_start = 1'b0;
    reg load_start = 1'b0;
    reg [1:0] load_index = 2'd0;
    reg use_song = 1'b0;

    wire [7:0] media_error;
    wire [23:0] media_status;
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
    wire [31:0] audio_size_bytes;
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
        .storage_done(storage_done),.storage_error(storage_error),
        .media_error            (media_error),
        .media_status           (media_status),
        .scan_found_valid       (scan_found_valid),
        .scan_found_index       (scan_found_index),
        .scan_found_total       (scan_found_total),
        .load_start             (load_start),
        .load_index             (load_index),
        .sd_init_done           (1'b1),
        .state_code             (state_code),
        .bmp_width              (16'd64),
        .bmp_height             (16'd4),
        .song_sel               (2'd0),
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
        .audio_size_bytes       (audio_size_bytes),
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

    assign sd_sec_read_data_valid = card_present && reading && (byte_no < 512);
    assign sd_sec_read_data       = cur_byte;
    assign sd_sec_read_end        = card_present && reading && (byte_no == 512);

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

    media_supervisor #(.CLK_FREQ_HZ(2000),.MOUNT_TIMEOUT_MS(10000),
     .REMOUNT_COOLDOWN_MS(20),.RESET_PULSE_CYCLES(10)) supervisor(
     .clk(clk),.rst_n(!global_reset),.media_ready(scan_done && media_error==0 && found==4),
     .mount_error(media_error),.sector_done(storage_done),.sector_error(storage_error),
     .sector_busy(audio_sec_busy),.sd_rst_n(media_reset_n),.media_err_code(active_error),.media_err_toggle(err_toggle));
    defparam dut.u_sd_sector_adapter.SECTOR_TIMEOUT_CYCLES=2000;
    always @(posedge clk or posedge rst) begin
      if(rst) begin scan_kicked<=0;scan_start<=0;end
      else begin
       scan_start<=0;
       if(!scan_kicked && ready) begin scan_start<=1;scan_kicked<=1;end
      end
    end
    always @(posedge rst) begin found=0;pix=0;end
    task mounted;
     begin
      wait(scan_done && media_error==0 && found==4);
      repeat(40) @(negedge clk);
      if(active_error!=0 || !audio_file_valid) $fatal(1,"FAIL remount metadata/error");
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

        // Begin with a real CRC failure, then replace the bytes without soft reset.
        use_song=1;
        mem_song[INDEX_LBA_SONG*512+64+5]=mem_song[INDEX_LBA_SONG*512+64+5]^8'h01;
        repeat(5) @(negedge clk);global_reset=0;
        wait(active_error==8'h34);
        wait(!media_reset_n);
        mem_song[INDEX_LBA_SONG*512+64+5]=mem_song[INDEX_LBA_SONG*512+64+5]^8'h01;
        wait(media_reset_n); mounted();do_load(0);
        if(pix!=256 || load_error) $fatal(1,"FAIL recovered CRC cover load");
        // Remove during a genuine FAT32 cover transfer; timeout must reset/rescan.
        pix=0; @(negedge clk); load_start=1; @(negedge clk);load_start=0;
        wait(pix>=16);card_present=0;
        wait(!media_reset_n);if(active_error!=5)$fatal(1,"FAIL sector removal error");
        card_present=1;wait(media_reset_n);mounted();do_load(0);
        if(pix!=256 || load_error) $fatal(1,"FAIL recovered removal cover load");
        $display("PASS real FAT32 CRC-bad to good, removal mid-cover, timeout, rescan and reload without global reset");
        $finish;
    end

    initial begin
        #200_000_000;
        $display("FAIL: tb_s7_media_lifecycle timeout");
        $finish;
    end
endmodule

`timescale 1ns/1ps
// =============================================================================
// 第八讲四bank调度单元仿真
//
// 本仿真只验证 sd_card_bmp 的 bank 调度、预加载、按键/长按/轮播行为。
// fat32_media_loader 和 sd_card_top 用轻量 stub 代替，避免重复仿真整个
// FAT32/SD 控制器链路；真实第七讲 FAT32 仿真仍由原有 testbench 覆盖。
// =============================================================================
module tb_sd_card_bmp_fourbank;
    reg         clk = 1'b0;
    reg         rst = 1'b1;
    reg         sdr_init_done = 1'b0;
    reg         key_next = 1'b1;
    reg         next_event = 1'b0;
    reg prev_event=0;
    reg         select_req = 1'b0;
    reg  [1:0]  select_index = 2'd0;
    reg         key_auto = 1'b1;
    reg         write_finish_toggle = 1'b0;
    reg         write_req_ack = 1'b0;

    wire [3:0]  state_code;
    wire        display_valid;
    wire [1:0]  write_buf_idx;
    wire [1:0]  disp_buf_idx;
    wire        select_ack;
    wire        write_req;
    wire        write_en;
    wire [31:0] write_data;
    wire        sd_ncs;
    wire        sd_dclk;
    wire        sd_mosi;
    wire        sd_miso = 1'b0;
    wire        audio_file_valid;
    wire [31:0] audio_start_lba;
    wire [31:0] audio_total_sectors;
    wire [31:0] audio_size_bytes;
    wire        audio_play_enable;
    reg         audio_sec_req = 1'b0;
    reg  [31:0] audio_sec_lba = 32'd0;
    wire        audio_sec_busy;
    wire        audio_sec_valid;
    wire [7:0]  audio_sec_byte;
    wire [8:0]  audio_sec_byte_index;
    wire        audio_sec_done;
    wire [7:0]  audio_sec_error;

    reg [1:0]   load_banks [0:15];
    integer     load_start_count = 0;
    integer     errors = 0;
    integer     wait_count;
    reg         finish_toggled_for_load = 1'b0;
    reg         abort_before;

    sd_card_bmp #(
        .CLK_FREQ_HZ       (1000),
        .SCAN_START_SECTOR (32'd0),
        .SCAN_MAX_SECTOR   (32'd16),
        .SCAN_TARGET_COUNT (3'd4),


        .SD_READ_TIMEOUT_MS(500),
        .MAX_RETRIES       (0)
    ) dut (
        .clk                 (clk),
        .rst                 (rst),
        .sdr_init_done       (sdr_init_done),

        .next_event          (next_event),
        .prev_event          (prev_event),
        .select_req          (select_req),
        .select_index        (select_index),
        .select_ack          (select_ack),

        .state_code          (state_code),
        .bmp_width           (16'd2),
        .bmp_height          (16'd2),
        .song_sel            (2'd0),
        .display_valid       (display_valid),
        .write_finish_toggle (write_finish_toggle),
        .write_buf_idx       (write_buf_idx),
        .disp_buf_idx        (disp_buf_idx),
        .write_req           (write_req),
        .write_req_ack       (write_req_ack),
        .write_en            (write_en),
        .write_data          (write_data),
        .SD_nCS              (sd_ncs),
        .SD_DCLK             (sd_dclk),
        .SD_MOSI             (sd_mosi),
        .SD_MISO             (sd_miso),
        .audio_file_valid    (audio_file_valid),
        .audio_start_lba     (audio_start_lba),
        .audio_total_sectors (audio_total_sectors),
        .audio_size_bytes    (audio_size_bytes),
        .audio_play_enable   (audio_play_enable),
        .audio_sec_req       (audio_sec_req),
        .audio_sec_lba       (audio_sec_lba),
        .audio_sec_busy      (audio_sec_busy),
        .audio_sec_valid     (audio_sec_valid),
        .audio_sec_byte      (audio_sec_byte),
        .audio_sec_byte_index(audio_sec_byte_index),
        .audio_sec_done      (audio_sec_done),
        .audio_sec_error     (audio_sec_error)
    );

    always #5 clk = ~clk;

    // 记录每次加载启动时的目标bank。
    always @(posedge clk) begin
        if (dut.load_start_pulse) begin
            if (load_start_count < 16)
                load_banks[load_start_count] = dut.load_index;
            load_start_count = load_start_count + 1;
        end
    end

    // 给 stub 的写请求回一个单拍 ack。
    always @(posedge clk) begin
        write_req_ack <= 1'b0;
        if (write_req)
            write_req_ack <= 1'b1;
    end

    // stub 的 bmp_ready 有效后，向 DUT 发送一次写完成 toggle。
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            finish_toggled_for_load <= 1'b0;
            write_finish_toggle    <= 1'b0;
        end else if (dut.load_busy && dut.fat32_media_loader_m0.ready) begin
            if (!finish_toggled_for_load) begin
                write_finish_toggle    <= ~write_finish_toggle;
                finish_toggled_for_load <= 1'b1;
            end
        end else if (!dut.load_busy) begin
            finish_toggled_for_load <= 1'b0;
        end
    end

    task press_key1; begin pulse_next_event(); end endtask

    task pulse_next_event;
        begin
            @(negedge clk) next_event = 1'b1;
            @(negedge clk) next_event = 1'b0;
            repeat (30) @(posedge clk);
        end
    endtask

    task short_press_key2;
        begin
            @(negedge clk) key_auto = 1'b0;
            repeat (30) @(posedge clk);
            @(negedge clk) key_auto = 1'b1;
            repeat (30) @(posedge clk);
        end
    endtask

    task long_press_key2; begin
 @(negedge clk) prev_event=1;
 @(negedge clk) prev_event=0;
 repeat(30) @(posedge clk);
end endtask

    initial begin
        key_next = 1'b1;
        key_auto = 1'b1;
        repeat (8) @(posedge clk);
        rst = 1'b0;
        sdr_init_done = 1'b1;

        // 等待第一张图提交。
        for (wait_count = 0; wait_count < 20000 && !display_valid; wait_count = wait_count + 1)
            @(posedge clk);
        if (!display_valid) begin
            $display("FAIL: first image did not commit");
            errors = errors + 1;
        end

        // 等四个bank全部预加载完成。
        for (wait_count = 0; wait_count < 40000 && dut.image_ready != 4'b1111; wait_count = wait_count + 1)
            @(posedge clk);
        if (dut.image_ready != 4'b1111) begin
            $display("FAIL: image_ready=%b, expected 1111", dut.image_ready);
            errors = errors + 1;
        end

        // 第十一讲：图片预加载完成后，AUDIO.PCM 元数据有效时应放行 WAV。
        for (wait_count = 0;
             wait_count < 100 && !audio_play_enable;
             wait_count = wait_count + 1)
            @(posedge clk);
        if (!audio_play_enable) begin
            $display("FAIL: audio_play_enable not asserted after preload");
            errors = errors + 1;
        end
        if (audio_start_lba != 32'd100 || audio_total_sectors != 32'd2) begin
            $display("FAIL: audio metadata start=%0d sectors=%0d",
                     audio_start_lba, audio_total_sectors);
            errors = errors + 1;
        end

        if (load_start_count != 4) begin
            $display("FAIL: load_start_count=%0d, expected 4", load_start_count);
            errors = errors + 1;
        end
        if (load_banks[0] !== 2'd0 || load_banks[1] !== 2'd1 ||
            load_banks[2] !== 2'd2 || load_banks[3] !== 2'd3) begin
            $display("FAIL: preload bank order %0d %0d %0d %0d",
                     load_banks[0], load_banks[1], load_banks[2], load_banks[3]);
            errors = errors + 1;
        end
        if (write_buf_idx !== 2'd3 || disp_buf_idx !== 2'd0) begin
            $display("FAIL: after preload write_buf_idx=%0d disp_buf_idx=%0d",
                     write_buf_idx, disp_buf_idx);
            errors = errors + 1;
        end

        // KEY1：已加载bank之间切换，必须零重新加载。
        press_key1();
        if (disp_buf_idx !== 2'd1 || load_start_count != 4) begin
            $display("FAIL: KEY1 first switch disp=%0d load_count=%0d",
                     disp_buf_idx, load_start_count);
            errors = errors + 1;
        end
        press_key1();
        if (disp_buf_idx !== 2'd2 || load_start_count != 4) begin
            $display("FAIL: KEY1 second switch disp=%0d load_count=%0d",
                     disp_buf_idx, load_start_count);
            errors = errors + 1;
        end

        // 第十讲：转场提交脉冲走与KEY1相同的下一张仲裁路径。
        pulse_next_event();
        if (disp_buf_idx !== 2'd3 || load_start_count != 4) begin
            $display("FAIL: next_event switch disp=%0d load_count=%0d",
                     disp_buf_idx, load_start_count);
            errors = errors + 1;
        end

        // KEY2长按：上一张，应回到bank2。
        long_press_key2();
        if (disp_buf_idx !== 2'd2 || load_start_count != 4) begin
            $display("FAIL: KEY2 long switch disp=%0d load_count=%0d",
                     disp_buf_idx, load_start_count);
            errors = errors + 1;
        end

        // 第十五讲：快速选择已加载bank，不允许重新加载。
        @(negedge clk);
        select_index = 2'd0;
        select_req   = 1'b1;
        wait (select_ack === 1'b1);
        @(negedge clk);
        select_req = 1'b0;
        repeat (5) @(posedge clk);
        if (disp_buf_idx !== 2'd0 || load_start_count != 4) begin
            $display("FAIL: quick select disp=%0d load_count=%0d",
                     disp_buf_idx, load_start_count);
            errors = errors + 1;
        end

        // 再次选择同一bank时必须产生一次释放脉冲，供转场状态机退出。
        abort_before = dut.switch_abort_toggle;
        @(negedge clk);
        select_index = 2'd0;
        select_req   = 1'b1;
        wait (select_ack === 1'b1);
        // Real top drops the held request on the next rising edge after ack.
        @(posedge clk);
        @(negedge clk);
        select_req = 1'b0;
        repeat (5) @(posedge clk);
        if (dut.switch_abort_toggle == abort_before) begin
            $display("FAIL: same-bank quick select did not release transition");
            errors = errors + 1;
        end

        // Idle and retired physical-key stimuli must not advance a bank.
        short_press_key2();
        repeat (500) @(posedge clk);
        if (load_start_count != 4 || disp_buf_idx != 0) begin
            $display("FAIL retired auto path changed bank or reloaded");
            errors = errors + 1;
        end

        if (errors == 0)
            $display("PASS: four-bank scheduler preload/switch/next_event/prev_event/no-auto");
        else
            $display("FAIL: errors=%0d", errors);
        $finish;
    end

endmodule

// -----------------------------------------------------------------------------
// 轻量 FAT32 loader stub：扫描时报告4张图，加载时产生4个像素。
// -----------------------------------------------------------------------------
module fat32_media_loader (
    input  wire        clk,
    input  wire        rst,
    output wire storage_done, output wire [7:0] storage_error,
    output reg         ready,
    input  wire        scan_start,
    output reg         scan_done,
    output wire [23:0] media_status,
    output wire [7:0] media_error,
    output reg         scan_found_valid,
    output reg  [1:0]  scan_found_index,
    output reg         scan_found_total,
    input  wire        load_start,
    input  wire [1:0]  load_index,
    input  wire        sd_init_done,
    output wire [3:0]  state_code,
    input  wire [15:0] bmp_width,
    input  wire [15:0] bmp_height,
    input  wire [1:0]  song_sel,       // S5：曲目选择（stub 不参与行为，仅为端口对齐）
    output reg  [3:0]  bmp_error,
    output reg         load_error,
    output reg         write_req,
    input  wire        write_req_ack,
    output wire        sd_sec_read,
    output wire [31:0] sd_sec_read_addr,
    input  wire [7:0]  sd_sec_read_data,
    input  wire        sd_sec_read_data_valid,
    input  wire        sd_sec_read_end,
    output reg         bmp_data_wr_en,
    output reg  [23:0] bmp_data,
    output wire [63:0] mv_metadata,
    output wire [31:0] background_base_lba,
    output wire        background_art2_supported,
    output wire        audio_file_valid,
    output wire [31:0] audio_start_lba,
    output wire [31:0] audio_total_sectors,
    output wire [31:0] audio_size_bytes,
    input  wire        audio_sec_req,
    input  wire [31:0] audio_sec_lba,
    output wire        audio_sec_busy,
    output wire        audio_sec_valid,
    output wire [7:0]  audio_sec_byte,
    output wire [8:0]  audio_sec_byte_index,
    output wire        audio_sec_done,
    output wire [7:0]  audio_sec_error
);
    reg [2:0] scan_state;
    reg [1:0] scan_index;
    reg       loading;
    reg       streaming;
    reg [2:0] pixel_count;

    assign media_status = {scan_done, 3'b011, 4'hF, 16'd0};
    assign media_error = 8'd0;
    assign state_code = 4'd1;
    assign sd_sec_read = 1'b0;
    assign sd_sec_read_addr = 32'd0;
    assign background_base_lba = 32'd0;
    assign background_art2_supported = 1'b0;
    assign audio_file_valid = 1'b1;
    assign audio_start_lba = 32'd100;
    assign audio_total_sectors = 32'd2;
    assign audio_size_bytes = 32'd1024;
    assign audio_sec_busy = 1'b0;
    assign audio_sec_valid = 1'b0;
    assign audio_sec_byte = 8'd0;
    assign audio_sec_byte_index = 9'd0;
    assign audio_sec_done = 1'b0;
    assign audio_sec_error = 8'd0;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            ready            <= 1'b1;
            scan_done        <= 1'b0;
            scan_found_valid <= 1'b0;
            scan_found_index <= 2'd0;
            scan_found_total <= 1'b0;
            load_error       <= 1'b0;
            write_req        <= 1'b0;
            bmp_error        <= 4'd0;
            bmp_data_wr_en   <= 1'b0;
            bmp_data         <= 24'd0;
            scan_state       <= 3'd0;
            scan_index       <= 2'd0;
            loading          <= 1'b0;
            streaming        <= 1'b0;
            pixel_count      <= 3'd0;
        end else begin
            bmp_data_wr_en <= 1'b0;
            scan_found_valid <= 1'b0;
            scan_found_total <= 1'b0;

            if (scan_start) begin
                scan_state <= 3'd1;
                scan_done  <= 1'b0;
                scan_index <= 2'd0;
            end

            case (scan_state)
                3'd1: begin
                    scan_found_valid <= 1'b1;
                    scan_found_total <= 1'b1;
                    scan_found_index <= scan_index;
                    if (scan_index == 2'd3) begin
                        scan_state <= 3'd2;
                        scan_done  <= 1'b1;
                    end else begin
                        scan_index <= scan_index + 2'd1;
                    end
                end
                default: ;
            endcase

            if (load_start && !loading) begin
                loading     <= 1'b1;
                ready       <= 1'b0;
                write_req   <= 1'b1;
                pixel_count <= 3'd0;
            end

            if (loading && write_req && write_req_ack) begin
                write_req <= 1'b0;
                streaming <= 1'b1;
            end

            if (streaming) begin
                if (pixel_count < 3'd4) begin
                    bmp_data_wr_en <= 1'b1;
                    bmp_data <= {8'h10, 8'h20, 8'h30} + {21'd0, pixel_count};
                    pixel_count <= pixel_count + 3'd1;
                end else begin
                    streaming <= 1'b0;
                    loading   <= 1'b0;
                    ready     <= 1'b1;
                end
            end
        end
    end
endmodule

// -----------------------------------------------------------------------------
// SD 顶层 stub：四bank调度仿真不访问真实TF卡。
// -----------------------------------------------------------------------------
module sd_card_top #(
    parameter SPI_LOW_SPEED_DIV = 248,
    parameter SPI_HIGH_SPEED_DIV = 0
) (
    input  wire        clk,
    input  wire        rst,
    output wire        SD_nCS,
    output wire        SD_DCLK,
    output wire        SD_MOSI,
    input  wire        SD_MISO,
    output wire        sd_init_done,
    input  wire        sd_sec_read,
    input  wire [31:0] sd_sec_read_addr,
    output wire [7:0]  sd_sec_read_data,
    output wire        sd_sec_read_data_valid,
    output wire        sd_sec_read_end,
    input  wire        sd_sec_write,
    input  wire [31:0] sd_sec_write_addr,
    input  wire [7:0]  sd_sec_write_data,
    output wire        sd_sec_write_data_req,
    output wire        sd_sec_write_end
);
    assign SD_nCS = 1'b1;
    assign SD_DCLK = 1'b0;
    assign SD_MOSI = 1'b1;
    assign sd_init_done = 1'b1;
    assign sd_sec_read_data = 8'h00;
    assign sd_sec_read_data_valid = 1'b0;
    assign sd_sec_read_end = 1'b0;
    assign sd_sec_write_data_req = 1'b0;
    assign sd_sec_write_end = 1'b0;
endmodule

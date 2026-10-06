`timescale 1ns/1ps
// =============================================================================
// FAT32 媒体加载兼容层（第七讲）
//
// 对外保持旧 bmp_read 的接口语义：
//   ready       : 扫描器/加载器空闲且可接受下一次请求
//   scan_*      : 扫描完成后输出 PIC1~PIC4 对应资源的存在性
//   load_start  : 按 load_index 加载 PICn.BMP
//   write_req   : 向 frame_read_write 请求 SDRAM 双缓冲写区
//   bmp_data_*  : 24bit RGB 写数据流
//
// 加载顺序固定为：
//   申请 SDRAM 写区 -> 启动 FAT32 文件流 -> 解析 BMP 头 ->
//   跳过 data_offset -> BGR 拼成 RGB -> 输出像素
// 这样在 write_req 等待期间不会提前消费文件字节。
// =============================================================================
module fat32_media_loader #(
    // S4：优先使用 INDEX.BIN 曲目索引；=0 或索引缺失/损坏时完全回退到
    // PIC1~4.BMP + AUDIO.PCM 旧路径（旧路径逐拍行为保持不变）。
    parameter         USE_INDEX_BIN = 1'b1
)(
    input  wire        clk,
    input  wire        rst,
    output wire        ready,

    input  wire        scan_start,
    output reg         scan_done,
    output wire [23:0] media_status, // {done,index,idx_present,audio,cover_mask,idx_err,fs_err}
    output wire [7:0] media_error,  // Full diagnostic byte; independent of load retry pulse
    output reg         scan_found_valid,
    output reg  [1:0]  scan_found_index,
    output reg         scan_found_total,

    input  wire        load_start,
    input  wire [1:0]  load_index,

    input  wire        sd_init_done,
    output wire [3:0]  state_code,
    input  wire [15:0] bmp_width,
    input  wire [15:0] bmp_height,
    input  wire [1:0]  song_sel,       // S5：当前选中曲目（已同步到本域）
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

    // 第十一讲：AUDIO.PCM 元数据与额外扇区客户端。
    output wire        audio_file_valid,
    output wire [31:0] audio_start_lba,
    output wire [31:0] audio_total_sectors,
    input  wire        audio_sec_req,
    input  wire [31:0] audio_sec_lba,
    output wire        audio_sec_busy,
    output wire        audio_sec_valid,
    output wire [7:0]  audio_sec_byte,
    output wire [8:0]  audio_sec_byte_index,
    output wire        audio_sec_done,
    output wire [7:0]  audio_sec_error
);

    localparam ERR_NONE        = 4'd0;
    localparam ERR_HEADER      = 4'd1;
    localparam ERR_TIMEOUT     = 4'd2;
    localparam ERR_TRUNCATED   = 4'd3;
    localparam ERR_NO_RESOURCE = 4'd4;

    localparam LD_IDLE       = 3'd0;
    localparam LD_WAIT_WRITE = 3'd1;
    localparam LD_HEADER     = 3'd2;
    localparam LD_DATA       = 3'd3;

    // -------------------------------------------------------------------------
    // 扫描/加载使用同一组扇区接口，分时复用。
    // -------------------------------------------------------------------------
    reg         use_streamer;
    reg         scan_launch_pending;
    reg         load_launch_pending;
    reg [1:0]   load_index_latched;

    wire        scanner_done;
    wire        scanner_busy;
    wire [7:0]  scanner_error;
    wire [7:0]  scanner_spc;
    wire [31:0] scanner_fat_start;
    wire [31:0] scanner_data_start;
    wire [31:0] scanner_max_cluster;
    wire [3:0]  scanner_valid;
    wire [31:0] scanner_cluster0;
    wire [31:0] scanner_cluster1;
    wire [31:0] scanner_cluster2;
    wire [31:0] scanner_cluster3;
    wire [31:0] scanner_size0;
    wire [31:0] scanner_size1;
    wire [31:0] scanner_size2;
    wire [31:0] scanner_size3;
    wire        scanner_audio_valid;
    wire [31:0] scanner_audio_cluster;
    wire [31:0] scanner_audio_size;
    wire        scanner_index_valid;
    wire [31:0] scanner_index_cluster;
    wire [31:0] scanner_index_size;
    wire        scanner_req;
    wire [31:0] scanner_lba;
    wire        scanner_sector_busy;
    wire        scanner_sector_valid;
    wire [7:0]  scanner_sector_byte;
    wire [8:0]  scanner_sector_byte_index;
    wire        scanner_sector_done;
    wire [7:0]  scanner_sector_error;

    wire        streamer_busy;
    wire        streamer_done;
    wire        streamer_valid;
    wire [7:0]  streamer_byte;
    wire [7:0]  streamer_error;
    wire        streamer_req;
    wire [31:0] streamer_lba;
    wire        streamer_sector_busy;
    wire        streamer_sector_valid;
    wire [7:0]  streamer_sector_byte;
    wire [8:0]  streamer_sector_byte_index;
    wire        streamer_sector_done;
    wire [7:0]  streamer_sector_error;

    wire        arb_sector_req;
    wire [31:0] arb_sector_lba;
    wire        arb_sector_busy;
    wire        arb_sector_valid;
    wire [7:0]  arb_sector_byte;
    wire [8:0]  arb_sector_byte_index;
    wire        arb_sector_done;
    wire [7:0]  arb_sector_error;

    reg         audio_active;
    reg  [31:0] audio_lba_latched;
    reg         audio_file_valid_reg;
    reg  [31:0] audio_start_lba_reg;
    reg  [31:0] audio_total_sectors_reg;

    // ---------------------------------------------------------------------
    // S4：INDEX.BIN 曲目索引（复用文件流器读其唯一扇区）
    // ---------------------------------------------------------------------
    localparam [1:0] SP_SCAN  = 2'd0;
    localparam [1:0] SP_INDEX = 2'd1;
    localparam [1:0] SP_EMIT  = 2'd2;

    reg  [1:0]  scan_phase;
    reg         idx_started;
    reg         idx_start_pulse;
    reg         index_mode;          // 1=本次扫描已采用索引
    reg  [3:0]  src_valid;           // 本次扫描实际用于发 found 的有效位
    wire        idx_stream_mode = (scan_phase == SP_INDEX);
    // 只需判"根目录存在 INDEX.BIN 且扫描无错"；簇号/长度合法性交给
    // song_index_db 逐拍校验（它本来就要做），避免在这里再挂 32 位比较器
    // 到 100 MHz 组合路径。
    wire        idx_take        = USE_INDEX_BIN && scanner_index_valid &&
                                  (scanner_error == 8'h00);
    wire        idx_done;
    wire        idx_valid;
    wire [7:0]  idx_error;
    wire [2:0]  idx_song_count;
    wire [15:0] idx_song_flags;
    wire [63:0] idx_cover0, idx_cover1, idx_cover2, idx_cover3;
    wire [63:0] idx_audio0, idx_audio1, idx_audio2, idx_audio3;
    // S5：按选中曲目切换音频定位（索引里 4 首的音频簇号/字节数都已保留）。
    reg  [63:0] idx_audio_sel;
    always @* begin
        case (song_sel)
            2'd0:    idx_audio_sel = idx_audio0;
            2'd1:    idx_audio_sel = idx_audio1;
            2'd2:    idx_audio_sel = idx_audio2;
            default: idx_audio_sel = idx_audio3;
        endcase
    end
    wire [31:0] idx_aud_cluster = idx_audio_sel[31:0];
    wire [31:0] idx_aud_bytes   = idx_audio_sel[63:32];
    wire        idx_aud_valid   = (idx_aud_bytes != 32'd0) &&
                                  (idx_aud_cluster >= 32'd2);
    reg  [1:0]  song_sel_d;
    wire        song_sel_changed = (song_sel != song_sel_d) && index_mode;
    wire [3:0]  idx_valid_vec  = (4'd1 << idx_song_count) - 4'd1;
    wire [3:0]  idx_valid_bits = index_mode ? idx_valid_vec : 4'd0;
    wire [3:0]  eff_valid = index_mode ? idx_valid_bits : scanner_valid;

    reg [31:0] load_cluster;
    reg [31:0] load_size;
    reg [2:0]  load_state;

    reg [7:0]  header0;
    reg [7:0]  header1;
    reg [31:0] file_len;
    reg [31:0] data_offset;
    reg [31:0] dib_size;
    reg [31:0] width;
    reg [31:0] height;
    reg [15:0] planes;
    reg [15:0] bit_count;
    reg [31:0] compression;
    // Only counts the 54-byte BMP header: the state exits at byte 53.
    // File offsets and dynamic image dimensions retain their full width.
    reg [5:0]  header_byte_cnt;
    reg [31:0] pixel_byte_cnt;
    reg [31:0] pixel_count;
    reg [2:0]  rgb_byte_cnt;

    reg [1:0]  scan_emit_idx;
    reg        scan_emitting;
    reg stream_start_q;
    reg [31:0] stream_first_cluster_q;
    reg [31:0] stream_file_size_q;

    assign ready = !scanner_busy && !streamer_busy && !stream_start_q &&
                   (load_state == LD_IDLE) &&
                   !scan_launch_pending && !load_launch_pending;
    // 只在 SDRAM 写区握手完成的那一拍启动一次文件读取。该组合脉冲
    // 同时被流读取器采样，随后 load_state 离开 LD_WAIT_WRITE 自动撤销。
    wire file_stream_start = (load_state == LD_WAIT_WRITE) && write_req_ack;

    // S4：文件流器在"读索引"与"读图片"之间分时复用。两者互斥——索引只在
    // 扫描完成、scan_done 尚未拉高时读取，此时不可能有图片加载请求。
    wire stream_start_any = (idx_stream_mode && idx_start_pulse) || file_stream_start;
    wire [31:0] stream_first_cluster = idx_stream_mode ? scanner_index_cluster
                                                       : load_cluster;
    wire [31:0] stream_file_size     = idx_stream_mode ? 32'd512 : load_size;

    // Break the source mux -> cluster subtract/shift/add timing path.
    // Capture one transaction; the streamer starts one clk later with stable metadata.
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            stream_start_q <= 1'b0;
            stream_first_cluster_q <= 32'd0;
            stream_file_size_q <= 32'd0;
        end else begin
            stream_start_q <= stream_start_any && !streamer_busy && !stream_start_q;
            if (stream_start_any && !streamer_busy && !stream_start_q) begin
                stream_first_cluster_q <= stream_first_cluster;
                stream_file_size_q <= stream_file_size;
            end
        end
    end

    wire [31:0] expected_pixel_count;
    wire [31:0] required_pixel_bytes;
    assign expected_pixel_count = {16'd0, bmp_width} * {16'd0, bmp_height};
    assign required_pixel_bytes = expected_pixel_count * 32'd3;
    wire header_valid = (header0 == "B") && (header1 == "M") &&
                        (dib_size >= 32'd40) &&
                        (width[15:0] == bmp_width) &&
                        (height[15:0] == bmp_height) &&
                        (planes == 16'd1) &&
                        (bit_count == 16'd24) &&
                        (compression == 32'd0) &&
                        (data_offset >= 32'd54) &&
                        (data_offset < file_len) &&
                        (file_len >= (data_offset + required_pixel_bytes));

    function [2:0] spc_shift;
        input [7:0] value;
        begin
            case (value)
                8'd1:   spc_shift = 3'd0;
                8'd2:   spc_shift = 3'd1;
                8'd4:   spc_shift = 3'd2;
                8'd8:   spc_shift = 3'd3;
                8'd16:  spc_shift = 3'd4;
                8'd32:  spc_shift = 3'd5;
                8'd64:  spc_shift = 3'd6;
                8'd128: spc_shift = 3'd7;
                default: spc_shift = 3'd0;
            endcase
        end
    endfunction

    wire audio_cluster_valid = scanner_audio_valid &&
                               (scanner_audio_cluster >= 32'd2) &&
                               (scanner_spc != 8'd0);

    // 扫描结果跨模块直接参与 wav_stream_player 的播放使能和指针控制
    // 会形成超长组合路径；在扫描完成时锁存一次，保持语义不变。
    //
    // 第十二讲时序修正：audio_start_lba = data_start + ((cluster-2)<<shift)
    // 原本是一条组合链（32bit 减法 → 桶形移位 → 32bit 加法 → 选择，TD final
    // 报 8 级逻辑 / 10.244ns，在 sd_card_clk 100MHz 下 setup WNS -0.524ns）。
    // 这里拆成两级寄存器：scanner_done 当拍只锁存 cluster-2、移位量、基址和
    // 长度，下一拍再做移位+加法并写入结果寄存器。扫描结果是准静态的，
    // 结果晚一拍对外语义不变（wav_stream_player 在扫描完成后才被使能）。
    reg  [31:0] audio_cluster_m2_d;
    reg  [2:0]  audio_spc_shift_d;
    reg  [31:0] audio_data_start_d;
    reg  [31:0] audio_size_d;
    reg         audio_cluster_valid_d;
    reg         audio_meta_pending;

    wire [31:0] audio_start_lba_calc =
        audio_data_start_d + (audio_cluster_m2_d << audio_spc_shift_d);
    wire [31:0] audio_total_sectors_calc =
        (audio_size_d + 32'd511) >> 9;
    wire audio_file_valid_calc = audio_cluster_valid_d &&
                                 (audio_size_d != 32'd0);

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            audio_file_valid_reg    <= 1'b0;
            audio_start_lba_reg     <= 32'd0;
            audio_total_sectors_reg <= 32'd0;
            audio_cluster_m2_d      <= 32'd0;
            audio_spc_shift_d       <= 3'd0;
            audio_data_start_d      <= 32'd0;
            audio_size_d            <= 32'd0;
            audio_cluster_valid_d   <= 1'b0;
            audio_meta_pending      <= 1'b0;
            song_sel_d              <= 2'd0;
        end else if (scan_start) begin
            audio_file_valid_reg    <= 1'b0;
            audio_start_lba_reg     <= 32'd0;
            audio_total_sectors_reg <= 32'd0;
            audio_meta_pending      <= 1'b0;
        end else if ((idx_done && idx_valid) || song_sel_changed) begin
            // S5：索引有效时音频定位由"当前选中曲目"的条目给出（裸 PCM 语义）；
            // 切曲时 song_sel_changed 会重新走一遍这条两级流水（约 2 拍）。
            song_sel_d            <= song_sel;
            audio_cluster_m2_d    <= idx_aud_valid ?
                                     (idx_aud_cluster - 32'd2) : 32'd0;
            audio_spc_shift_d     <= spc_shift(scanner_spc);
            audio_data_start_d    <= scanner_data_start;
            audio_size_d          <= idx_aud_bytes;
            audio_cluster_valid_d <= idx_aud_valid;
            audio_meta_pending    <= 1'b1;
        end else if ((scanner_done && !idx_take) || (idx_done && !idx_valid)) begin
            // A rejected index must restore legacy audio as well as PIC covers.
            audio_cluster_m2_d    <= audio_cluster_valid ?
                                     (scanner_audio_cluster - 32'd2) : 32'd0;
            audio_spc_shift_d     <= spc_shift(scanner_spc);
            audio_data_start_d    <= scanner_data_start;
            audio_size_d          <= scanner_audio_size;
            audio_cluster_valid_d <= audio_cluster_valid;
            audio_meta_pending    <= 1'b1;
        end else if (audio_meta_pending) begin
            audio_file_valid_reg    <= audio_file_valid_calc;
            audio_start_lba_reg     <= audio_cluster_valid_d ?
                                       audio_start_lba_calc : 32'd0;
            audio_total_sectors_reg <= (audio_file_valid_calc &&
                                        (audio_total_sectors_calc != 32'd0)) ?
                                       audio_total_sectors_calc : 32'd0;
            audio_meta_pending      <= 1'b0;
        end
    end

    assign media_status = {scan_done, index_mode, scanner_index_valid,
                           audio_file_valid_reg, src_valid, idx_error, scanner_error};
    assign media_error = !scan_done ? 8'd0 :
                         (scanner_error != 0) ? scanner_error :
                         (idx_started && !idx_valid) ? idx_error :
                         (src_valid == 0) ? 8'h22 : 8'd0;
    assign audio_file_valid = audio_file_valid_reg;
    assign audio_start_lba = audio_start_lba_reg;
    assign audio_total_sectors = audio_total_sectors_reg;

    // -------------------------------------------------------------------------
    // 请求锁存：上游 pulse 即使与子模块 busy 同拍也不会丢失。
    // -------------------------------------------------------------------------
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            scan_launch_pending <= 1'b0;
            load_launch_pending <= 1'b0;
            load_index_latched <= 2'd0;
        end else begin
            if (scan_start)
                scan_launch_pending <= 1'b1;
            if (load_start) begin
                load_launch_pending <= 1'b1;
                load_index_latched <= load_index;
            end

            // scanner 在 ST_IDLE 看到 scan_start 后下一拍拉起 scanner_busy。
            // 以 busy 上升沿确认请求已接收，避免扫描完成时再次启动一轮扫描。
            if (scan_launch_pending && !use_streamer && scanner_busy)
                scan_launch_pending <= 1'b0;

            if (load_launch_pending && use_streamer &&
                !streamer_busy && (load_state == LD_IDLE))
                load_launch_pending <= 1'b0;

        end
    end

    // -------------------------------------------------------------------------
    // FAT32 卷扫描器
    // -------------------------------------------------------------------------
    fat32_volume_scanner u_volume_scanner (
        .clk                 (clk),
        .rst_n               (~rst),
        .scan_start          (scan_launch_pending && !use_streamer),
        .scan_busy           (scanner_busy),
        .scan_done           (scanner_done),
        .fs_error            (scanner_error),
        .partition_lba       (),
        .sectors_per_cluster (scanner_spc),
        .fat_start_lba       (scanner_fat_start),
        .data_start_lba      (scanner_data_start),
        .max_cluster         (scanner_max_cluster),
        .resource_valid      (scanner_valid),
        .resource0_cluster   (scanner_cluster0),
        .resource1_cluster   (scanner_cluster1),
        .resource2_cluster   (scanner_cluster2),
        .resource3_cluster   (scanner_cluster3),
        .resource0_size      (scanner_size0),
        .resource1_size      (scanner_size1),
        .resource2_size      (scanner_size2),
        .resource3_size      (scanner_size3),
        .audio_valid         (scanner_audio_valid),
        .audio_cluster       (scanner_audio_cluster),
        .audio_size          (scanner_audio_size),
        .index_valid         (scanner_index_valid),
        .index_cluster       (scanner_index_cluster),
        .index_size          (scanner_index_size),
        .sector_req          (scanner_req),
        .sector_lba          (scanner_lba),
        .sector_busy         (scanner_sector_busy),
        .sector_valid        (scanner_sector_valid),
        .sector_byte         (scanner_sector_byte),
        .sector_byte_index   (scanner_sector_byte_index),
        .sector_done         (scanner_sector_done),
        .sector_error        (scanner_sector_error)
    );

    // -------------------------------------------------------------------------
    // FAT32 文件流读取器
    // -------------------------------------------------------------------------
    fat32_file_streamer u_file_streamer (
        .clk                 (clk),
        .rst_n               (~rst),
        .file_start          (stream_start_q),
        .first_cluster       (stream_first_cluster_q),
        .file_size           (stream_file_size_q),
        .sectors_per_cluster (scanner_spc),
        .fat_start_lba       (scanner_fat_start),
        .data_start_lba      (scanner_data_start),
        .max_cluster         (scanner_max_cluster),
        .file_busy           (streamer_busy),
        .file_done           (streamer_done),
        .file_valid          (streamer_valid),
        .file_byte           (streamer_byte),
        // S4：file_byte_offset 不引出（其 32 位减法在本设计里无人使用，
        // 不引出可让 TD 继续裁剪掉它，避免它进入 100 MHz 关键区域）。
        .file_byte_offset    (),
        .fs_error            (streamer_error),
        .sector_req          (streamer_req),
        .sector_lba          (streamer_lba),
        .sector_busy         (streamer_sector_busy),
        .sector_valid        (streamer_sector_valid),
        .sector_byte         (streamer_sector_byte),
        .sector_byte_index   (streamer_sector_byte_index),
        .sector_done         (streamer_sector_done),
        .sector_error        (streamer_sector_error)
    );

    // -------------------------------------------------------------------------
    // S4：曲目索引解析器（消费文件流器输出的字节流）
    // -------------------------------------------------------------------------
    song_index_db #(
        .MAX_SONGS (4)
    ) u_song_index_db (
        .clk            (clk),
        .rst_n          (~rst),
        .start          (idx_start_pulse),
        .in_valid       (streamer_valid),
        .in_byte        (streamer_byte),
        .in_done        (streamer_done),
        .in_error       (streamer_error),
        .max_cluster    (scanner_max_cluster),
        .busy           (),
        .done           (idx_done),
        .valid          (idx_valid),
        .err            (idx_error),
        .song_count     (idx_song_count),
        .song_flags     (idx_song_flags),
        .song_cover0    (idx_cover0),
        .song_cover1    (idx_cover1),
        .song_cover2    (idx_cover2),
        .song_cover3    (idx_cover3),
        .song_audio0    (idx_audio0),
        .song_audio1    (idx_audio1),
        .song_audio2    (idx_audio2),
        .song_audio3    (idx_audio3)
    );

    // 索引条目与旧扫描结果的取数选择（index_mode=0 时严格等于旧路径）
    wire [31:0] sel_cluster0 = index_mode ? idx_cover0[31:0] : scanner_cluster0;
    wire [31:0] sel_cluster1 = index_mode ? idx_cover1[31:0] : scanner_cluster1;
    wire [31:0] sel_cluster2 = index_mode ? idx_cover2[31:0] : scanner_cluster2;
    wire [31:0] sel_cluster3 = index_mode ? idx_cover3[31:0] : scanner_cluster3;
    wire [31:0] sel_size0    = index_mode ? idx_cover0[63:32] : scanner_size0;
    wire [31:0] sel_size1    = index_mode ? idx_cover1[63:32] : scanner_size1;
    wire [31:0] sel_size2    = index_mode ? idx_cover2[63:32] : scanner_size2;
    wire [31:0] sel_size3    = index_mode ? idx_cover3[63:32] : scanner_size3;

    // -------------------------------------------------------------------------
    // 两路扇区读分时复用
    // -------------------------------------------------------------------------
    // 第十一讲：音频扇区请求优先级最高，但每次只占用一个扇区。
    // 图片预加载/自动轮播的流读取器请求会在音频扇区结束后的下一拍继续
    // 获得仲裁，因此不会长时间饿死图片加载。
    assign arb_sector_req = audio_active ? 1'b1 :
                            ((!arb_sector_busy && audio_sec_req) ? 1'b1 :
                             (use_streamer ? streamer_req : scanner_req));
    assign arb_sector_lba = audio_active ? audio_lba_latched :
                            ((!arb_sector_busy && audio_sec_req) ? audio_sec_lba :
                             (use_streamer ? streamer_lba : scanner_lba));

    assign scanner_sector_busy       = (use_streamer || audio_active) ?
                                       1'b1 : arb_sector_busy;
    assign scanner_sector_valid      = (use_streamer || audio_active) ?
                                       1'b0 : arb_sector_valid;
    assign scanner_sector_byte       = (use_streamer || audio_active) ?
                                       8'd0 : arb_sector_byte;
    assign scanner_sector_byte_index = (use_streamer || audio_active) ?
                                       9'd0 : arb_sector_byte_index;
    assign scanner_sector_done       = (use_streamer || audio_active) ?
                                       1'b0 : arb_sector_done;
    assign scanner_sector_error      = (use_streamer || audio_active) ?
                                       8'd0 : arb_sector_error;

    assign streamer_sector_busy       = (!use_streamer || audio_active) ?
                                        1'b1 : arb_sector_busy;
    assign streamer_sector_valid      = (use_streamer && !audio_active) ?
                                        arb_sector_valid : 1'b0;
    assign streamer_sector_byte       = (use_streamer && !audio_active) ?
                                        arb_sector_byte : 8'd0;
    assign streamer_sector_byte_index = (use_streamer && !audio_active) ?
                                        arb_sector_byte_index : 9'd0;
    assign streamer_sector_done       = (use_streamer && !audio_active) ?
                                        arb_sector_done : 1'b0;
    assign streamer_sector_error      = (use_streamer && !audio_active) ?
                                        arb_sector_error : 8'd0;

    assign audio_sec_busy       = arb_sector_busy;
    assign audio_sec_valid      = audio_active ? arb_sector_valid : 1'b0;
    assign audio_sec_byte       = audio_active ? arb_sector_byte : 8'd0;
    assign audio_sec_byte_index = audio_active ? arb_sector_byte_index : 9'd0;
    assign audio_sec_done       = audio_active ? arb_sector_done : 1'b0;
    assign audio_sec_error      = audio_active ? arb_sector_error : 8'd0;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            audio_active      <= 1'b0;
            audio_lba_latched <= 32'd0;
        end else if (audio_active && arb_sector_done) begin
            audio_active <= 1'b0;
        end else if (!audio_active && !arb_sector_busy && audio_sec_req) begin
            audio_active      <= 1'b1;
            audio_lba_latched <= audio_sec_lba;
        end
    end

    // -------------------------------------------------------------------------
    // 扫描结果打散：旧上层接口按“找到一张就发一个 scan_found_valid”，
    // 本兼容层对资源 1~4 逐位发出 found，维持 img_sector0~3 的索引语义。
    // S4：若根目录有 INDEX.BIN，则先读一份索引；索引有效时按索引条目发
    // found（数量=曲目数），索引损坏/缺失时回退到旧的 PIC1~4 分支。
    // -------------------------------------------------------------------------
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            use_streamer <= 1'b0;
            scan_done <= 1'b0;
            scan_found_valid <= 1'b0;
            scan_found_index <= 2'd0;
            scan_found_total <= 1'b0;
            scan_emitting <= 1'b0;
            scan_emit_idx <= 2'd0;
            scan_phase <= SP_SCAN;
            idx_started <= 1'b0;
            idx_start_pulse <= 1'b0;
            index_mode <= 1'b0;
            src_valid <= 4'd0;
        end else begin
            scan_found_valid <= 1'b0;
            idx_start_pulse <= 1'b0;

            // 保持与旧 bmp_read 一致的接口语义：scan_done 在扫描完成后
            // 持续有效，上层 KEY1/KEY2 和自动轮播调度都依赖该电平。
            // 只有下一次 scan_start 到来时才清除。
            if (scan_start) begin
                scan_done <= 1'b0;
                scan_phase <= SP_SCAN;
                idx_started <= 1'b0;
                index_mode <= 1'b0;
                src_valid <= 4'd0;
            end else if (scan_phase == SP_SCAN) begin
                if (scanner_done) begin
                    use_streamer <= 1'b1;
                    if (idx_take) begin
                        // 有有效 INDEX.BIN 条目：下一拍启动索引文件流
                        scan_phase <= SP_INDEX;
                    end else if ((scanner_error != 0) || (scanner_valid == 4'd0)) begin
                        scan_phase <= SP_EMIT;
                        src_valid  <= 4'd0;
                        scan_emitting <= 1'b0;
                        scan_done <= 1'b1;
                    end else begin
                        scan_phase <= SP_EMIT;
                        src_valid  <= scanner_valid;
                        scan_emitting <= 1'b1;
                        scan_emit_idx <= 2'd0;
                    end
                end
            end else if (scan_phase == SP_INDEX) begin
                if (!idx_started) begin
                    idx_started <= 1'b1;
                    idx_start_pulse <= 1'b1;
                end else if (idx_done) begin
                    scan_phase <= SP_EMIT;
                    if (idx_valid) begin
                        index_mode <= 1'b1;
                        src_valid  <= idx_valid_vec;
                        scan_emitting <= 1'b1;
                        scan_emit_idx <= 2'd0;
                    end else if (scanner_valid != 4'd0) begin
                        src_valid  <= scanner_valid;
                        scan_emitting <= 1'b1;
                        scan_emit_idx <= 2'd0;
                    end else begin
                        src_valid  <= 4'd0;
                        scan_emitting <= 1'b0;
                        scan_done <= 1'b1;
                    end
                end
            end else if (scan_emitting) begin
                if (src_valid[scan_emit_idx]) begin
                    scan_found_valid <= 1'b1;
                    scan_found_index <= scan_emit_idx;
                    scan_found_total <= 1'b1;
                end
                if (scan_emit_idx == 2'd3) begin
                    scan_emitting <= 1'b0;
                    scan_done <= 1'b1;
                end else begin
                    scan_emit_idx <= scan_emit_idx + 2'd1;
                end
            end
        end
    end

    // -------------------------------------------------------------------------
    // BMP 头解析 + RGB 输出状态机
    // -------------------------------------------------------------------------
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            load_state <= LD_IDLE;
            header0 <= 8'd0;
            header1 <= 8'd0;
            file_len <= 32'd0;
            data_offset <= 32'd54;
            dib_size <= 32'd0;
            width <= 32'd0;
            height <= 32'd0;
            planes <= 16'd0;
            bit_count <= 16'd0;
            compression <= 32'd0;
            header_byte_cnt <= 32'd0;
            pixel_byte_cnt <= 32'd0;
            pixel_count <= 32'd0;
            rgb_byte_cnt <= 3'd0;
            load_cluster <= 32'd0;
            load_size <= 32'd0;
            write_req <= 1'b0;
            bmp_data_wr_en <= 1'b0;
            bmp_data <= 24'd0;
            bmp_error <= ERR_NONE;
            load_error <= 1'b0;
        end else if (!sd_init_done) begin
            load_state <= LD_IDLE;
            write_req <= 1'b0;
            bmp_data_wr_en <= 1'b0;
            load_error <= 1'b0;
            bmp_error <= ERR_NONE;
        end else begin
            load_error <= 1'b0;
            bmp_data_wr_en <= 1'b0;

            // 1. 接受加载请求：先申请 SDRAM 写区。
            if (load_launch_pending && use_streamer &&
                !streamer_busy && (load_state == LD_IDLE)) begin
                case (load_index_latched)
                    2'd0: begin load_cluster <= sel_cluster0; load_size <= sel_size0; end
                    2'd1: begin load_cluster <= sel_cluster1; load_size <= sel_size1; end
                    2'd2: begin load_cluster <= sel_cluster2; load_size <= sel_size2; end
                    default: begin load_cluster <= sel_cluster3; load_size <= sel_size3; end
                endcase

                if (!eff_valid[load_index_latched]) begin
                    bmp_error <= ERR_NO_RESOURCE;
                    load_error <= 1'b1;
                    load_state <= LD_IDLE;
                end else begin
                    write_req <= 1'b1;
                    load_state <= LD_WAIT_WRITE;
                    header_byte_cnt <= 32'd0;
                    pixel_byte_cnt <= 32'd0;
                    pixel_count <= 32'd0;
                    rgb_byte_cnt <= 3'd0;
                end
            end

            // 2. 写区握手完成后启动文件流。
            if ((load_state == LD_WAIT_WRITE) && write_req_ack) begin
                write_req <= 1'b0;
                load_state <= LD_HEADER;
            end

            // 3. 解析 BMP 前 54 字节。只消费 LD_HEADER 阶段的有效字节。
            if (streamer_valid && (load_state == LD_HEADER)) begin
                case (header_byte_cnt)
                    32'd0:  header0 <= streamer_byte;
                    32'd1:  header1 <= streamer_byte;
                    32'd2:  file_len[7:0] <= streamer_byte;
                    32'd3:  file_len[15:8] <= streamer_byte;
                    32'd4:  file_len[23:16] <= streamer_byte;
                    32'd5:  file_len[31:24] <= streamer_byte;
                    32'd10: data_offset[7:0] <= streamer_byte;
                    32'd11: data_offset[15:8] <= streamer_byte;
                    32'd12: data_offset[23:16] <= streamer_byte;
                    32'd13: data_offset[31:24] <= streamer_byte;
                    32'd14: dib_size[7:0] <= streamer_byte;
                    32'd15: dib_size[15:8] <= streamer_byte;
                    32'd16: dib_size[23:16] <= streamer_byte;
                    32'd17: dib_size[31:24] <= streamer_byte;
                    32'd18: width[7:0] <= streamer_byte;
                    32'd19: width[15:8] <= streamer_byte;
                    32'd20: width[23:16] <= streamer_byte;
                    32'd21: width[31:24] <= streamer_byte;
                    32'd22: height[7:0] <= streamer_byte;
                    32'd23: height[15:8] <= streamer_byte;
                    32'd24: height[23:16] <= streamer_byte;
                    32'd25: height[31:24] <= streamer_byte;
                    32'd26: planes[7:0] <= streamer_byte;
                    32'd27: planes[15:8] <= streamer_byte;
                    32'd28: bit_count[7:0] <= streamer_byte;
                    32'd29: bit_count[15:8] <= streamer_byte;
                    32'd30: compression[7:0] <= streamer_byte;
                    32'd31: compression[15:8] <= streamer_byte;
                    32'd32: compression[23:16] <= streamer_byte;
                    32'd33: compression[31:24] <= streamer_byte;
                    default: ;
                endcase

                if (header_byte_cnt == 32'd53) begin
                    if (header_valid) begin
                        pixel_byte_cnt <= data_offset;
                        rgb_byte_cnt <= 3'd0;
                        load_state <= LD_DATA;
                    end else begin
                        bmp_error <= ERR_HEADER;
                        load_error <= 1'b1;
                        load_state <= LD_IDLE;
                    end
                end else begin
                    header_byte_cnt <= header_byte_cnt + 32'd1;
                end
            end

            // 4. 跳过 BMP 数据偏移，然后 BGR -> RGB。
            if (streamer_valid && (load_state == LD_DATA)) begin
                if (pixel_byte_cnt < data_offset) begin
                    pixel_byte_cnt <= pixel_byte_cnt + 32'd1;
                end else if ((pixel_byte_cnt < file_len) &&
                             (pixel_byte_cnt <
                              (data_offset + required_pixel_bytes))) begin
                    case (rgb_byte_cnt)
                        3'd0: begin
                            bmp_data[7:0] <= streamer_byte;
                            rgb_byte_cnt <= 3'd1;
                        end
                        3'd1: begin
                            bmp_data[15:8] <= streamer_byte;
                            rgb_byte_cnt <= 3'd2;
                        end
                        3'd2: begin
                            bmp_data[23:16] <= streamer_byte;
                            rgb_byte_cnt <= 3'd0;
                            bmp_data_wr_en <= 1'b1;
                            pixel_count <= pixel_count + 32'd1;
                        end
                        default: rgb_byte_cnt <= 3'd0;
                    endcase
                    pixel_byte_cnt <= pixel_byte_cnt + 32'd1;
                end
            end

            // 5. 文件流结束后的完整性判定。
            if (streamer_done && (load_state != LD_IDLE)) begin
                if ((load_state == LD_DATA) &&
                    (pixel_count >= expected_pixel_count)) begin
                    load_state <= LD_IDLE;
                end else begin
                    bmp_error <= (load_state == LD_HEADER) ?
                                 ERR_HEADER : ERR_TRUNCATED;
                    load_error <= 1'b1;
                    load_state <= LD_IDLE;
                end
                write_req <= 1'b0;
            end

            if (load_error) begin
                write_req <= 1'b0;
                load_state <= LD_IDLE;
            end
        end
    end

    // -------------------------------------------------------------------------
    // 接到现有 sd_card_top 的协议适配层。
    // -------------------------------------------------------------------------
    sd_sector_adapter u_sd_sector_adapter (
        .clk                    (clk),
        .rst_n                  (~rst),
        .sector_req             (arb_sector_req),
        .sector_lba             (arb_sector_lba),
        .sector_busy            (arb_sector_busy),
        .sector_valid           (arb_sector_valid),
        .sector_byte            (arb_sector_byte),
        .sector_byte_index      (arb_sector_byte_index),
        .sector_done            (arb_sector_done),
        .sector_error           (arb_sector_error),
        .sd_sec_read            (sd_sec_read),
        .sd_sec_read_addr       (sd_sec_read_addr),
        .sd_sec_read_data_valid (sd_sec_read_data_valid),
        .sd_sec_read_data       (sd_sec_read_data),
        .sd_sec_read_end        (sd_sec_read_end)
    );

    assign state_code = (load_state == LD_IDLE)       ? 4'd1 :
                        (load_state == LD_WAIT_WRITE) ? 4'd3 :
                        (load_state == LD_HEADER)     ? 4'd2 : 4'd4;

endmodule

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
    output wire storage_done,
    output wire [7:0] storage_error,
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
    output wire [63:0] mv_metadata, // S6 selected song; zero for v1/absent MV
    output wire [31:0] background_base_lba,
    output wire background_art2_supported,
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
    // Keep BMP byte, valid and completion aligned in one pipeline stage.
    // Index parsing consumes a parallel one-cycle pipeline so its stream-valid
    // fanout does not directly drive the index field decoder.
    reg         bmp_stream_valid;
    reg [7:0]   bmp_stream_byte;
    reg         bmp_stream_done;
    reg         idx_stream_valid;
    reg [7:0]   idx_stream_byte;
    reg         idx_stream_done;
    reg [7:0]   idx_stream_error;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            bmp_stream_valid <= 1'b0;
            bmp_stream_byte <= 8'd0;
            bmp_stream_done <= 1'b0;
            idx_stream_valid <= 1'b0;
            idx_stream_byte <= 8'd0;
            idx_stream_done <= 1'b0;
            idx_stream_error <= 8'd0;
        end else begin
            bmp_stream_valid <= streamer_valid && sd_init_done;
            bmp_stream_byte <= streamer_byte;
            bmp_stream_done <= streamer_done && sd_init_done;
            // Keep the index byte stream and terminal status aligned while
            // adding a local register boundary after the shared FAT streamer.
            idx_stream_valid <= streamer_valid;
            idx_stream_byte <= streamer_byte;
            idx_stream_done <= streamer_done;
            idx_stream_error <= streamer_error;
        end
    end
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
    reg  [31:0] audio_size_bytes_reg;

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
    wire [63:0] idx_mv0,idx_mv1,idx_mv2,idx_mv3;
    wire [31:0] idx_background_base_lba;
    wire idx_background_art2_supported;
    assign background_base_lba = index_mode ? idx_background_base_lba : 32'd0;
    assign background_art2_supported = index_mode && idx_background_art2_supported;
    assign mv_metadata = !index_mode ? 64'd0 :
                         song_sel==0 ? idx_mv0 : song_sel==1 ? idx_mv1 :
                         song_sel==2 ? idx_mv2 : idx_mv3;
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
    // S7-03 时序收口：进入 LD_DATA 时一次寄存 data_offset + required_pixel_bytes，
    // 使逐像素判断不再在 100 MHz 路径里重算 32 位加法，功能等价。
    reg [31:0] pixel_end;
    reg [31:0] dib_size;
    reg [15:0] width;
    reg [15:0] height;
    reg [15:0] planes;
    reg [15:0] bit_count;
    reg [31:0] compression;
    // Only counts the 54-byte BMP header: the state exits at byte 53.
    // File offsets and dynamic image dimensions retain their full width.
    reg [5:0]  header_byte_cnt;
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
    // S7-04 资源/时序优化：原写法把 required_pixel_bytes 写成组合表达式
    //   {16'd0,bmp_width} * {16'd0,bmp_height} * 3
    // 它在 100MHz 域上生成 32x32 乘法器 + 32 位加法器串，并且直接串进
    //   header_valid: file_len >= (data_offset + required_pixel_bytes)
    // 这正是 S7-03 布局布线后 sd_card_clk 域唯一违例路径
    //   (WNS -0.125ns, data_offset_reg -> ... -> bmp_error_reg) 的来源。
    //
    // 改法：把两个乘积拆成“比较用”和“计数用”两路，并在数据段开始前
    // 一次性寄存。bmp_width/bmp_height 在整个文件加载期间是常量（顶层固定
    // 接 640/480），因此提前一拍算出与原表达式逐位相同的值不改变任何行为；
    // 同时 header_valid 判定时这两个值已经是寄存器输出，组合加法器串被切断。
    // 注意：必须保留 bmp_width/bmp_height 的可参数化语义——仿真台
    // tb_fat32_index_loader 用的是 64x4，不是 640x480。
    reg  [31:0] expected_pixel_count_q;
    reg  [31:0] required_pixel_bytes_q;
    reg         pixel_geom_ready;
    reg header_format_ok = 1'b0;
    reg header_offset_ok = 1'b0;
    reg header_payload_ok = 1'b0;
    reg [3:0] header_offset_parts = 4'd0;
    reg [2:0] header_payload_parts = 3'd0;

    assign expected_pixel_count = expected_pixel_count_q;
    assign required_pixel_bytes = required_pixel_bytes_q;

    wire header_valid = header_format_ok &&
                        (width[15:0] == bmp_width) &&
                        (height[15:0] == bmp_height) &&
                        header_offset_ok &&
                        pixel_geom_ready &&
                        header_payload_ok;

    // Every consumed header field is complete by byte 33. Prepare invariants
    // in the unused tail bytes, keeping byte 53's decision and stream timing.
    always @(posedge clk or posedge rst) begin
        if (rst) header_format_ok <= 1'b0;
        else if (bmp_stream_valid && load_state == LD_HEADER && header_byte_cnt == 6'd51)
            header_format_ok <= header0 == "B" && header1 == "M" &&
                dib_size >= 32'd40 && planes == 16'd1 &&
                bit_count == 16'd24 && compression == 32'd0;
    end
    always @(posedge clk or posedge rst) begin
        if (rst) header_offset_parts <= 4'd0;
        // Fields settle by byte 33 and are consumed only at byte 53.
        // Precompute continuously instead of merging byte/state decode into CE.
        else
            // The byte parser enters LD_DATA immediately after byte 53.
            // Accept exactly that layout; do not decode extended-header bytes as pixels.
            header_offset_parts <= {data_offset == 32'd54,
                                    file_len[31:16] != 16'd0,
                                    file_len[31:16] == 16'd0,
                                    file_len[15:0] > 16'd54};
    end
    always @(posedge clk or posedge rst) begin
        if (rst) header_offset_ok <= 1'b0;
        else
            header_offset_ok <= header_offset_parts[3] &&
                (header_offset_parts[2] || (header_offset_parts[1] && header_offset_parts[0]));
    end
    always @(posedge clk or posedge rst) begin
        if (rst) header_payload_parts <= 3'd0;
        else header_payload_parts <= {file_len[31:16] > pixel_end[31:16],
                                      file_len[31:16] == pixel_end[31:16],
                                      file_len[15:0] >= pixel_end[15:0]};
    end
    always @(posedge clk or posedge rst) begin
        if (rst) header_payload_ok <= 1'b0;
        else header_payload_ok <= header_payload_parts[2] ||
                                  (header_payload_parts[1] && header_payload_parts[0]);
    end

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
            audio_size_bytes_reg    <= 32'd0;
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
            audio_size_bytes_reg    <= 32'd0;
            audio_meta_pending      <= 1'b0;
        end else if ((idx_done && idx_valid) || song_sel_changed) begin
            // S5：索引有效时音频定位由"当前选中曲目"的条目给出（裸 PCM 语义）；
            // 切曲时 song_sel_changed 会重新走一遍这条两级流水（约 2 拍）。
            song_sel_d            <= song_sel;
            // Invalid intermediate arithmetic is never published: the next
            // commit already gates every derived address with *_valid_d.
            audio_cluster_m2_d    <= idx_aud_cluster - 32'd2;
            audio_spc_shift_d     <= spc_shift(scanner_spc);
            audio_data_start_d    <= scanner_data_start;
            audio_size_d          <= idx_aud_bytes;
            audio_cluster_valid_d <= idx_aud_valid;
            audio_meta_pending    <= 1'b1;
        end else if ((scanner_done && !idx_take) || (idx_done && !idx_valid)) begin
            // A rejected index must restore legacy audio as well as PIC covers.
            audio_cluster_m2_d    <= scanner_audio_cluster - 32'd2;
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
            audio_size_bytes_reg    <= audio_file_valid_calc ? audio_size_d : 32'd0;
            audio_meta_pending      <= 1'b0;
        end
    end

    assign storage_done = arb_sector_done;
    assign storage_error = arb_sector_error;
    assign media_status = {scan_done, index_mode, scanner_index_valid,
                           audio_file_valid_reg, src_valid, idx_error, scanner_error};
    assign media_error = !scan_done ? 8'd0 :
                         (scanner_error != 0) ? scanner_error :
                         (idx_started && !idx_valid) ? idx_error :
                         (src_valid == 0) ? 8'h22 : 8'd0;
    assign audio_file_valid = audio_file_valid_reg;
    assign audio_start_lba = audio_start_lba_reg;
    assign audio_total_sectors = audio_total_sectors_reg;
    assign audio_size_bytes = audio_size_bytes_reg;

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
        .MAX_SONGS (4),
        // index_mode is committed only after idx_valid; it also gates all
        // index payload consumption during reload and error fallback.
        .RAW_PAYLOAD_OUTPUTS (1)
    ) u_song_index_db (
        .clk            (clk),
        .rst_n          (~rst),
        .start          (idx_start_pulse),
        .in_valid       (idx_stream_valid),
        .in_byte        (idx_stream_byte),
        .in_done        (idx_stream_done),
        .in_error       (idx_stream_error),
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
        .song_audio3    (idx_audio3),
        .song_mv0(idx_mv0), .song_mv1(idx_mv1), .song_mv2(idx_mv2), .song_mv3(idx_mv3),
        .background_base_lba(idx_background_base_lba),
        .background_art2_supported(idx_background_art2_supported)
    );

    // Select a slot within each source first, then choose the source once.
    // This keeps index_mode off the four parallel 64-bit slot buses.
    reg [63:0] legacy_meta_sel;
    reg [63:0] index_meta_sel;
    always @* begin
        case (load_index_latched)
            2'd0: begin
                legacy_meta_sel = {scanner_size0, scanner_cluster0};
                index_meta_sel  = idx_cover0;
            end
            2'd1: begin
                legacy_meta_sel = {scanner_size1, scanner_cluster1};
                index_meta_sel  = idx_cover1;
            end
            2'd2: begin
                legacy_meta_sel = {scanner_size2, scanner_cluster2};
                index_meta_sel  = idx_cover2;
            end
            default: begin
                legacy_meta_sel = {scanner_size3, scanner_cluster3};
                index_meta_sel  = idx_cover3;
            end
        endcase
    end
    wire [63:0] selected_meta = index_mode ? index_meta_sel : legacy_meta_sel;

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
                // A rescan must return sector ownership to the scanner. The
                // caller asserts scan_start only while ready, so no active
                // streamer transaction is interrupted by this mux change.
                use_streamer <= 1'b0;
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
            pixel_end <= 32'd0;
            dib_size <= 32'd0;
            width <= 16'd0;
            height <= 16'd0;
            planes <= 16'd0;
            bit_count <= 16'd0;
            compression <= 32'd0;
            header_byte_cnt <= 6'd0;
            pixel_count <= 32'd0;
            rgb_byte_cnt <= 3'd0;
            expected_pixel_count_q <= 32'd0;
            required_pixel_bytes_q <= 32'd0;
            pixel_geom_ready <= 1'b0;
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
            if (load_state == LD_WAIT_WRITE && !pixel_geom_ready) begin
                required_pixel_bytes_q <= (expected_pixel_count_q << 1) + expected_pixel_count_q;
                pixel_geom_ready <= 1'b1;
            end

            // 1. 接受加载请求：先申请 SDRAM 写区。
            if (load_launch_pending && use_streamer &&
                !streamer_busy && (load_state == LD_IDLE)) begin
                load_cluster <= selected_meta[31:0];
                load_size <= selected_meta[63:32];

                if (!eff_valid[load_index_latched]) begin
                    bmp_error <= ERR_NO_RESOURCE;
                    load_error <= 1'b1;
                    load_state <= LD_IDLE;
                end else begin
                    write_req <= 1'b1;
                    load_state <= LD_WAIT_WRITE;
                    header_byte_cnt <= 6'd0;
                    pixel_count <= 32'd0;
                    rgb_byte_cnt <= 3'd0;
                    // S7-04：几何常量在加载请求被接受时就一次算定。
                    // bmp_width/bmp_height 是常量输入，到 54 字节头校验时
                    // 已有 50+ 拍余量，乘法器完全不进入 header_valid 路径。
                    expected_pixel_count_q <= {16'd0, bmp_width} * {16'd0, bmp_height};
                    // Reuse this product in the following write-ACK wait beat.
                    // Generic test dimensions and modulo-2^32 arithmetic stay.
                    pixel_geom_ready      <= 1'b0;
                end
            end

            // 2. 写区握手完成后启动文件流。
            if ((load_state == LD_WAIT_WRITE) && write_req_ack) begin
                write_req <= 1'b0;
                load_state <= LD_HEADER;
            end

            // 3. 解析 BMP 前 54 字节。只消费 LD_HEADER 阶段的有效字节。
            if (bmp_stream_valid && (load_state == LD_HEADER)) begin
                case (header_byte_cnt)
                    6'd0:  header0 <= bmp_stream_byte;
                    6'd1:  header1 <= bmp_stream_byte;
                    6'd2:  file_len[7:0] <= bmp_stream_byte;
                    6'd3:  file_len[15:8] <= bmp_stream_byte;
                    6'd4:  file_len[23:16] <= bmp_stream_byte;
                    6'd5:  file_len[31:24] <= bmp_stream_byte;
                    6'd10: data_offset[7:0] <= bmp_stream_byte;
                    6'd11: data_offset[15:8] <= bmp_stream_byte;
                    6'd12: data_offset[23:16] <= bmp_stream_byte;
                    6'd13: data_offset[31:24] <= bmp_stream_byte;
                    6'd14: dib_size[7:0] <= bmp_stream_byte;
                    6'd15: dib_size[15:8] <= bmp_stream_byte;
                    6'd16: dib_size[23:16] <= bmp_stream_byte;
                    6'd17: dib_size[31:24] <= bmp_stream_byte;
                    6'd18: width[7:0] <= bmp_stream_byte;
                    6'd19: width[15:8] <= bmp_stream_byte;
                    6'd22: height[7:0] <= bmp_stream_byte;
                    6'd23: height[15:8] <= bmp_stream_byte;
                    6'd26: planes[7:0] <= bmp_stream_byte;
                    6'd27: planes[15:8] <= bmp_stream_byte;
                    6'd28: bit_count[7:0] <= bmp_stream_byte;
                    6'd29: bit_count[15:8] <= bmp_stream_byte;
                    6'd30: compression[7:0] <= bmp_stream_byte;
                    6'd31: compression[15:8] <= bmp_stream_byte;
                    6'd32: compression[23:16] <= bmp_stream_byte;
                    6'd33: compression[31:24] <= bmp_stream_byte;
                    default: ;
                endcase

                // All header fields are complete by byte 33. Prepare the
                // existing end register four bytes before validation, including
                // the original modulo-2^32 wrap. No output or handshake moves.
                if (header_byte_cnt == 6'd49)
                    pixel_end <= data_offset + required_pixel_bytes;

                if (header_byte_cnt == 6'd53) begin
                    if (header_valid) begin
                        rgb_byte_cnt <= 3'd0;
                        load_state <= LD_DATA;
                    end else begin
                        bmp_error <= ERR_HEADER;
                        load_error <= 1'b1;
                        load_state <= LD_IDLE;
                    end
                end else begin
                    header_byte_cnt <= header_byte_cnt + 6'd1;
                end
            end

            // 4. 跳过 BMP 数据偏移，然后 BGR -> RGB。
            if (bmp_stream_valid && (load_state == LD_DATA)) begin
                // 字节消费上界改用 pixel_count 守卫：pixel_count 在本状态
                // 外保持清零、进入前已复位，且只在本分支内每 3 字节加一，
                // 故“已消费字节数 N”与 pixel_count 恒有 N=3*pixel_count+r。
                // 于是 pixel_count < expected_pixel_count 与原
                // pixel_byte_cnt < pixel_end 逐拍等价（N<3P 当且仅当
                // floor(N/3)<P），同时去掉一个 32 位字节计数器及其自增。
                if (pixel_count < expected_pixel_count) begin
                    case (rgb_byte_cnt)
                        3'd0: begin
                            bmp_data[7:0] <= bmp_stream_byte;
                            rgb_byte_cnt <= 3'd1;
                        end
                        3'd1: begin
                            bmp_data[15:8] <= bmp_stream_byte;
                            rgb_byte_cnt <= 3'd2;
                        end
                        3'd2: begin
                            bmp_data[23:16] <= bmp_stream_byte;
                            rgb_byte_cnt <= 3'd0;
                            bmp_data_wr_en <= 1'b1;
                            pixel_count <= pixel_count + 32'd1;
                        end
                        default: rgb_byte_cnt <= 3'd0;
                    endcase
                end
            end

            // 5. 文件流结束后的完整性判定。
            if (bmp_stream_done && (load_state != LD_IDLE)) begin
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

            // S7-04：几何常量只对本次加载有效。离开本次加载后清除，保证下一次
            // 加载必须重新算定，不会有陈旧值通过 header 校验。
            // 注意排除“本拍刚接受加载请求”这一种情况：那一拍load_state 仍是
            // LD_IDLE，若在此清零会覆盖上面刚写入的 1'b1（后赋值优先）。
            if ((load_state == LD_IDLE) && !(load_launch_pending && use_streamer &&
                                             !streamer_busy && eff_valid[load_index_latched]))
                pixel_geom_ready <= 1'b0;
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

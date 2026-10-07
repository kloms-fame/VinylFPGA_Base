// =============================================================================
// File Name    : sd_card_bmp.v
// Module Name  : sd_card_bmp
// Project      : VinylFPGA (完赛优化系列 - 第三讲/第五讲/第六讲/第七讲/第八讲)
// Description  : 长短按复用、双向切换、自动轮播、稳定性恢复、FAT32四bank预加载
// =============================================================================

module sd_card_bmp #(
    parameter integer CLK_FREQ_HZ       = 100_000_000, // 控制时钟100MHz
    parameter [31:0]  SCAN_START_SECTOR = 32'd0,       // 扫描起始扇区
    parameter [31:0]  SCAN_MAX_SECTOR   = 32'd131071,  // 扫描最大扇区
    parameter [2:0]   SCAN_TARGET_COUNT = 3'd4,        // 目标图片数量
    // === 优化新增参数配置 ===
    parameter integer LONG_PRESS_MS      = 1000,        // KEY2长按判定门限(ms)，默认1秒
    parameter integer AUTO_PLAY_MS       = 3000,        // 自动轮播间隔(ms)，默认3秒
    parameter integer SD_READ_TIMEOUT_MS = 500,         // SD读超时(ms)，第五讲稳定性
    parameter integer MAX_RETRIES        = 1            // 错误重试次数，默认1次
)(
    input                       clk,
    input                       rst,
    input                       sdr_init_done,         // SDRAM初始化完成，已同步到本时钟域
    input                       key_next,              // KEY1：短按下一张
    input                       next_event,            // 第十讲：转场模块完成淡出后的下一张请求
    input                       prev_event,            // S3：J2 EC1/方向键的"上一张"单拍请求
    input                       select_req,            // 第十五讲：快速选图请求（保持到 select_ack）
    input  [1:0]                select_index,          // 第十五讲：快速选图目标 bank
    output reg                  select_ack,            // 第十五讲：快速选图请求已接受
    input                       auto_inhibit,
    input                       key_auto,              // KEY2：短按自动轮播开关 / 长按上一张
    output reg [3:0]            state_code,            // 数码管显示：当前图片编号 1~4
    input  [15:0]               bmp_width,
    input  [15:0]               bmp_height,
    input  [1:0]                song_sel,           // S5：当前选中曲目（同域，播放音频定位用）
    output reg                  display_valid,
    output wire                 auto_play_en_out,      // 第九讲OSD：自动轮播状态
    output reg  [7:0]           osd_error_code,        // 第九讲OSD：错误码，0=正常
    output reg                  osd_error_toggle,      // 跨到video_clk域的捆绑数据翻转标志
    output reg                  switch_abort_toggle,   // 第十讲：手动切换失败时释放转场状态机
    input                       write_finish_toggle,   // 来自 mem_clk 域的写完成翻转信号
    output reg [1:0]            write_buf_idx,         // 当前加载目标bank(0~3)
    output reg [1:0]            disp_buf_idx,          // 当前显示bank(0~3)
    output wire [3:0]           image_ready_out,       // 第十三讲：四个bank加载完成标记（只读引出）
    output                      write_req,
    input                       write_req_ack,
    output                      write_en,
    output [31:0]               write_data,
    output                      SD_nCS,
    output                      SD_DCLK,
    output                      SD_MOSI,
    input                       SD_MISO,

    // 第十一讲：AUDIO.PCM 元数据与音频扇区客户端。
    output wire storage_done,
    output wire [7:0] storage_error,
    output wire [23:0]          media_status,            // SD-domain diagnostic snapshot
    output wire media_preloaded,
    output wire [63:0] mv_metadata, // S6 selected song; zero for v1/absent MV
    output wire                 audio_file_valid,
    output wire [31:0]          audio_start_lba,
    output wire [31:0]          audio_total_sectors,
    output wire [31:0]          audio_size_bytes,
    output wire                 audio_play_enable,
    input  wire                 audio_sec_req,
    input  wire [31:0]          audio_sec_lba,
    output wire                 audio_sec_busy,
    output wire                 audio_sec_valid,
    output wire [7:0]           audio_sec_byte,
    output wire [8:0]           audio_sec_byte_index,
    output wire                 audio_sec_done,
    output wire [7:0]           audio_sec_error
);

    // =========================================================================
    // 信号定义
    // =========================================================================
    wire        key_next_press;
    wire        key_auto_press;
    wire        key_auto_stable;
    reg         key_auto_stable_d;

    wire        sd_sec_read;
    wire [31:0] sd_sec_read_addr;
    wire [7:0]  sd_sec_read_data;
    wire        sd_sec_read_data_valid;
    wire        sd_sec_read_end;
    wire        bmp_data_wr_en;
    wire [23:0] bmp_data;
    wire        sd_init_done;
    wire        bmp_ready;
    reg         bmp_ready_q;
    wire        scan_done;
    reg         scan_done_eff;
    wire        scan_found_valid;
    wire [1:0]  scan_found_index;
    wire        scan_found_total;
    wire [3:0]  bmp_internal_state;
    wire [3:0]  bmp_error;
    wire        load_error;
    wire [7:0]  media_error;
    wire        preload_done;

    reg         scan_start_pulse;
    reg         load_start_pulse;
    reg [1:0]   load_index;
    reg         scan_kicked;
    reg         first_image_committed;
    reg         scan_abort;
    reg         boot_failed;
    reg [2:0]   preload_idx;         // 后台预加载顺序：0~3，4表示全部处理完

    reg         auto_play_en;
    reg [31:0]  auto_cnt;
    reg [2:0]   img_found_count;
    reg         audio_play_enable_reg;
    reg [1:0]   img_idx;             // 当前屏幕上显示的图片编号(0~3)
    reg [1:0]   load_idx;            // 正在加载的图片编号(0~3)
    reg [3:0]   image_ready;         // 四个bank加载完成标记，bit n对应PIC(n+1)

    // FAT32 扫描结果：每张有效图片对应的资源索引(0~3)，
    // 加载时交给 fat32_media_loader 选择 PICn.BMP 的簇号/大小。
    reg [1:0]   img_index0;
    reg [1:0]   img_index1;
    reg [1:0]   img_index2;
    reg [1:0]   img_index3;

    reg         next_req_pending;    // 下一张请求挂起标志（防连跳）
    reg         prev_req_pending;    // 上一张请求挂起标志（防连跳）
    reg         load_busy;
    reg         load_is_preload;     // 当前加载是否由后台预加载发起
    reg         load_for_display;    // 当前加载完成后是否切换显示
    reg         source_done_seen;
    reg         load_error_seen;
    reg [1:0]   retry_count;

    // KEY2 长按检测逻辑寄存器
    reg [31:0]  long_press_cnt;
    reg         long_press_marked;

    // 跨时钟域写完成同步链
    reg [2:0]   wrfin_tgl_sync;
    wire        write_finish_pulse;

    // 毫秒转周期常量计算
    localparam [31:0] AUTO_PLAY_CYCLES  = (CLK_FREQ_HZ / 1000) * AUTO_PLAY_MS;
    localparam [31:0] LONG_PRESS_CYCLES = (CLK_FREQ_HZ / 1000) * LONG_PRESS_MS;

    wire        auto_tick;
    wire [1:0]  next_from_current;
    wire [1:0]  prev_from_current;

    // =========================================================================
    // 连续赋值
    // =========================================================================
    assign write_en           = bmp_data_wr_en;
    assign write_data         = {bmp_data[23:16], bmp_data[15:8], bmp_data[7:0], 8'h00};
    assign write_finish_pulse = wrfin_tgl_sync[2] ^ wrfin_tgl_sync[1];
    assign auto_tick          = (auto_cnt >= (AUTO_PLAY_CYCLES - 1'b1));
    assign auto_play_en_out   = auto_play_en;
    assign media_preloaded = preload_done && scan_done_eff;
    assign preload_done       = (img_found_count == 3'd0) ||
                                (preload_idx >= img_found_count);
    // 第十三讲：把内部 bank 就绪标记只读引出给顶层缩略图视图使用，
    // 不改变任何原有状态机逻辑。
    assign image_ready_out    = image_ready;
    wire audio_play_request = audio_file_valid && scan_done_eff &&
                              preload_done;
    assign audio_play_enable = audio_play_enable_reg;

    // 播放使能由组合调度信号寄存后送 WAV 播放器，切断扫描/预加载
    // 到音频缓冲控制的跨模块长路径；只延迟一个 sd_card_clk 周期。
    always @(posedge clk or posedge rst) begin
        if (rst)
            audio_play_enable_reg <= 1'b0;
        else if (!sd_init_done)
            audio_play_enable_reg <= 1'b0;
        else
            audio_play_enable_reg <= audio_play_request;
    end

    // 四bank后，图片编号就是bank编号，切换时读地址索引直接使用img_idx。
    assign next_from_current  = next_index_limited(img_idx, img_found_count);
    assign prev_from_current  = prev_index_limited(img_idx, img_found_count);

    // =========================================================================
    // 逻辑函数 (组合逻辑)
    // =========================================================================
    // 计算下一张图片编号
    function [1:0] next_index_limited;
        input [1:0] cur;
        input [2:0] count;
        begin
            case (count)
                3'd0: next_index_limited = 2'd0;
                3'd1: next_index_limited = 2'd0;
                3'd2: next_index_limited = (cur == 2'd1) ? 2'd0 : (cur + 2'd1);
                3'd3: next_index_limited = (cur == 2'd2) ? 2'd0 : (cur + 2'd1);
                default: next_index_limited = (cur == 2'd3) ? 2'd0 : (cur + 2'd1);
            endcase
        end
    endfunction

    // 计算上一张图片编号 (完赛新增)
    function [1:0] prev_index_limited;
        input [1:0] cur;
        input [2:0] count;
        begin
            case (count)
                3'd0: prev_index_limited = 2'd0;
                3'd1: prev_index_limited = 2'd0;
                3'd2: prev_index_limited = (cur == 2'd0) ? 2'd1 : (cur - 2'd1);
                3'd3: prev_index_limited = (cur == 2'd0) ? 2'd2 : (cur - 2'd1);
                default: prev_index_limited = (cur == 2'd0) ? 2'd3 : (cur - 2'd1);
            endcase
        end
    endfunction

    // 图片资源索引查表函数
    function [1:0] index_lut;
        input [1:0] idx;
        begin
            case (idx)
                2'd0: index_lut = img_index0;
                2'd1: index_lut = img_index1;
                2'd2: index_lut = img_index2;
                default: index_lut = img_index3;
            endcase
        end
    endfunction

    // 四bank加载完成查询函数
    function ready_lut;
        input [1:0] idx;
        begin
            case (idx)
                2'd0: ready_lut = image_ready[0];
                2'd1: ready_lut = image_ready[1];
                2'd2: ready_lut = image_ready[2];
                default: ready_lut = image_ready[3];
            endcase
        end
    endfunction

    // =========================================================================
    // 状态控制主时序
    // =========================================================================
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            wrfin_tgl_sync        <= 3'b000;
            bmp_ready_q           <= 1'b0;
            scan_done_eff         <= 1'b0;
            scan_start_pulse      <= 1'b0;
            load_start_pulse      <= 1'b0;
            load_index            <= 2'd0;
            scan_kicked           <= 1'b0;
            first_image_committed <= 1'b0;
            scan_abort            <= 1'b0;
            boot_failed           <= 1'b0;
            preload_idx           <= 3'd0;
            auto_play_en          <= 1'b0;
            auto_cnt              <= 32'd0;
            img_found_count       <= 3'd0;
            img_idx               <= 2'd0;
            load_idx              <= 2'd0;
            image_ready           <= 4'd0;
            write_buf_idx         <= 2'd0;
            disp_buf_idx          <= 2'd0;
            img_index0            <= 2'd0;
            img_index1            <= 2'd0;
            img_index2            <= 2'd0;
            img_index3            <= 2'd0;
            next_req_pending      <= 1'b0;
            prev_req_pending      <= 1'b0;
            load_busy             <= 1'b0;
            load_is_preload       <= 1'b0;
            load_for_display      <= 1'b0;
            source_done_seen      <= 1'b0;
            load_error_seen       <= 1'b0;
            retry_count           <= 2'd0;
            display_valid         <= 1'b0;
            osd_error_code        <= 8'd0;
            osd_error_toggle      <= 1'b0;
            switch_abort_toggle   <= 1'b0;
            long_press_cnt        <= 32'd0;
            long_press_marked     <= 1'b0;
            key_auto_stable_d     <= 1'b1;
            select_ack            <= 1'b0;
            state_code            <= 4'd0;
        end else begin
            // 跨时钟域信号同步与按键打拍
            wrfin_tgl_sync    <= {wrfin_tgl_sync[1:0], write_finish_toggle};
            bmp_ready_q       <= bmp_ready;
            scan_done_eff     <= scan_done | scan_abort;
            key_auto_stable_d <= key_auto_stable;

            if (auto_inhibit) auto_play_en <= 1'b0;
            scan_start_pulse  <= 1'b0;
            load_start_pulse  <= 1'b0;
            select_ack        <= 1'b0;

            if (!sd_init_done) begin
                scan_kicked           <= 1'b0;
                first_image_committed <= 1'b0;
                scan_abort            <= 1'b0;
                boot_failed           <= 1'b0;
                preload_idx           <= 3'd0;
                auto_play_en          <= 1'b0;
                auto_cnt              <= 32'd0;
                img_found_count       <= 3'd0;
                img_idx               <= 2'd0;
                load_idx              <= 2'd0;
                image_ready           <= 4'd0;
                write_buf_idx         <= 2'd0;
                disp_buf_idx          <= 2'd0;
                img_index0            <= 2'd0;
                img_index1            <= 2'd0;
                img_index2            <= 2'd0;
                img_index3            <= 2'd0;
                next_req_pending      <= 1'b0;
                prev_req_pending      <= 1'b0;
                load_busy             <= 1'b0;
                load_is_preload       <= 1'b0;
                load_for_display      <= 1'b0;
                source_done_seen      <= 1'b0;
                load_error_seen       <= 1'b0;
                retry_count           <= 2'd0;
                display_valid         <= 1'b0;
                osd_error_code        <= 8'd0;
                osd_error_toggle      <= 1'b0;
                switch_abort_toggle   <= 1'b0;
                long_press_cnt        <= 32'd0;
                long_press_marked     <= 1'b0;
                select_ack            <= 1'b0;
                state_code            <= 4'd0;
            end else begin
                // 1. 扫描匹配结果更新
                if (scan_found_valid) begin
                    case (img_found_count)
                        3'd0: img_index0 <= scan_found_index;
                        3'd1: img_index1 <= scan_found_index;
                        3'd2: img_index2 <= scan_found_index;
                        3'd3: img_index3 <= scan_found_index;
                        default: ;
                    endcase
                    if (img_found_count < 3'd4)
                        img_found_count <= img_found_count + 3'd1;
                end

                // 2. BMP 解码源数据读取结束
                if (load_busy && bmp_ready && !load_error)
                    source_done_seen <= 1'b1;

                // 3. SDRAM 写完成：标记对应bank已加载；需要显示时切换读bank
                if (load_busy && source_done_seen && write_finish_pulse && !load_error) begin
                    load_busy             <= 1'b0;
                    source_done_seen      <= 1'b0;
                    image_ready[load_idx] <= 1'b1;
                    first_image_committed <= 1'b1;
                    boot_failed           <= 1'b0;
                    load_error_seen       <= 1'b0;
                    retry_count           <= 2'd0;
                    if (osd_error_code != media_error) begin
                        osd_error_code   <= media_error;
                        osd_error_toggle <= ~osd_error_toggle;
                    end
                    if (!display_valid || load_for_display) begin
                        img_idx       <= load_idx;
                        disp_buf_idx  <= load_idx;
                        display_valid <= 1'b1;
                    end
                    if (load_is_preload) begin
                        if (load_idx == 2'd3)
                            preload_idx <= 3'd4;
                        else
                            preload_idx <= {1'b0, load_idx} + 3'd1;
                    end
                end

                // 4. 数码管显示内容更新：已进入显示后呈现图片号 1~4，初始化期呈现底层状态码
                if (display_valid)
                    state_code <= {2'b00, img_idx} + 4'd1;
                else
                    state_code <= bmp_internal_state;

                // 5. 扫描与加载调度状态机
                if (!scan_kicked && bmp_ready_q && sdr_init_done) begin
                    // 上电自启动扫描
                    scan_start_pulse      <= 1'b1;
                    scan_kicked           <= 1'b1;
                    first_image_committed <= 1'b0;
                    scan_abort            <= 1'b0;
                    boot_failed           <= 1'b0;
                    preload_idx           <= 3'd0;
                    auto_play_en          <= 1'b0;
                    auto_cnt              <= 32'd0;
                    img_found_count       <= 3'd0;
                    img_idx               <= 2'd0;
                    load_idx              <= 2'd0;
                    image_ready           <= 4'd0;
                    write_buf_idx         <= 2'd0;
                    disp_buf_idx          <= 2'd0;
                    next_req_pending      <= 1'b0;
                    prev_req_pending      <= 1'b0;
                    display_valid         <= 1'b0;
                    load_busy             <= 1'b0;
                    load_is_preload       <= 1'b0;
                    load_for_display      <= 1'b0;
                    source_done_seen      <= 1'b0;
                    load_error_seen       <= 1'b0;
                    retry_count           <= 2'd0;
                end else begin
                    // ---- KEY1: 手动下一张 ----
                    if ((key_next_press || next_event) && scan_done_eff &&
                        (img_found_count > 3'd0))
                        next_req_pending <= 1'b1;

                    // ---- S3: J2 事件"上一张"（与 KEY2 长按同一分支，行为等价）----
                    if (prev_event && scan_done_eff && (img_found_count > 3'd0))
                        prev_req_pending <= 1'b1;

                    // ---- KEY2: 长按(上一张) 与 短按(自动轮播开关) 互斥判定 ----
                    if (key_auto_stable == 1'b0) begin
                        // 按键持续按下
                        if (long_press_cnt < (LONG_PRESS_CYCLES - 1'b1)) begin
                            long_press_cnt <= long_press_cnt + 32'd1;
                        end else if (!long_press_marked) begin
                            // 达到 1 秒长按门限，触发上一张请求
                            long_press_marked <= 1'b1;
                            if (scan_done_eff && (img_found_count > 3'd0))
                                prev_req_pending <= 1'b1;
                        end
                    end else begin
                        // 按键处于松开状态
                        if (key_auto_stable_d == 1'b0) begin
                            // 检测到按键释放沿 (0 -> 1)
                            if (!long_press_marked) begin
                                // 持续时间不足 1 秒，确认为有效短按：翻转自动轮播状态
                                if (scan_done_eff && (img_found_count > 3'd1)) begin
                                    auto_play_en <= ~auto_play_en;
                                    auto_cnt     <= 32'd0;
                                end
                            end
                        end
                        long_press_cnt    <= 32'd0;
                        long_press_marked <= 1'b0;
                    end

                    // ---- 自动轮播计时器 ----
                    if (!auto_inhibit && scan_done_eff && auto_play_en && display_valid && !load_busy &&
                        first_image_committed && (img_found_count > 3'd1)) begin
                        if (auto_tick)
                            auto_cnt <= 32'd0;
                        else
                            auto_cnt <= auto_cnt + 32'd1;
                    end else begin
                        auto_cnt <= 32'd0;
                    end

                    // ---- 图片加载/切换仲裁调度逻辑 ----
                    // 优先级0（第十五讲）：缩略图快速选择。select_req 默认恒为0，
                    // 以下原有仲裁路径在旧功能下保持原行为。
                    if (scan_done_eff && display_valid && !load_busy &&
                        select_req && !select_ack && (img_found_count != 3'd0)) begin
                        auto_cnt <= 32'd0;
                        if (ready_lut(select_index)) begin
                            img_idx      <= select_index;
                            disp_buf_idx <= select_index;
                            select_ack   <= 1'b1;
                            // 选中的就是当前bank时 state_code 不变，转场状态机
                            // 等不到 index_commit；复用已有 abort 脉冲释放它。
                            if (select_index == img_idx)
                                switch_abort_toggle <= ~switch_abort_toggle;
                        end else if (bmp_ready_q) begin
                            load_idx         <= select_index;
                            load_index       <= select_index;
                            write_buf_idx    <= select_index;
                            load_start_pulse <= 1'b1;
                            load_busy        <= 1'b1;
                            load_is_preload  <= 1'b0;
                            load_for_display <= 1'b1;
                            source_done_seen <= 1'b0;
                            load_error_seen  <= 1'b0;
                            retry_count      <= 2'd0;
                            select_ack       <= 1'b1;
                        end
                    end
                    // 优先级1：手动下一张。已加载bank零延迟切换；未加载bank则加载后再切换。
                    else if (scan_done_eff && display_valid && !load_busy &&
                        next_req_pending && (img_found_count != 3'd0)) begin
                        next_req_pending <= 1'b0;
                        auto_cnt         <= 32'd0;
                        if (ready_lut(next_from_current)) begin
                            img_idx      <= next_from_current;
                            disp_buf_idx <= next_from_current;
                        end else if (bmp_ready_q) begin
                            load_idx         <= next_from_current;
                            load_index       <= next_from_current;
                            write_buf_idx    <= next_from_current;
                            load_start_pulse <= 1'b1;
                            load_busy        <= 1'b1;
                            load_is_preload  <= 1'b0;
                            load_for_display <= 1'b1;
                            source_done_seen <= 1'b0;
                            load_error_seen  <= 1'b0;
                            retry_count      <= 2'd0;
                        end
                    end
                    // 优先级2：手动上一张（KEY2长按）。
                    else if (scan_done_eff && display_valid && !load_busy &&
                             prev_req_pending && (img_found_count != 3'd0)) begin
                        prev_req_pending <= 1'b0;
                        auto_cnt         <= 32'd0;
                        if (ready_lut(prev_from_current)) begin
                            img_idx      <= prev_from_current;
                            disp_buf_idx <= prev_from_current;
                        end else if (bmp_ready_q) begin
                            load_idx         <= prev_from_current;
                            load_index       <= prev_from_current;
                            write_buf_idx    <= prev_from_current;
                            load_start_pulse <= 1'b1;
                            load_busy        <= 1'b1;
                            load_is_preload  <= 1'b0;
                            load_for_display <= 1'b1;
                            source_done_seen <= 1'b0;
                            load_error_seen  <= 1'b0;
                            retry_count      <= 2'd0;
                        end
                    end
                    // 优先级3：自动轮播。已加载bank直接切换，避免重新读卡。
                    else if (scan_done_eff && display_valid && !load_busy &&
                             !auto_inhibit && auto_play_en && auto_tick && (img_found_count > 3'd1)) begin
                        auto_cnt <= 32'd0;
                        if (ready_lut(next_from_current)) begin
                            img_idx      <= next_from_current;
                            disp_buf_idx <= next_from_current;
                        end else if (bmp_ready_q) begin
                            load_idx         <= next_from_current;
                            load_index       <= next_from_current;
                            write_buf_idx    <= next_from_current;
                            load_start_pulse <= 1'b1;
                            load_busy        <= 1'b1;
                            load_is_preload  <= 1'b0;
                            load_for_display <= 1'b1;
                            source_done_seen <= 1'b0;
                            load_error_seen  <= 1'b0;
                            retry_count      <= 2'd0;
                        end
                    end
                    // 优先级4：后台顺序预加载四个bank。首图加载完成后立即显示，
                    // 其余图片在后台装入各自固定bank，后续切换不再访问TF卡。
                    else if (scan_done_eff && bmp_ready_q && !load_busy &&
                             (preload_idx < img_found_count)) begin
                        if (!ready_lut(preload_idx[1:0])) begin
                            load_idx         <= preload_idx[1:0];
                            load_index       <= preload_idx[1:0];
                            write_buf_idx    <= preload_idx[1:0];
                            load_start_pulse <= 1'b1;
                            load_busy        <= 1'b1;
                            load_is_preload  <= 1'b1;
                            load_for_display <= 1'b0;
                            source_done_seen <= 1'b0;
                            load_error_seen  <= 1'b0;
                            retry_count      <= 2'd0;
                        end else begin
                            preload_idx <= preload_idx + 3'd1;
                        end
                    end
                end

                // Report scan/index errors even when no BMP load was launched.
                // Keep legacy load_error retry semantics separate from diagnostics.
                if (media_error != 8'd0 && osd_error_code != media_error) begin
                    osd_error_code <= media_error;
                    osd_error_toggle <= ~osd_error_toggle;
                end

                // 6. 稳定性错误恢复（最高优先级，放在本轮普通调度之后覆盖写）
                //    扫描超时：重试一次；仍失败则强制结束扫描，避免永久停在 scan_done=0。
                //    加载错误：重试当前图一次；仍失败则保留上一帧并跳过。
                if (load_error && !load_error_seen) begin
                    osd_error_code   <= {4'b0000, bmp_error};
                    osd_error_toggle <= ~osd_error_toggle;
                    if (!scan_done && !scan_abort) begin
                        if (retry_count < MAX_RETRIES) begin
                            retry_count      <= retry_count + 2'd1;
                            img_found_count  <= 3'd0;
                            scan_start_pulse <= 1'b1;
                            scan_abort       <= 1'b0;
                            boot_failed      <= 1'b0;
                            preload_idx      <= 3'd0;
                            image_ready      <= 4'd0;
                            load_busy        <= 1'b0;
                            source_done_seen <= 1'b0;
                            load_error_seen  <= 1'b0;
                        end else begin
                            scan_abort       <= 1'b1;
                            load_busy        <= 1'b0;
                            source_done_seen <= 1'b0;
                            retry_count      <= 2'd0;
                            load_error_seen  <= 1'b1;
                            if (img_found_count == 3'd0)
                                boot_failed <= 1'b1;
                        end
                    end else begin
                        if (retry_count < MAX_RETRIES) begin
                            retry_count      <= retry_count + 2'd1;
                            load_start_pulse <= 1'b1;
                            load_busy        <= 1'b1;
                            source_done_seen <= 1'b0;
                            load_error_seen  <= 1'b0;
                        end else begin
                            load_busy        <= 1'b0;
                            source_done_seen <= 1'b0;
                            next_req_pending <= 1'b0;
                            prev_req_pending <= 1'b0;
                            auto_cnt         <= 32'd0;
                            retry_count      <= 2'd0;
                            load_error_seen  <= 1'b1;
                            if (load_for_display && !load_is_preload)
                                switch_abort_toggle <= ~switch_abort_toggle;
                            // 预加载失败时跳过该图，继续尝试后续bank；
                            // 手动切换失败时保留当前画面，不破坏已有显示。
                            if (load_is_preload) begin
                                if (load_idx == 2'd3)
                                    preload_idx <= 3'd4;
                                else
                                    preload_idx <= {1'b0, load_idx} + 3'd1;
                            end
                            if (!display_valid && (preload_idx >= img_found_count))
                                boot_failed <= 1'b1;
                            end
                        end
                    end
                end
            end
        end

    // =========================================================================
    // 实例化消抖模块
    // =========================================================================
    key_press_debounce #(
        .CLK_FREQ_HZ (CLK_FREQ_HZ),
        .DEBOUNCE_MS (20)
    ) u_key_next (
        .clk              (clk),
        .rst              (rst),
        .button_in        (key_next),
        .press_pulse      (key_next_press),
        .button_stable_out()
    );

    key_press_debounce #(
        .CLK_FREQ_HZ (CLK_FREQ_HZ),
        .DEBOUNCE_MS (20)
    ) u_key_auto (
        .clk              (clk),
        .rst              (rst),
        .button_in        (key_auto),
        .press_pulse      (key_auto_press),
        .button_stable_out(key_auto_stable) // 引出消抖后电平供长按状态机采样
    );

    // =========================================================================
    // 底层子模块例化：第七讲用 FAT32 加载器替换 bmp_read。
    // =========================================================================
    fat32_media_loader fat32_media_loader_m0 (
        .clk                    (clk),
        .rst                    (rst),
        .ready                  (bmp_ready),
        .scan_start             (scan_start_pulse),
        .scan_done              (scan_done),
        .storage_done           (storage_done),
        .storage_error          (storage_error),
        .media_status           (media_status),
        .media_error            (media_error),
        .scan_found_valid       (scan_found_valid),
        .scan_found_index       (scan_found_index),
        .scan_found_total       (scan_found_total),
        .load_start             (load_start_pulse),
        .load_index             (load_index),
        .sd_init_done           (sd_init_done),
        .state_code             (bmp_internal_state), // 改接内部 wire
        .bmp_width              (bmp_width),
        .bmp_height             (bmp_height),
        .song_sel               (song_sel),
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
        .mv_metadata            (mv_metadata),
        .audio_file_valid       (audio_file_valid),
        .audio_start_lba        (audio_start_lba),
        .audio_total_sectors    (audio_total_sectors),
        .audio_size_bytes       (audio_size_bytes),
        .audio_sec_req          (audio_sec_req),
        .audio_sec_lba          (audio_sec_lba),
        .audio_sec_busy         (audio_sec_busy),
        .audio_sec_valid        (audio_sec_valid),
        .audio_sec_byte         (audio_sec_byte),
        .audio_sec_byte_index   (audio_sec_byte_index),
        .audio_sec_done         (audio_sec_done),
        .audio_sec_error        (audio_sec_error)
    );

    sd_card_top sd_card_top_m0(
        .clk                    (clk),
        .rst                    (rst),
        .SD_nCS                 (SD_nCS),
        .SD_DCLK                (SD_DCLK),
        .SD_MOSI                (SD_MOSI),
        .SD_MISO                (SD_MISO),
        .sd_init_done           (sd_init_done),
        .sd_sec_read            (sd_sec_read),
        .sd_sec_read_addr       (sd_sec_read_addr),
        .sd_sec_read_data       (sd_sec_read_data),
        .sd_sec_read_data_valid (sd_sec_read_data_valid),
        .sd_sec_read_end        (sd_sec_read_end),
        .sd_sec_write           (1'b0),
        .sd_sec_write_addr      (32'd0),
        .sd_sec_write_data      (),
        .sd_sec_write_data_req  (),
        .sd_sec_write_end       ()
    );

endmodule


// =============================================================================
// 按键消抖模块 (升级版：新增输出消抖后电平 button_stable_out)
// =============================================================================
module key_press_debounce #(
    parameter integer CLK_FREQ_HZ = 100_000_000,
    parameter integer DEBOUNCE_MS = 20
)(
    input  wire clk,
    input  wire rst,
    input  wire button_in,
    output reg  press_pulse,
    output reg  button_stable_out // 1=松开, 0=按下
);

    localparam integer DEBOUNCE_CYCLES = (CLK_FREQ_HZ / 1000) * DEBOUNCE_MS;

    reg button_sync0;
    reg button_sync1;
    reg button_stable;
    reg [31:0] cnt;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            button_sync0      <= 1'b1;
            button_sync1      <= 1'b1;
            button_stable     <= 1'b1;
            button_stable_out <= 1'b1;
            cnt               <= 32'd0;
            press_pulse       <= 1'b0;
        end else begin
            button_sync0 <= button_in;
            button_sync1 <= button_sync0;
            press_pulse  <= 1'b0;

            if (button_sync1 == button_stable) begin
                cnt <= 32'd0;
            end else begin
                if (cnt >= DEBOUNCE_CYCLES - 1'b1) begin
                    if (button_stable && !button_sync1)
                        press_pulse <= 1'b1;
                    button_stable     <= button_sync1;
                    button_stable_out <= button_sync1;
                    cnt               <= 32'd0;
                end else begin
                    cnt <= cnt + 32'd1;
                end
            end
        end
    end

endmodule

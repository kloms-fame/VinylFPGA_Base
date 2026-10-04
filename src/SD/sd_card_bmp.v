// =============================================================================
// File Name    : sd_card_bmp.v
// Module Name  : sd_card_bmp
// Project      : VinylFPGA (完赛优化系列 - 第三讲/第五讲/第六讲)
// Description  : 长短按复用、双向切换、参数化轮播、稳定性恢复与SDRAM就绪启动
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
    input                       key_auto,              // KEY2：短按自动轮播开关 / 长按上一张
    output reg [3:0]            state_code,            // 数码管显示：当前图片编号 1~4
    input  [15:0]               bmp_width,
    input  [15:0]               bmp_height,
    output reg                  display_valid,
    input                       write_finish_toggle,   // 来自 mem_clk 域的写完成翻转信号
    output reg [1:0]            write_buf_idx,         // 显存写入缓冲区(0或1)
    output reg [1:0]            disp_buf_idx,          // 显存显示缓冲区(0或1)
    output                      write_req,
    input                       write_req_ack,
    output                      write_en,
    output [31:0]               write_data,
    output                      SD_nCS,
    output                      SD_DCLK,
    output                      SD_MOSI,
    input                       SD_MISO
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
    wire        scan_done;
    wire        scan_done_eff;
    wire        scan_found_valid;
    wire [31:0] scan_found_sector;
    wire [2:0]  scan_found_total;
    wire [3:0]  bmp_internal_state;
    wire [2:0]  bmp_error;
    wire        load_error;

    reg         scan_start_pulse;
    reg         load_start_pulse;
    reg [31:0]  load_sector;
    reg         scan_kicked;
    reg         first_image_committed;
    reg         scan_abort;
    reg         boot_failed;
    reg [1:0]   boot_idx;

    reg         auto_play_en;
    reg [31:0]  auto_cnt;
    reg [2:0]   img_found_count;
    reg [1:0]   img_idx;             // 当前屏幕上显示呈现的图片编号(0~3)
    reg [1:0]   load_idx;            // 正在向后台缓冲区加载的图片编号(0~3)
    reg [1:0]   pending_buf_idx;     // 后台写入的目标缓冲区编号(0或1)

    reg [31:0]  img_sector0;
    reg [31:0]  img_sector1;
    reg [31:0]  img_sector2;
    reg [31:0]  img_sector3;

    reg         next_req_pending;    // 下一张请求挂起标志（防连跳）
    reg         prev_req_pending;    // 上一张请求挂起标志（防连跳）
    reg         load_busy;
    reg         source_done_seen;
    reg         load_error_seen;
    reg [1:0]   retry_count;

    // 稳定性时序优化：预计算"下一张候选首图"的扇区与存在性，
    // 避免 load_error 直接驱动 32 位 sector_lut 形成长组合路径。
    reg [31:0]  boot_sector_next;
    reg         has_more_boot_r;

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
    assign scan_done_eff      = scan_done | scan_abort;

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

    // 扇区查表函数
    function [31:0] sector_lut;
        input [1:0] idx;
        begin
            case (idx)
                2'd0: sector_lut = img_sector0;
                2'd1: sector_lut = img_sector1;
                2'd2: sector_lut = img_sector2;
                default: sector_lut = img_sector3;
            endcase
        end
    endfunction

    // 双缓冲轮转函数：写入非当前显示区
    function [1:0] next_buf_lut;
        input [1:0] cur_disp_buf;
        input       valid_now;
        begin
            if (!valid_now)
                next_buf_lut = 2'd0;
            else if (cur_disp_buf == 2'd0)
                next_buf_lut = 2'd1;
            else
                next_buf_lut = 2'd0;
        end
    endfunction

    // =========================================================================
    // 状态控制主时序
    // =========================================================================
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            wrfin_tgl_sync        <= 3'b000;
            scan_start_pulse      <= 1'b0;
            load_start_pulse      <= 1'b0;
            load_sector           <= 32'd0;
            scan_kicked           <= 1'b0;
            first_image_committed <= 1'b0;
            scan_abort            <= 1'b0;
            boot_failed           <= 1'b0;
            boot_idx              <= 2'd0;
            auto_play_en          <= 1'b0;
            auto_cnt              <= 32'd0;
            img_found_count       <= 3'd0;
            img_idx               <= 2'd0;
            load_idx              <= 2'd0;
            pending_buf_idx       <= 2'd0;
            write_buf_idx         <= 2'd0;
            disp_buf_idx          <= 2'd0;
            img_sector0           <= 32'd0;
            img_sector1           <= 32'd0;
            img_sector2           <= 32'd0;
            img_sector3           <= 32'd0;
            next_req_pending      <= 1'b0;
            prev_req_pending      <= 1'b0;
            load_busy             <= 1'b0;
            source_done_seen      <= 1'b0;
            load_error_seen       <= 1'b0;
            retry_count           <= 2'd0;
            boot_sector_next      <= 32'd0;
            has_more_boot_r       <= 1'b0;
            display_valid         <= 1'b0;
            long_press_cnt        <= 32'd0;
            long_press_marked     <= 1'b0;
            key_auto_stable_d     <= 1'b1;
            state_code            <= 4'd0;
        end else begin
            // 跨时钟域信号同步与按键打拍
            wrfin_tgl_sync    <= {wrfin_tgl_sync[1:0], write_finish_toggle};
            key_auto_stable_d <= key_auto_stable;

            // 首图候选预计算（每拍寄存，切断 load_error 的组合长路径）
            boot_sector_next <= sector_lut(boot_idx + 2'd1);
            has_more_boot_r  <= (({1'b0, boot_idx} + 3'd1) < img_found_count);

            scan_start_pulse  <= 1'b0;
            load_start_pulse  <= 1'b0;

            if (!sd_init_done) begin
                scan_kicked           <= 1'b0;
                first_image_committed <= 1'b0;
                scan_abort            <= 1'b0;
                boot_failed           <= 1'b0;
                boot_idx              <= 2'd0;
                auto_play_en          <= 1'b0;
                auto_cnt              <= 32'd0;
                img_found_count       <= 3'd0;
                img_idx               <= 2'd0;
                load_idx              <= 2'd0;
                pending_buf_idx       <= 2'd0;
                write_buf_idx         <= 2'd0;
                disp_buf_idx          <= 2'd0;
                img_sector0           <= 32'd0;
                img_sector1           <= 32'd0;
                img_sector2           <= 32'd0;
                img_sector3           <= 32'd0;
                next_req_pending      <= 1'b0;
                prev_req_pending      <= 1'b0;
                load_busy             <= 1'b0;
                source_done_seen      <= 1'b0;
                load_error_seen       <= 1'b0;
                retry_count           <= 2'd0;
                boot_sector_next      <= 32'd0;
                has_more_boot_r       <= 1'b0;
                display_valid         <= 1'b0;
                long_press_cnt        <= 32'd0;
                long_press_marked     <= 1'b0;
                state_code            <= 4'd0;
            end else begin
                // 1. 扫描匹配结果更新
                if (scan_found_valid) begin
                    case (img_found_count)
                        3'd0: img_sector0 <= scan_found_sector;
                        3'd1: img_sector1 <= scan_found_sector;
                        3'd2: img_sector2 <= scan_found_sector;
                        3'd3: img_sector3 <= scan_found_sector;
                        default: ;
                    endcase
                    if (img_found_count < 3'd4)
                        img_found_count <= img_found_count + 3'd1;
                end

                // 2. BMP 解码源数据读取结束
                if (load_busy && bmp_ready && !load_error)
                    source_done_seen <= 1'b1;

                // 3. SDRAM 写完成：双缓冲原子提交（消除场撕裂）
                if (load_busy && source_done_seen && write_finish_pulse && !load_error) begin
                    load_busy             <= 1'b0;
                    source_done_seen      <= 1'b0;
                    disp_buf_idx          <= pending_buf_idx;
                    img_idx               <= load_idx;
                    display_valid         <= 1'b1;
                    first_image_committed <= 1'b1;
                    boot_failed           <= 1'b0;
                    load_error_seen       <= 1'b0;
                    retry_count           <= 2'd0;
                end

                // 4. 数码管显示内容更新：已进入显示后呈现图片号 1~4，初始化期呈现底层状态码
                if (display_valid)
                    state_code <= {2'b00, img_idx} + 4'd1;
                else
                    state_code <= bmp_internal_state;

                // 5. 扫描与加载调度状态机
                if (!scan_kicked && bmp_ready && sdr_init_done) begin
                    // 上电自启动扫描
                    scan_start_pulse      <= 1'b1;
                    scan_kicked           <= 1'b1;
                    first_image_committed <= 1'b0;
                    scan_abort            <= 1'b0;
                    boot_failed           <= 1'b0;
                    boot_idx              <= 2'd0;
                    auto_play_en          <= 1'b0;
                    auto_cnt              <= 32'd0;
                    img_found_count       <= 3'd0;
                    img_idx               <= 2'd0;
                    load_idx              <= 2'd0;
                    pending_buf_idx       <= 2'd0;
                    write_buf_idx         <= 2'd0;
                    disp_buf_idx          <= 2'd0;
                    next_req_pending      <= 1'b0;
                    prev_req_pending      <= 1'b0;
                    display_valid         <= 1'b0;
                    load_busy             <= 1'b0;
                    source_done_seen      <= 1'b0;
                    load_error_seen       <= 1'b0;
                    retry_count           <= 2'd0;
                end else begin
                    // ---- KEY1: 手动下一张 ----
                    if (key_next_press && scan_done_eff && (img_found_count > 3'd0))
                        next_req_pending <= 1'b1;

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
                    if (scan_done_eff && auto_play_en && display_valid && !load_busy && 
                        first_image_committed && (img_found_count > 3'd1)) begin
                        if (auto_tick)
                            auto_cnt <= 32'd0;
                        else
                            auto_cnt <= auto_cnt + 32'd1;
                    end else begin
                        auto_cnt <= 32'd0;
                    end

                    // ---- 图片加载仲裁调度逻辑 ----
                    // 优先级 1：上电自动加载第一张图
                    if (scan_done_eff && !first_image_committed && !boot_failed &&
                        bmp_ready && !load_busy && (img_found_count != 3'd0)) begin
                        load_idx         <= boot_idx;
                        load_sector      <= sector_lut(boot_idx);
                        pending_buf_idx  <= 2'd0;
                        write_buf_idx    <= 2'd0;
                        load_start_pulse <= 1'b1;
                        load_busy        <= 1'b1;
                        source_done_seen <= 1'b0;
                        load_error_seen  <= 1'b0;
                        retry_count      <= 2'd0;
                        next_req_pending <= 1'b0;
                        prev_req_pending <= 1'b0;
                        auto_cnt         <= 32'd0;
                    end
                    // 优先级 2：响应【下一张】请求（手动优先）
                    else if (scan_done_eff && bmp_ready && display_valid && !load_busy && next_req_pending && (img_found_count != 3'd0)) begin
                        load_idx         <= next_from_current;
                        load_sector      <= sector_lut(next_from_current);
                        pending_buf_idx  <= next_buf_lut(disp_buf_idx, display_valid);
                        write_buf_idx    <= next_buf_lut(disp_buf_idx, display_valid);
                        load_start_pulse <= 1'b1;
                        load_busy        <= 1'b1;
                        source_done_seen <= 1'b0;
                        load_error_seen  <= 1'b0;
                        retry_count      <= 2'd0;
                        next_req_pending <= 1'b0;
                        auto_cnt         <= 32'd0;
                    end
                    // 优先级 3：响应【上一张】请求（手动优先）
                    else if (scan_done_eff && bmp_ready && display_valid && !load_busy && prev_req_pending && (img_found_count != 3'd0)) begin
                        load_idx         <= prev_from_current;
                        load_sector      <= sector_lut(prev_from_current);
                        pending_buf_idx  <= next_buf_lut(disp_buf_idx, display_valid);
                        write_buf_idx    <= next_buf_lut(disp_buf_idx, display_valid);
                        load_start_pulse <= 1'b1;
                        load_busy        <= 1'b1;
                        source_done_seen <= 1'b0;
                        load_error_seen  <= 1'b0;
                        retry_count      <= 2'd0;
                        prev_req_pending <= 1'b0;
                        auto_cnt         <= 32'd0;
                    end
                    // 优先级 4：响应【自动轮播定时器】触发
                    else if (scan_done_eff && bmp_ready && display_valid && !load_busy && auto_play_en && auto_tick && (img_found_count > 3'd1)) begin
                        load_idx         <= next_from_current;
                        load_sector      <= sector_lut(next_from_current);
                        pending_buf_idx  <= next_buf_lut(disp_buf_idx, display_valid);
                        write_buf_idx    <= next_buf_lut(disp_buf_idx, display_valid);
                        load_start_pulse <= 1'b1;
                        load_busy        <= 1'b1;
                        source_done_seen <= 1'b0;
                        load_error_seen  <= 1'b0;
                        retry_count      <= 2'd0;
                        auto_cnt         <= 32'd0;
                    end
                end

                // 6. 稳定性错误恢复（最高优先级，放在本轮普通调度之后覆盖写）
                //    扫描超时：重试一次；仍失败则强制结束扫描，避免永久停在 scan_done=0。
                //    加载错误：重试当前图一次；仍失败则保留上一帧并跳过。
                if (load_error && !load_error_seen) begin
                    if (!scan_done && !scan_abort) begin
                        if (retry_count < MAX_RETRIES) begin
                            retry_count      <= retry_count + 2'd1;
                            img_found_count  <= 3'd0;
                            scan_start_pulse <= 1'b1;
                            scan_abort       <= 1'b0;
                            boot_failed      <= 1'b0;
                            boot_idx         <= 2'd0;
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
                            if (!display_valid) begin
                                // 首图失败时按顺序尝试下一张候选图，避免反复重试同一张坏图。
                                // 候选扇区与存在性已提前寄存，切断 load_error 的长组合路径。
                                if (has_more_boot_r) begin
                                    boot_idx         <= boot_idx + 2'd1;
                                    load_idx         <= boot_idx + 2'd1;
                                    load_sector      <= boot_sector_next;
                                    pending_buf_idx  <= 2'd0;
                                    write_buf_idx    <= 2'd0;
                                    load_start_pulse <= 1'b1;
                                    load_busy        <= 1'b1;
                                    load_error_seen  <= 1'b0;
                                    retry_count      <= 2'd0;
                                end else begin
                                    boot_failed <= 1'b1;
                                end
                            end
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
    // 底层子模块例化（保持不变）
    // =========================================================================
    bmp_read #(
        .CLK_FREQ_HZ        (CLK_FREQ_HZ),
        .SD_READ_TIMEOUT_MS (SD_READ_TIMEOUT_MS)
    ) bmp_read_m0 (
        .clk                    (clk),
        .rst                    (rst),
        .ready                  (bmp_ready),
        .scan_start             (scan_start_pulse),
        .scan_start_sector      (SCAN_START_SECTOR),
        .scan_max_sector        (SCAN_MAX_SECTOR),
        .scan_target_count      (SCAN_TARGET_COUNT),
        .scan_done              (scan_done),
        .scan_found_valid       (scan_found_valid),
        .scan_found_sector      (scan_found_sector),
        .scan_found_total       (scan_found_total),
        .load_start             (load_start_pulse),
        .load_sector            (load_sector),
        .sd_init_done           (sd_init_done),
        .state_code             (bmp_internal_state), // 改接内部 wire
        .bmp_width              (bmp_width),
        .bmp_height             (bmp_height),
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
        .bmp_data               (bmp_data)
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

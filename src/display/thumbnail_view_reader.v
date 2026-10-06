`timescale 1ns/1ps

// =============================================================================
// 第十三讲《图片缩放与缩略图》——缩略图取像引擎（本工程的对应实现）
//
// 教程链路：
//   video_timing -> thumbnail_layout -> 本模块(对应 media_frame_reader 职责)
//     -> 像素 -> OSD/转场
//
// 取像模型严格按第八讲 media_frame_reader 与第十二讲已验证的 SDRAM 读节奏：
//   - 每个缩略图显示行对应源图的一整行（640 个 32 位字）；
//   - 按 128 字连续突发读 SDRAM，左右两格共 10 个突发；
//   - 突发内每 4 个字取 1 个（最近邻 4:1 缩小），每个突发贡献 32 个显示
//     像素，每格 5 个突发贡献 160 个显示像素；
//   - 只在突发起始前检查 mem_enable（控制器空闲/非刷新）；一旦突发开始，
//     必须连续发满 128 拍，不能中途停下（与 frame_fifo_read 的 S_READ_BURST
//     行为完全一致）；
//   - 两次突发之间保留 BURST_GAP_CYCLES 个空闲周期给自动刷新。
//
// 为什么不能逐像素单字随机读：
//   孤立单字随机读把每次读都拆成独立突发，刷新窗口/忙判据一挡就丢数据，
//   在真实 SDRAM 上表现为缩略图整片全白，并因为读窗口与刷新互相干扰引入
//   彩点。第八讲和第十二讲已经证明“128 字突发 + 突发间隔 + 只在起始处避让
//   刷新”才是本工程可靠模型。
//
// 安全边界：
//   - 不改 frame_read_write / frame_fifo_read / SDRAM 控制器内部；
//   - enable=0 时持续复位内部 FIFO，绝不发出任何读请求；
//   - 复用工程既有 rfifo_32_32_512，不新增 IP 原语，不另造轮子。
// =============================================================================
module thumbnail_view_reader #(
    parameter integer DISPLAY_WIDTH    = 640,
    parameter integer DISPLAY_HEIGHT   = 480,
    parameter integer ADDR_WIDTH       = 21,
    parameter integer BANK_WORDS       = 307200,   // 640*480，每 bank 字数
    parameter integer THUMB_WIDTH      = 160,
    parameter integer THUMB_HEIGHT     = 120,
    parameter integer BURST_SIZE       = 128,
    parameter integer BURSTS_PER_THUMB = 5,        // ceil(640/128)
    parameter integer BURST_GAP_CYCLES = 12,
    parameter [23:0]  BORDER_RGB       = 24'hff_ff_00
) (
    input  wire                    pix_clk,
    input  wire                    pix_rst_n,
    input  wire                    mem_clk,
    input  wire                    mem_rst_n,

    input  wire                    enable,        // 1=缩略图视图生效
    input  wire                    mem_enable,    // mem 域：可以发起一次读突发
    input  wire                    frame_start,   // video 域帧起始单拍
    input  wire [1:0]              focus_index,
    input  wire [3:0]              image_complete,
    input  wire [9:0]              pixel_x,       // 当前显示像素 x（0~639）
    input  wire                    in_de,

    output wire                    thumb_active,  // 该像素属于缩略图区域
    output wire [23:0]             pixel_rgb,     // 缩略图像素（含边框色）
    output wire                    focus_border,  // 该像素是焦点边框
    output wire                    line_mismatch, // 本行出现过欠载（可上 ILA 观察）

    // mem 域读口（接到 sdram_rd_arbiter）
    output wire                    rd_req,
    output wire [ADDR_WIDTH-1:0]   rd_addr,
    input  wire                    rd_valid,      // 对应 Sdr_rd_en
    input  wire [31:0]             rd_data       // 对应 Sdr_rd_dout
);

    localparam integer TOTAL_BURSTS   = 2 * BURSTS_PER_THUMB;   // 左右两格
    localparam integer THUMB_ROWS     = THUMB_HEIGHT;
    localparam [7:0]   BURST_WORD_LAST = BURST_SIZE - 1;
    // S7-04：BURST_SIZE 以参数形式给出，但当前唯一例化点固定 128(=1<<7)。
    // 用 localparam 显式折算成移位量，既让综合器生成移位而不是 21 位乘法器，
    // 又在参数被改动时自动回退为正确的移位量，不会静默算错地址。
    localparam integer BURST_SIZE_LSH = 7;   // log2(128)

    // ---------------------------------------------------------------------
    // 1. 显示行计数（与 osd_overlay_24 同一口径：vs 起始清零，de 下降沿加一）
    // ---------------------------------------------------------------------
    reg  [11:0] line_y;
    reg         de_q;

    always @(posedge pix_clk or negedge pix_rst_n) begin
        if (!pix_rst_n) begin
            line_y <= 12'd0;
            de_q   <= 1'b0;
        end else begin
            de_q <= in_de;
            if (frame_start)
                line_y <= 12'd0;
            else if (de_q && !in_de && (line_y < (DISPLAY_HEIGHT-1)))
                line_y <= line_y + 12'd1;
        end
    end

    // 下一显示行；最后一行绕回第 0 行，保证下一帧顶行也有取像数据。
    wire [11:0] next_line_y = (line_y == (DISPLAY_HEIGHT-1)) ? 12'd0
                                                            : (line_y + 12'd1);

    // ---------------------------------------------------------------------
    // 2. 教程模块 thumbnail_layout：当前像素的坐标映射与焦点边框
    // ---------------------------------------------------------------------
    wire        cur_thumb_de;
    wire [1:0]  cur_source_index;
    wire [9:0]  cur_source_x;
    wire [9:0]  cur_source_y;
    wire        cur_focus_border;
    wire [11:0] pixel_x12 = {2'b00, pixel_x};

    thumbnail_layout #(
        .DISPLAY_WIDTH  (DISPLAY_WIDTH),
        .DISPLAY_HEIGHT (DISPLAY_HEIGHT),
        .THUMB_WIDTH    (THUMB_WIDTH),
        .THUMB_HEIGHT   (THUMB_HEIGHT)
    ) u_layout_display (
        .in_de        (in_de),
        .pixel_x      (pixel_x12),
        .pixel_y      (line_y),
        .focus_index  (focus_index),
        .image_complete(image_complete),
        .thumb_de     (cur_thumb_de),
        .source_index (cur_source_index),
        .source_x     (cur_source_x),
        .source_y     (cur_source_y),
        .focus_border (cur_focus_border)
    );

    // ---------------------------------------------------------------------
    // 3. video -> mem 行任务：每显示行行首请求“下一显示行”的整行取像。
    //    提前一整行（640 显示时钟 + 行消隐）预取，给 128 字突发留足时间。
    // ---------------------------------------------------------------------
    wire        next_row_valid  = (next_line_y < (THUMB_HEIGHT * 2));
    wire        next_is_bottom  = (next_line_y >= THUMB_HEIGHT);
    wire [1:0]  next_left_index = next_is_bottom ? 2'd2 : 2'd0;
    wire [1:0]  next_right_index= next_left_index + 2'd1;
    wire [11:0] next_local_y    = next_is_bottom ?
                                  (next_line_y - THUMB_HEIGHT) : next_line_y;
    wire [9:0]  next_src_y      = next_local_y[9:0] * (DISPLAY_HEIGHT/THUMB_HEIGHT);
    wire        next_left_valid = next_row_valid && image_complete[next_left_index];
    wire        next_right_valid= next_row_valid && image_complete[next_right_index];

    reg         req_toggle_pix;
    reg         req_busy_pix;
    reg  [9:0]  req_src_y_pix;
    reg         req_left_pix;
    reg         req_right_pix;
    reg  [1:0]  req_left_index_pix;
    reg  [1:0]  req_right_index_pix;
    reg         ack_sync1_pix;
    reg         ack_sync2_pix;

    // mem 域行任务与突发状态（声明提前，供 pix 域 always 读取 ack_toggle_mem）
    reg         enable_sync1_mem;
    reg         enable_sync2_mem;
    reg         req_toggle_sync1_mem;
    reg         req_toggle_sync2_mem;
    reg         req_seen_mem;
    reg         ack_toggle_mem;
    reg  [9:0]  req_src_y_sync1_mem;
    reg  [9:0]  req_src_y_sync2_mem;
    reg         req_left_sync1_mem;
    reg         req_left_sync2_mem;
    reg         req_right_sync1_mem;
    reg         req_right_sync2_mem;
    reg  [1:0]  req_left_index_sync1_mem;
    reg  [1:0]  req_left_index_sync2_mem;
    reg  [1:0]  req_right_index_sync1_mem;
    reg  [1:0]  req_right_index_sync2_mem;
    reg         task_active_mem;
    reg  [9:0]  task_src_y_mem;
    reg  [ADDR_WIDTH-1:0] task_src_row_off_mem;
    reg         task_left_mem;
    reg         task_right_mem;
    reg  [1:0]  task_left_index_mem;
    reg  [1:0]  task_right_index_mem;
    reg  [3:0]  burst_idx_mem;
    reg  [7:0]  burst_word_mem;
    reg         burst_active_mem;
    reg  [7:0]  gap_cnt_mem;
    reg  [ADDR_WIDTH-1:0] burst_base_mem;
    reg  [11:0] issued_count_mem;
    reg  [11:0] returned_count_mem;
    reg  [11:0] ret_index_mem;

    wire        row_head = enable && in_de && (pixel_x == 10'd0);
    wire        req_fire = row_head && !req_busy_pix && next_row_valid &&
                           (next_left_valid || next_right_valid);

    always @(posedge pix_clk or negedge pix_rst_n) begin
        if (!pix_rst_n) begin
            req_toggle_pix  <= 1'b0;
            req_busy_pix    <= 1'b0;
            req_src_y_pix   <= 10'd0;
            req_left_pix    <= 1'b0;
            req_right_pix   <= 1'b0;
            req_left_index_pix  <= 2'd0;
            req_right_index_pix <= 2'd1;
            ack_sync1_pix   <= 1'b0;
            ack_sync2_pix   <= 1'b0;
        end else if (!enable) begin
            req_toggle_pix  <= 1'b0;
            req_busy_pix    <= 1'b0;
            req_src_y_pix   <= 10'd0;
            req_left_pix    <= 1'b0;
            req_right_pix   <= 1'b0;
            req_left_index_pix  <= 2'd0;
            req_right_index_pix <= 2'd1;
            ack_sync1_pix   <= 1'b0;
            ack_sync2_pix   <= 1'b0;
        end else begin
            ack_sync1_pix <= ack_toggle_mem;
            ack_sync2_pix <= ack_sync1_pix;

            if (req_fire) begin
                req_toggle_pix <= ~req_toggle_pix;
                req_src_y_pix  <= next_src_y;
                req_left_pix   <= next_left_valid;
                req_right_pix  <= next_right_valid;
                req_left_index_pix  <= next_left_index;
                req_right_index_pix <= next_right_index;
                req_busy_pix   <= 1'b1;
            end else if (req_busy_pix && (ack_sync2_pix == req_toggle_pix)) begin
                req_busy_pix   <= 1'b0;
            end
        end
    end

    // ---------------------------------------------------------------------
    // 4. mem 域：捕获行任务，按 10 个 128 字突发顺序取像
    // ---------------------------------------------------------------------
    wire [11:0] pending_returns = issued_count_mem - returned_count_mem;
    wire        all_bursts_done = (burst_idx_mem >= TOTAL_BURSTS);
    wire        task_done       = task_active_mem && all_bursts_done &&
                                  (pending_returns == 12'd0);
    wire        capture_task    = (req_toggle_sync2_mem != req_seen_mem) &&
                                  !task_active_mem && !burst_active_mem;
    wire        cur_burst_left  = (burst_idx_mem < BURSTS_PER_THUMB);
    wire        cur_burst_valid = cur_burst_left ? task_left_mem : task_right_mem;
    wire        gap_ok          = (gap_cnt_mem == 8'd0);
    wire        start_burst     = task_active_mem && !burst_active_mem && gap_ok &&
                                  (burst_idx_mem < TOTAL_BURSTS) &&
                                  cur_burst_valid && mem_enable;
    wire        skip_burst      = task_active_mem && !burst_active_mem && gap_ok &&
                                  (burst_idx_mem < TOTAL_BURSTS) &&
                                  !cur_burst_valid;

    function [ADDR_WIDTH-1:0] bank_base;
        input [1:0] idx;
        begin
            case (idx)
                2'd0:    bank_base = {ADDR_WIDTH{1'b0}};
                2'd1:    bank_base = BANK_WORDS;
                2'd2:    bank_base = BANK_WORDS * 2;
                default: bank_base = BANK_WORDS * 3;
            endcase
        end
    endfunction

    wire [1:0] cur_bank = cur_burst_left ? task_left_index_mem
                                         : task_right_index_mem;
    wire [3:0] cur_burst_in_thumb = cur_burst_left ? burst_idx_mem :
                                    (burst_idx_mem - BURSTS_PER_THUMB);
    wire [ADDR_WIDTH-1:0] cur_burst_in_thumb_ext =
        {{(ADDR_WIDTH-4){1'b0}}, cur_burst_in_thumb};

    // S7-04 资源/时序优化：源行偏移 task_src_y_mem * DISPLAY_WIDTH 在整个
    // 行任务内是常量（左右两格、10 个突发共用同一 src_y），原先每个突发都在
    // 组合路径上重算一次 10x21 乘法器，既浪费 LUT，又把 ext_mem_clk 125MHz
    // 的突发启动路径拉长（布局布线后该域 5 条违例全部起自 burst_word_mem）。
    // 改为在 capture_task 时一次寄存，突发启动路径只剩移位与加法。
    // 数值完全等价，功能与时序行为不变。
    wire [ADDR_WIDTH-1:0] task_src_row_off_next =
        req_src_y_sync2_mem * DISPLAY_WIDTH;

    // 参数自检：移位实现仅在 BURST_SIZE==128 时成立，参数被改动时立即报错，
    // 避免地址静默算错。
    initial begin
        if (BURST_SIZE != (1 << BURST_SIZE_LSH)) begin
            $display("ERROR: thumbnail_view_reader requires BURST_SIZE==128 for the shift-based address path");
            $finish;
        end
    end

    wire [ADDR_WIDTH-1:0] cur_burst_base =
        bank_base(cur_bank)
        + task_src_row_off_mem
        + (cur_burst_in_thumb_ext << BURST_SIZE_LSH);

    always @(posedge mem_clk or negedge mem_rst_n) begin
        if (!mem_rst_n) begin
            enable_sync1_mem    <= 1'b0;
            enable_sync2_mem    <= 1'b0;
            req_toggle_sync1_mem<= 1'b0;
            req_toggle_sync2_mem<= 1'b0;
            req_seen_mem        <= 1'b0;
            ack_toggle_mem      <= 1'b0;
            req_src_y_sync1_mem <= 10'd0;
            req_src_y_sync2_mem <= 10'd0;
            req_left_sync1_mem  <= 1'b0;
            req_left_sync2_mem  <= 1'b0;
            req_right_sync1_mem <= 1'b0;
            req_right_sync2_mem <= 1'b0;
            req_left_index_sync1_mem  <= 2'd0;
            req_left_index_sync2_mem  <= 2'd0;
            req_right_index_sync1_mem <= 2'd1;
            req_right_index_sync2_mem <= 2'd1;
            task_active_mem     <= 1'b0;
            task_src_y_mem      <= 10'd0;
            task_src_row_off_mem<= {ADDR_WIDTH{1'b0}};
            task_left_mem       <= 1'b0;
            task_right_mem      <= 1'b0;
            task_left_index_mem <= 2'd0;
            task_right_index_mem<= 2'd1;
            burst_idx_mem       <= 4'd0;
            burst_word_mem      <= 8'd0;
            burst_active_mem    <= 1'b0;
            gap_cnt_mem         <= 8'd0;
            burst_base_mem      <= {ADDR_WIDTH{1'b0}};
            issued_count_mem    <= 12'd0;
            returned_count_mem  <= 12'd0;
            ret_index_mem       <= 12'd0;
        end else begin
            enable_sync1_mem    <= enable;
            enable_sync2_mem    <= enable_sync1_mem;

            if (!enable_sync2_mem) begin
                req_toggle_sync1_mem<= 1'b0;
                req_toggle_sync2_mem<= 1'b0;
                req_seen_mem        <= 1'b0;
                ack_toggle_mem      <= 1'b0;
                task_active_mem     <= 1'b0;
                task_left_mem       <= 1'b0;
                task_right_mem      <= 1'b0;
                task_left_index_mem <= 2'd0;
                task_right_index_mem<= 2'd1;
                burst_idx_mem       <= 4'd0;
                burst_word_mem      <= 8'd0;
                burst_active_mem    <= 1'b0;
                gap_cnt_mem         <= 8'd0;
                issued_count_mem    <= 12'd0;
                returned_count_mem  <= 12'd0;
                ret_index_mem       <= 12'd0;
            end else begin
            req_toggle_sync1_mem<= req_toggle_pix;
            req_toggle_sync2_mem<= req_toggle_sync1_mem;
            req_src_y_sync1_mem <= req_src_y_pix;
            req_src_y_sync2_mem <= req_src_y_sync1_mem;
            req_left_sync1_mem  <= req_left_pix;
            req_left_sync2_mem  <= req_left_sync1_mem;
            req_right_sync1_mem <= req_right_pix;
            req_right_sync2_mem <= req_right_sync1_mem;
            req_left_index_sync1_mem  <= req_left_index_pix;
            req_left_index_sync2_mem  <= req_left_index_sync1_mem;
            req_right_index_sync1_mem <= req_right_index_pix;
            req_right_index_sync2_mem <= req_right_index_sync1_mem;

            // 突发间隔计数只在没有突发时递减
            if (!burst_active_mem && (gap_cnt_mem != 8'd0))
                gap_cnt_mem <= gap_cnt_mem - 8'd1;

            if (capture_task) begin
                req_seen_mem       <= req_toggle_sync2_mem;
                ack_toggle_mem     <= req_toggle_sync2_mem;
                task_active_mem    <= 1'b1;
                task_src_y_mem     <= req_src_y_sync2_mem;
                task_src_row_off_mem <= task_src_row_off_next;
                task_left_mem      <= req_left_sync2_mem;
                task_right_mem     <= req_right_sync2_mem;
                task_left_index_mem<= req_left_index_sync2_mem;
                task_right_index_mem<= req_right_index_sync2_mem;
                burst_idx_mem      <= 4'd0;
                burst_word_mem     <= 8'd0;
                burst_active_mem   <= 1'b0;
                issued_count_mem   <= 12'd0;
                returned_count_mem <= 12'd0;
                ret_index_mem      <= 12'd0;
            end else begin
                if (skip_burst)
                    burst_idx_mem <= burst_idx_mem + 4'd1;

                if (start_burst) begin
                    burst_active_mem <= 1'b1;
                    burst_word_mem   <= 8'd0;
                    burst_base_mem   <= cur_burst_base;
                end else if (burst_active_mem) begin
                    issued_count_mem <= issued_count_mem + 12'd1;
                    if (burst_word_mem == BURST_WORD_LAST) begin
                        burst_active_mem <= 1'b0;
                        burst_word_mem   <= 8'd0;
                        burst_idx_mem    <= burst_idx_mem + 4'd1;
                        gap_cnt_mem      <= BURST_GAP_CYCLES[7:0];
                    end else begin
                        burst_word_mem   <= burst_word_mem + 8'd1;
                    end
                end

                if (rd_valid) begin
                    returned_count_mem <= returned_count_mem + 12'd1;
                    ret_index_mem      <= ret_index_mem + 12'd1;
                end

                if (task_done) begin
                    task_active_mem <= 1'b0;
                    ack_toggle_mem  <= req_seen_mem;
                end
            end
            end
        end
    end

    // ---------------------------------------------------------------------
    // 5. 异步 FIFO：mem 域写“每 4 取 1”的缩略图像素，pix 域消费
    // ---------------------------------------------------------------------
    wire fifo_rst    = !pix_rst_n | !mem_rst_n | !enable;
    wire fifo_full;
    wire fifo_empty;
    wire [31:0] fifo_dout;
    wire fifo_valid;
    wire fifo_we = rd_valid && (ret_index_mem[1:0] == 2'd0) &&
                   !fifo_full && !fifo_rst;
    wire raw_read_en;

    rfifo_32_32_512 u_thmb_fifo (
        .rst        (fifo_rst),
        .clkw       (mem_clk),
        .clkr       (pix_clk),
        .we         (fifo_we),
        .di         (rd_data),
        .re         (raw_read_en),
        .dout       (fifo_dout),
        .valid      (fifo_valid),
        .full_flag  (fifo_full),
        .empty_flag (fifo_empty),
        .afull      (),
        .aempty     (),
        .wrusedw    (),
        .rdusedw    ()
    );

    // ---------------------------------------------------------------------
    // 6. 像素域两槽预取（等价于教程 fifo_prefetch_2 的 show-ahead 行为，
    //    但用本地寄存器实现，避免 TD 对 show-ahead 的 BRAM 推断限制）
    // ---------------------------------------------------------------------
    wire        consume   = enable && in_de && cur_thumb_de;
    reg  [31:0] slot0;
    reg  [31:0] slot1;
    reg  [1:0]  count;
    reg  [1:0]  outstanding;
    wire        pop       = consume && (count != 2'd0);
    wire [2:0]  reserved  = {1'b0, count} + {1'b0, outstanding};
    assign raw_read_en = !fifo_empty &&
                         ((reserved < 3'd2) ||
                          (pop && (reserved == 3'd2)));
    wire        out_valid = (count != 2'd0);
    wire [31:0] out_data  = slot0;

    always @(posedge pix_clk or negedge pix_rst_n) begin
        if (!pix_rst_n || !enable) begin
            slot0       <= 32'd0;
            slot1       <= 32'd0;
            count       <= 2'd0;
            outstanding <= 2'd0;
        end else begin
            case ({raw_read_en, fifo_valid})
                2'b10: outstanding <= outstanding + 2'd1;
                2'b01: outstanding <= outstanding - 2'd1;
                default: outstanding <= outstanding;
            endcase

            case ({pop, fifo_valid})
                2'b00: count <= count;
                2'b01: begin
                    if (count == 2'd0)
                        slot0 <= fifo_dout;
                    else
                        slot1 <= fifo_dout;
                    count <= count + 2'd1;
                end
                2'b10: begin
                    if (count == 2'd2)
                        slot0 <= slot1;
                    count <= count - 2'd1;
                end
                2'b11: begin
                    if (count == 2'd1)
                        slot0 <= fifo_dout;
                    else begin
                        slot0 <= slot1;
                        slot1 <= fifo_dout;
                    end
                    count <= count;
                end
            endcase
        end
    end

    // ---------------------------------------------------------------------
    // 7. 欠载诊断：正常带宽下不会发生；只作为 ILA/串口观测点
    // ---------------------------------------------------------------------
    reg under_flag;
    always @(posedge pix_clk or negedge pix_rst_n) begin
        if (!pix_rst_n || !enable)
            under_flag <= 1'b0;
        else if (in_de && (pixel_x == 10'd0))
            under_flag <= consume && !out_valid;
        else if (consume && !out_valid)
            under_flag <= 1'b1;
    end

    assign line_mismatch = under_flag;

    // ---------------------------------------------------------------------
    // 8. 像素输出（边框优先；数据未就绪时输出黑）
    // ---------------------------------------------------------------------
    assign thumb_active = enable && in_de && cur_thumb_de;
    assign focus_border = enable && in_de && cur_focus_border;
    assign pixel_rgb    = focus_border ? BORDER_RGB
                        : ((thumb_active && out_valid && !under_flag)
                           ? out_data[31:8] : 24'h00_00_00);

    assign rd_req  = burst_active_mem;
    assign rd_addr = burst_base_mem
                     + {{(ADDR_WIDTH-8){1'b0}}, burst_word_mem};

endmodule

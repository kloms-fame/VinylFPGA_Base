`timescale 1ns/1ps

// =============================================================================
// 第十三讲《图片缩放与缩略图》——缩略图取像引擎（本工程的对应实现）
//
// 教程链路：
//   video_timing -> thumbnail_layout -> media_frame_reader -> 像素 -> OSD/转场
//
// 本工程原有的 frame_read_write / frame_fifo_read 只提供“整帧顺序流式读出”，
// 没有“按坐标取像”的通道；而 thumbnail_layout 输出的恰恰是“每屏像素对应源图
// 哪一个像素”的坐标。因此这里按第八讲 media_frame_reader 的职责边界，补一个
// “按坐标取一个像素”的读取器（不改 frame_read_write / frame_fifo_read /
// SDRAM 控制器内部，只占用它们已有的 App_rd_en / App_rd_addr / Sdr_rd_en 口）：
//
//   pixel 域：
//     - 复现显示行计数 line_y（与 osd_overlay_24 同一口径）；
//     - 实例化教程模块 thumbnail_layout 三次：
//         u_layout_display  ：当前显示行坐标映射（决定这一屏像素要不要取像）；
//         u_layout_prefetch ：下一显示行坐标映射（地址提前一整行写进地址 FIFO）；
//         u_layout_next_px  ：当前行“下一个像素”的坐标映射，用于标准 FIFO
//                             的“提前一拍弹出”（valid 比 re 晚一拍）；
//     - 把 source_index/source_x/source_y 折算成 21 位 SDRAM 字地址，压入地址 FIFO。
//   mem 域：
//     - 从地址 FIFO 取地址，控制器空闲时发一次单字读；
//     - Sdr_rd_en/Sdr_rd_dout 写回像素 FIFO。
//
// IP 选型（复用工程既有 IP 与既有用法，不另造轮子）：
//   - 两个 FIFO 都用 rfifo_32_32_512（标准模式）。实测 show-ahead 的
//     wfifo_32_32_512 在本工程上下文中 TD 报 SYN-5042 无法推断 BRAM，
//     会展开成巨量寄存器，因此这里统一用可推断的标准 FIFO。
//   - 标准 FIFO 的 valid 只保持一拍（“re 之后一拍有效”），所以：
//       地址侧：rd_req = addr_pop && addr_valid，一个地址恰好读一次；
//       像素侧：提前一拍弹出（下一像素是不是缩略图像素），行首那一个像素
//               在消隐期弹出并保持在 row_first 寄存器里，跨消隐保持到行首。
//
// 安全设计（不影响原功能）：
//   - enable=0 时两个 FIFO 被持续复位，取像引擎完全不往 SDRAM 发请求；
//   - 行内一旦出现欠载，就在行末复位两个 FIFO 重对齐，并把紧随其后的那一行
//     整行按黑色处理（该行不消费 FIFO），保证地址流与像素流不会越对越偏。
// =============================================================================
module thumbnail_view_reader #(
    parameter integer DISPLAY_WIDTH   = 640,
    parameter integer DISPLAY_HEIGHT  = 480,
    parameter integer ADDR_WIDTH      = 21,
    parameter integer BANK_WORDS      = 307200,   // 640*480，每 bank 字数
    parameter integer THUMB_WIDTH     = 160,
    parameter integer THUMB_HEIGHT    = 120,
    parameter [23:0]  BORDER_RGB      = 24'hff_ff_00   // 焦点边框颜色（黄）
) (
    input  wire                    pix_clk,
    input  wire                    pix_rst_n,
    input  wire                    mem_clk,
    input  wire                    mem_rst_n,

    input  wire                    enable,        // 1=缩略图视图生效
    input  wire                    mem_enable,    // mem 域：可以发起一次读（含控制器空闲判据）
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

    // 提前一行的目标行号；最后一行要绕回第 0 行，否则每帧顶行都会缺取像数据
    wire [11:0] next_line_y = (line_y == (DISPLAY_HEIGHT-1)) ? 12'd0
                                                            : (line_y + 12'd1);
    wire [11:0] pixel_x12   = {2'b00, pixel_x};

    // ---------------------------------------------------------------------
    // 2. 教程模块 thumbnail_layout：当前行 / 下一行 / 同一行的下一个像素
    // ---------------------------------------------------------------------
    wire        cur_thumb_de;
    wire [1:0]  cur_source_index;
    wire [9:0]  cur_source_x;
    wire [9:0]  cur_source_y;
    wire        cur_focus_border;

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

    wire        next_thumb_de;
    wire [1:0]  next_source_index;
    wire [9:0]  next_source_x;
    wire [9:0]  next_source_y;
    wire        next_focus_border;   // 取像侧不需要边框，仅占位

    thumbnail_layout #(
        .DISPLAY_WIDTH  (DISPLAY_WIDTH),
        .DISPLAY_HEIGHT (DISPLAY_HEIGHT),
        .THUMB_WIDTH    (THUMB_WIDTH),
        .THUMB_HEIGHT   (THUMB_HEIGHT)
    ) u_layout_prefetch (
        .in_de        (in_de),
        .pixel_x      (pixel_x12),
        .pixel_y      (next_line_y),
        .focus_index  (focus_index),
        .image_complete(image_complete),
        .thumb_de     (next_thumb_de),
        .source_index (next_source_index),
        .source_x     (next_source_x),
        .source_y     (next_source_y),
        .focus_border (next_focus_border)
    );

    // 同一显示行、像素 x+1 的映射结果：标准 FIFO 需要“提前一拍”弹出像素，
    // 弹出条件就是“下一个显示像素仍然是缩略图像素”。
    wire        nx_px_thumb_de;
    wire [1:0]  nx_px_source_index;
    wire [9:0]  nx_px_source_x;
    wire [9:0]  nx_px_source_y;
    wire        nx_px_focus_border;
    wire [11:0] next_pixel_x12 = pixel_x12 + 12'd1;

    thumbnail_layout #(
        .DISPLAY_WIDTH  (DISPLAY_WIDTH),
        .DISPLAY_HEIGHT (DISPLAY_HEIGHT),
        .THUMB_WIDTH    (THUMB_WIDTH),
        .THUMB_HEIGHT   (THUMB_HEIGHT)
    ) u_layout_next_px (
        .in_de        (in_de),
        .pixel_x      (next_pixel_x12),
        .pixel_y      (line_y),
        .focus_index  (focus_index),
        .image_complete(image_complete),
        .thumb_de     (nx_px_thumb_de),
        .source_index (nx_px_source_index),
        .source_x     (nx_px_source_x),
        .source_y     (nx_px_source_y),
        .focus_border (nx_px_focus_border)
    );

    // ---------------------------------------------------------------------
    // 3. bank 基地址 + 行内偏移 -> 21 位 SDRAM 字地址
    //    frame_fifo_write 的 WRITE_V_FLIP 只是把 BMP 底向上的行序转成
    //    “存储器行号 == 显示行号”，因此读侧 source_y 直接就是存储行号。
    // ---------------------------------------------------------------------
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

    wire [ADDR_WIDTH-1:0] prefetch_addr =
        bank_base(next_source_index)
        + (next_source_y * DISPLAY_WIDTH)
        + {{(ADDR_WIDTH-10){1'b0}}, next_source_x};

    // 下一显示行第一列（x=0）是不是缩略图像素：等价于 thumbnail_layout 在
    // (pixel_x=0, pixel_y=next_line_y) 上的 thumb_de。用一行组合式判断即可，
    // 用来决定“这次消隐期是否需要把下一行第一个像素提前弹出来”。
    wire        nx_row_left_sel  = (next_line_y >= THUMB_HEIGHT);
    wire        nx_row_starts_thumb =
                    (next_line_y < (THUMB_HEIGHT * 2))
                    && image_complete[nx_row_left_sel ? 2'd2 : 2'd0];

    // ---------------------------------------------------------------------
    // 4. 地址 FIFO（video -> mem）与像素 FIFO（mem -> video），都是标准模式
    // ---------------------------------------------------------------------
    reg  [3:0]  flush_cnt;
    wire        row_end    = enable && de_q && !in_de;   // de 下降沿：当前显示行结束

    wire        pix_valid;       // 标准模式：re 之后一拍有效
    wire [31:0] pix_dout;
    wire        pix_full;        // mem 域回压：像素 FIFO 满则暂停取地址

    reg         under_flag;      // 本行出现过“取像数据未就绪”（欠载）
    reg         flush_row;       // 紧随冲刷行的下一行：整行按黑处理且不消费 FIFO
    wire        flush_req = row_end && under_flag;
    wire        flush_now = (flush_cnt != 4'd0);

    wire        addr_full;
    wire        addr_valid;
    wire [31:0] addr_dout;
    // 地址推送：显示第 y 行时，把“下一显示行 y+1”的缩略图像素地址写进 FIFO，
    // 提前一整行给 SDRAM 单字读留出余量（显示行周期内 mem 时钟快 4 倍）。
    wire        addr_push  = enable && in_de && next_thumb_de && !addr_full
                             && !flush_now;
    // 地址弹出受像素 FIFO 满信号回压；标准模式下 dout 比 re 晚一拍，
    // 因此读请求由 valid 限定（rd_req = addr_pop && addr_valid），一地址一读。
    wire        addr_pop   = mem_enable && !pix_full;

    // ---- 像素侧消费：标准 FIFO 的“提前一拍弹出” ----
    // 1) 行内：当前像素显示时，弹出“下一个显示像素”的取像数据（提前一拍）；
    // 2) 行首那一个像素：在行末消隐期弹出，并保持在 row_first 寄存器里跨消隐
    //    送到下一行行首（消隐有多长都不会丢）。
    reg         blank_done;      // 本次消隐期已经成功弹出 1 项
    reg         row_taken;       // 当前显示行已经出现并消费过缩略图像素

    wire        pop_look  = enable && in_de && nx_px_thumb_de
                            && !flush_now && !flush_row;
    wire        pop_blank = enable && !in_de && !blank_done
                            && nx_row_starts_thumb && !flush_now;
    wire        pix_pop   = pop_look || pop_blank;
    wire        blank_cap = enable && !in_de && !de_q && pix_valid && !flush_now;

    reg         row_first_vld;
    reg  [31:0] row_first_data;

    wire        first_thumb_px = enable && in_de && cur_thumb_de && !row_taken;
    wire        use_row_first  = first_thumb_px && row_first_vld;

    wire        under_now = enable && in_de && cur_thumb_de
                            && !(use_row_first ? row_first_vld : pix_valid)
                            && !flush_now && !flush_row;

    always @(posedge pix_clk or negedge pix_rst_n) begin
        if (!pix_rst_n)
            flush_cnt <= 4'd15;
        else if (!enable)
            flush_cnt <= 4'd15;                       // 关闭时持续复位两 FIFO
        else if (flush_req)
            flush_cnt <= 4'd8;                        // 行末消隐期复位两 FIFO 重对齐
        else if (flush_cnt != 4'd0)
            flush_cnt <= flush_cnt - 4'd1;
    end

    always @(posedge pix_clk or negedge pix_rst_n) begin
        if (!pix_rst_n)
            flush_row <= 1'b0;
        else if (!enable)
            flush_row <= 1'b0;
        else if (flush_req)
            flush_row <= 1'b1;                        // 紧接着的下一行按预期黑处理
        else if (row_end)
            flush_row <= 1'b0;
    end

    always @(posedge pix_clk or negedge pix_rst_n) begin
        if (!pix_rst_n)
            blank_done <= 1'b0;
        else if (!enable || flush_now)
            blank_done <= 1'b0;
        else if (in_de)
            blank_done <= 1'b0;                       // 进入行内即允许下次消隐再弹一次
        else if (pop_blank)
            blank_done <= 1'b1;                       // 已发出弹出，避免 valid 未及时到来时重复弹
    end

    always @(posedge pix_clk or negedge pix_rst_n) begin
        if (!pix_rst_n)
            row_taken <= 1'b0;
        else if (!enable || flush_now)
            row_taken <= 1'b0;
        else if (row_end)
            row_taken <= 1'b0;
        else if (first_thumb_px)
            row_taken <= 1'b1;
    end

    always @(posedge pix_clk or negedge pix_rst_n) begin
        if (!pix_rst_n) begin
            row_first_vld  <= 1'b0;
            row_first_data <= 32'd0;
        end else if (!enable || flush_now) begin
            row_first_vld  <= 1'b0;
            row_first_data <= 32'd0;
        end else if (blank_cap) begin
            row_first_vld  <= 1'b1;                   // 消隐期取出的下一行首像素
            row_first_data <= pix_dout;
        end else if (use_row_first || row_end) begin
            row_first_vld  <= 1'b0;                   // 行首消费掉 / 换行时作废
        end
    end

    wire fifo_rst = !pix_rst_n | !mem_rst_n | flush_now;

    // under_flag 描述“当前这一行”，每行行首清零，行内一旦欠载就置位；
    // 它在行末触发整行冲刷重对齐。
    always @(posedge pix_clk or negedge pix_rst_n) begin
        if (!pix_rst_n)
            under_flag <= 1'b0;
        else if (!enable || flush_now)
            under_flag <= 1'b0;
        else if (in_de && (pixel_x == 10'd0))
            under_flag <= 1'b0;
        else if (under_now)
            under_flag <= 1'b1;
    end

    assign line_mismatch = flush_req;

    rfifo_32_32_512 u_addr_fifo (
        .rst        (fifo_rst),
        .clkw       (pix_clk),
        .clkr       (mem_clk),
        .we         (addr_push),
        .di         ({{(32-ADDR_WIDTH){1'b0}}, prefetch_addr}),
        .re         (addr_pop),
        .dout       (addr_dout),
        .valid      (addr_valid),
        .full_flag  (addr_full),
        .empty_flag (),
        .afull      (),
        .aempty     (),
        .wrusedw    (),
        .rdusedw    ()
    );

    rfifo_32_32_512 u_pixel_fifo (
        .rst        (fifo_rst),
        .clkw       (mem_clk),
        .clkr       (pix_clk),
        .we         (rd_valid),
        .di         (rd_data),
        .re         (pix_pop),
        .dout       (pix_dout),
        .valid      (pix_valid),
        .full_flag  (pix_full),
        .empty_flag (),
        .afull      (),
        .aempty     (),
        .wrusedw    (),
        .rdusedw    ()
    );

    assign rd_req  = addr_pop && addr_valid;
    assign rd_addr = addr_dout[ADDR_WIDTH-1:0];

    // ---------------------------------------------------------------------
    // 5. 像素输出（边框优先；数据未就绪/坏行时输出黑）
    // ---------------------------------------------------------------------
    wire        disp_vld  = use_row_first ? row_first_vld : pix_valid;
    wire [31:0] disp_data = use_row_first ? row_first_data : pix_dout;

    assign thumb_active = enable && in_de && cur_thumb_de;
    assign focus_border = enable && in_de && cur_focus_border;
    assign pixel_rgb    = focus_border ? BORDER_RGB
                        : ((disp_vld && !under_flag && !flush_row)
                           ? disp_data[31:8] : 24'h00_00_00);

endmodule

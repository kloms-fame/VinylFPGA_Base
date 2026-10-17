`ifndef BOOT_LAYER_V
`define BOOT_LAYER_V
// =============================================================================
// boot_layer —— S2 开机 Logo / 启动画面（最小 STATE_BOOT）
//
// 位置：像素链最末端（波形叠加之后、RGB->AXIS 之前）的纯像素替换层。
//   - 不改 de/vs/hs 节拍，不碰 HDMI 核与音频岛调度；
//   - boot_active=1 时整屏由 Logo 图层接管（盒外纯黑），=0 时顶层直接旁路
//     回原波形像素，主链路行为与 S1 完全一致。
//
// 状态：
//   STATE_BOOT  ：上电默认态，显示片内 Logo + 固定周期呼吸（只调像素，
//                 不动任何时钟）；
//   STATE_BROWSE：boot_active=0，交给既有主链路显示。
//   离开 STATE_BOOT 的条件（都在帧边界 vs 下降沿提交）：
//     1) 启动时 SW2 为高，经两级同步后直接旁路 Boot；
//     2) 收到已确认 J2 事件并达到 SKIP_MIN_MS；
//     3) 首图已就绪且已显示满 HOLD_MS；4) 兜底超时 TIMEOUT_MS。
//
// 时钟域：video_clk（25 MHz），复位 video_rst_n，与像素链同域。
// 跨域接收 J2 事件翻转电平（两级同步 + 边沿检测）和 SW2 启动状态
// （两级电平同步）；SW2 状态只在启动采样一次。
//
// Logo 数据来自 boot_logo_rom（片内调色板 ROM，几何见 boot_logo_geom.vh），
// 由 tools/gen_boot_logo.py 从 doc/资源/VinylFPGA_640x480.jpg 生成。
// =============================================================================
`include "boot_logo_geom.vh"

module boot_layer #(
    parameter         BOOT_ENABLE      = 1'b1,        // 总开关（=0 时整层旁路）
    parameter integer CLK_FREQ_HZ      = 25_000_000, // video_clk
    parameter integer HOLD_MS          = 6000,       // 最短显示时间
    parameter integer SKIP_MIN_MS      = 0,          // Top reserves HDMI acquisition window
    parameter integer TIMEOUT_MS       = 8000,       // 无人操作/无图时的兜底
    parameter integer BREATH_FLOOR     = 192          // 呼吸最暗增益（/256）
)(
    input  wire        clk,               // video_clk
    input  wire        rst_n,             // video_rst_n
    input  wire        vs,                // 与像素链同域的场同步
    input  wire        de,                // adjusted_de：有效像素使能
    input  wire [9:0]  pixel_x,           // adjusted_pixel_x：行内像素计数
    input  wire        skip_toggle,       // clk 域事件翻转电平（异步输入）
    input  wire        startup_skip,      // clk 域启动时锁存的 SW2 状态（异步输入）
    input  wire        first_image_ready, // display_valid_sync2
    output reg         boot_active,       // 1=STATE_BOOT，0=STATE_BROWSE
    output wire [23:0] rgb                // 启动画面像素（boot_active=1 时有效）
);
    localparam integer MS_DIV = CLK_FREQ_HZ / 1000;

    localparam [14:0] MS_DIV_LAST  = MS_DIV - 1;
    localparam [7:0]  DIM_FLOOR    = BREATH_FLOOR;

    localparam [9:0]  BOX_X0 = `BOOT_LOGO_X0;
    localparam [9:0]  BOX_Y0 = `BOOT_LOGO_Y0;
    localparam [9:0]  BOX_X1 = `BOOT_LOGO_X0 + `BOOT_LOGO_CROP_W;
    localparam [9:0]  BOX_Y1 = `BOOT_LOGO_Y0 + `BOOT_LOGO_CROP_H;
    localparam integer SCL2  = `BOOT_LOGO_SCALE_LOG2;
    localparam integer AB    = `BOOT_LOGO_ADDR_BITS;
    localparam integer PB    = `BOOT_LOGO_PIXEL_BITS;
    localparam [15:0] LW16   = `BOOT_LOGO_LW;
    localparam [7:0]  LW8    = `BOOT_LOGO_LW;

    localparam [15:0] HOLD_LIMIT    = HOLD_MS;
    localparam [15:0] TIMEOUT_LIMIT = TIMEOUT_MS;

    // ---- 毫秒节拍（与主链路其它 ms 计数器同构，只在本模块内部使用）----
    reg  [14:0] ms_div;
    reg         ms_tick;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ms_div  <= 15'd0;
            ms_tick <= 1'b0;
        end else begin
            ms_tick <= 1'b0;
            if (ms_div == MS_DIV_LAST) begin
                ms_div  <= 15'd0;
                ms_tick <= 1'b1;
            end else begin
                ms_div  <= ms_div + 15'd1;
            end
        end
    end

    // ---- 跨域事件：两级同步 + 边沿检测（一次事件一个单拍）----
    reg skip_s1, skip_s2, skip_s3;
    wire skip_pulse = skip_s2 ^ skip_s3;
    reg startup_skip_s1, startup_skip_s2;

    // ---- 场边界 ----
    reg  vs_q;
    wire frame_start = vs_q & ~vs;

    // ---- 行计数（行内 x 直接用像素链已对齐的 adjusted_pixel_x）----
    reg  [9:0] pixel_y;
    reg        de_q;

    // ---- Boot 状态与计时 ----
    reg  [15:0] boot_ms;
    reg  [10:0] breath_phase;
    reg         skip_latched;

    wire hold_ok  = first_image_ready && (boot_ms >= HOLD_LIMIT);
    wire timeout_ok = (boot_ms >= TIMEOUT_LIMIT);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            skip_s1      <= 1'b0;
            skip_s2      <= 1'b0;
            skip_s3      <= 1'b0;
            startup_skip_s1 <= 1'b0;
            startup_skip_s2 <= 1'b0;
            vs_q         <= 1'b0;
            de_q         <= 1'b0;
            pixel_y      <= 10'd0;
            boot_ms      <= 16'd0;
            breath_phase <= 11'd0;
            skip_latched <= 1'b0;
            boot_active  <= BOOT_ENABLE;   // 上电即 STATE_BOOT
        end else begin
            skip_s1 <= skip_toggle;
            skip_s2 <= skip_s1;
            skip_s3 <= skip_s2;
            startup_skip_s1 <= startup_skip;
            startup_skip_s2 <= startup_skip_s1;

            vs_q <= vs;
            de_q <= de;

            // 行计数：de 拉低时收行，帧边界清零。首行 y=0。
            //
            // 注意：本工程 640x480 时序是 VS_POL=0（场同步**低有效**，见
            // src/SD/color_bar.v），vs 在绝大多数行都保持高电平，因此绝不能用
            // "vs 为高就清零"——那会把行计数一直压在 0，Logo 永远画不出来。
            // 统一改用与主链路同一判据的帧边界 frame_start（vs 的下降沿）。
            if (frame_start) begin
                pixel_y <= 10'd0;
            end else if (!de) begin
                if (de_q)
                    pixel_y <= pixel_y + 10'd1;
            end

            if (skip_pulse)
                skip_latched <= 1'b1;

            if (ms_tick && boot_active) begin
                boot_ms      <= boot_ms + 16'd1;
                breath_phase <= breath_phase + 11'd1;
            end

            // 只在帧边界提交状态跳转，避免半帧切换造成撕裂
            if (frame_start && boot_active) begin
                if (startup_skip_s2 || (skip_latched && boot_ms >= SKIP_MIN_MS) ||
                    hold_ok || timeout_ok) begin
                    boot_active  <= 1'b0;   // -> STATE_BROWSE
                    skip_latched <= 1'b0;
                end
            end
        end
    end

    // ---- 取像素：裁剪盒内按 SCL2 倍欠采样寻址，盒外强制地址 0 ----
    wire in_box = (pixel_x >= BOX_X0) && (pixel_x < BOX_X1) &&
                  (pixel_y >= BOX_Y0) && (pixel_y < BOX_Y1);

    wire [7:0] lx = (pixel_x - BOX_X0) >> SCL2;
    wire [7:0] ly = (pixel_y - BOX_Y0) >> SCL2;
    wire [15:0] pix_index_full = ly * LW16 + {8'd0, lx};
    wire [AB-1:0] pix_index = in_box ? pix_index_full[AB-1:0] : {AB{1'b0}};

    wire [23:0] rom_rgb;

    boot_logo_rom #(
        .LOGO_W     (LW8),
        .LOGO_H     (`BOOT_LOGO_LH),
        .PIXEL_BITS (PB),
        .ADDR_BITS  (AB)
    ) u_boot_logo_rom (
        .clk       (clk),
        .pix_index (pix_index),
        .rgb       (rom_rgb)
    );

    // ROM 同步读有 1 拍延迟：把"是否在盒内"同步延迟 1 拍，与 ROM 数据对齐，
    // 结果是整幅 Logo 统一右移 1 像素（不可见），但不会出现行末错位。
    reg in_box_q;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            in_box_q <= 1'b0;
        else
            in_box_q <= in_box;
    end

    // ---- 呼吸：三角波增益 192..255，只对像素做一次 8x8 乘法 ----
    wire [10:0] breath_half = breath_phase[10] ? (11'd2047 - breath_phase) : breath_phase;
    wire [6:0]  breath_tri  = breath_half[9:4];              // 0..63
    wire [7:0]  breath_gain = DIM_FLOOR + {1'b0, breath_tri};

    wire [15:0] mul_r = rom_rgb[23:16] * breath_gain;
    wire [15:0] mul_g = rom_rgb[15:8]  * breath_gain;
    wire [15:0] mul_b = rom_rgb[7:0]   * breath_gain;
    wire [23:0] rom_rgb_dim = {mul_r[15:8], mul_g[15:8], mul_b[15:8]};

    // 组合输出：ROM 已自带 1 拍同步读，in_box_q 同样延迟 1 拍，两者严格对齐。
    assign rgb = (boot_active && in_box_q) ? rom_rgb_dim : 24'd0;

endmodule
`endif

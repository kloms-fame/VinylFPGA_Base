`ifndef EXP_WS2812_EFFECTS_V
`define EXP_WS2812_EFFECTS_V
// =============================================================================
// ws2812_effects —— X1B：WS2812 灯效层（全灭 / 音频律动 / 进度条）
//
// 运行在板级 clk(50 MHz) 域。KEY10 每按一次在三种模式间循环：
//   mode 0 = 全灭（上电默认）
//   mode 1 = 音频律动：8 颗灯按 PCM 包络点亮，快升慢降由 pcm_tap 提供
//   mode 2 = 进度条   ：8 颗灯按播放进度点亮，暂停/欠载时进度自然冻结
//
// 音频只读旁路：level 是 pcm_tap 送来的包络，本模块不反压、不访问 SD/音频 FIFO。
// DIP6(enable) 关闭时：先补发一整帧全黑（否则灯珠会保持最后颜色），
//   黑帧发射完成后才停止刷新；DIP6 重新打开后恢复当前模式。
// mute 在 X5 之前恒为 0；为 1 时律动灭，进度条不受影响。
// =============================================================================
module ws2812_effects #(
    parameter integer PIXEL_COUNT = 8,
    parameter integer CLK_FREQ_HZ = 50_000_000,
    parameter integer REFRESH_MS  = 20,
    // 时序按 CLK_FREQ_HZ 推导（见 ws2812_driver 头部注释）：
    //   50 MHz -> 63/18/35/3000（1.260us/0.360us/0.700us/60us）
    //   25 MHz -> 31/10/19/1250（1.240us/0.400us/0.760us/50us）
    parameter integer BIT_CYCLES  = (CLK_FREQ_HZ >= 50_000_000) ? 63 : 31,
    parameter integer T0H_CYCLES  = (CLK_FREQ_HZ >= 50_000_000) ? 18 : 10,
    parameter integer T1H_CYCLES  = (CLK_FREQ_HZ >= 50_000_000) ? 35 : 19,
    parameter integer RESET_CYCLES= (CLK_FREQ_HZ >= 50_000_000) ? 3000 : 1250
)(
    input  wire       clk,
    input  wire       rst_n,

    input  wire       enable,        // DIP6 WS 总使能（上拨=1）
    input  wire       mode_tgl,      // KEY10 单拍电平翻转（clk 域）
    input  wire [7:0] level,         // PCM 包络 0..255（clk 域，已跨域同步）
    input  wire [3:0] progress,      // 进度 0..8（点亮颗数）
    input  wire       mute,          // X5 前恒 0

    output wire       ws_data
);
    // ---- KEY10 -> 模式循环 ----
    reg [2:0] mode_sync;
    reg [1:0] mode;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) mode_sync <= 3'd0;
        else        mode_sync <= {mode_sync[1:0], mode_tgl};
    end
    wire mode_event = mode_sync[2] ^ mode_sync[1];
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) mode <= 2'd0;
        else if (mode_event) mode <= (mode == 2'd2) ? 2'd0 : mode + 1'b1;
    end

    // ---- 律动点亮颗数：level>>5 再补一颗，钳位到 8 ----
    wire [3:0] vu_n = (level < 8'd8)  ? 4'd0 :
                      (level < 8'd40) ? 4'd1 :
                      (level < 8'd72) ? 4'd2 :
                      (level < 8'd104)? 4'd3 :
                      (level < 8'd136)? 4'd4 :
                      (level < 8'd168)? 4'd5 :
                      (level < 8'd200)? 4'd6 :
                      (level < 8'd232)? 4'd7 : 4'd8;
    wire [3:0] vu_n_eff = mute ? 4'd0 : vu_n;

    // ---- 整帧像素（RGB）----
    reg  [23:0] frame_rgb [0:PIXEL_COUNT-1];
    reg  [PIXEL_COUNT*24-1:0] frame_grb;
    integer i;
    always @* begin
        for (i = 0; i < PIXEL_COUNT; i = i + 1) begin
            frame_rgb[i] = 24'h000000;
            if (mode == 2'd1) begin
                if (i < vu_n_eff)
                    frame_rgb[i] = (i < 3) ? 24'h00E000 :
                                   (i < 6) ? 24'hE0E000 : 24'hE02000;
            end else if (mode == 2'd2) begin
                if (i < progress)
                    frame_rgb[i] = (i < 4) ? 24'h0030E0 : 24'h00C0E0;
            end
        end
        for (i = 0; i < PIXEL_COUNT; i = i + 1)
            frame_grb[i*24 +: 24] = {frame_rgb[i][15:8],
                                     frame_rgb[i][23:16],
                                     frame_rgb[i][7:0]};
    end

    // ---- 20 ms 刷新节拍 ----
    localparam integer MS_CYCLES = CLK_FREQ_HZ / 1000;
    localparam integer MS_W      = $clog2(MS_CYCLES + 1);
    localparam integer RF_W      = $clog2(REFRESH_MS + 1);
    reg [MS_W-1:0] ms_div;
    reg [RF_W-1:0] rf_ms;
    wire ms_tick = (ms_div >= (MS_CYCLES - 1));
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ms_div <= {MS_W{1'b0}};
            rf_ms  <= {RF_W{1'b0}};
        end else if (ms_tick) begin
            ms_div <= {MS_W{1'b0}};
            rf_ms  <= (rf_ms >= (REFRESH_MS - 1)) ? {RF_W{1'b0}} : rf_ms + 1'b1;
        end else begin
            ms_div <= ms_div + 1'b1;
        end
    end
    wire refresh_pulse = ms_tick && (rf_ms >= (REFRESH_MS - 1));

    // ---- 黑帧补发：DIP6 关闭后必须真正推一帧全 0，而不是把数据线拉低 ----
    wire [PIXEL_COUNT*24-1:0] tx_frame = enable ? frame_grb
                                                : {PIXEL_COUNT*24{1'b0}};
    wire frame_is_black = (tx_frame == {PIXEL_COUNT*24{1'b0}});

    reg  black_sent;
    reg  load_req;
    wire busy;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)          black_sent <= 1'b0;
        else if (enable)     black_sent <= 1'b0;
        else if (load_req && frame_is_black) black_sent <= 1'b1;
    end

    always @* begin
        if (enable)
            load_req = refresh_pulse && !busy;
        else
            load_req = !busy && !black_sent;
    end

    ws2812_driver #(
        .PIXEL_COUNT  (PIXEL_COUNT),
        .BIT_CYCLES   (BIT_CYCLES),
        .T0H_CYCLES   (T0H_CYCLES),
        .T1H_CYCLES   (T1H_CYCLES),
        .RESET_CYCLES (RESET_CYCLES)
    ) u_ws2812_driver (
        .clk    (clk),
        .rst_n  (rst_n),
        .load   (load_req),
        .grb_in (tx_frame),
        .busy   (busy),
        .dout   (ws_data)
    );
endmodule
`endif

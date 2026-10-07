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

    // Low-cost RGB colour wheel, one step per refresh. Audio amplitude sets
    // the channel ceiling (0..63); silence and mute are black. No fixed VU palette.
    reg [5:0] hue_ramp;
    reg [2:0] hue_sector;
    reg [7:0] runner_ms;
    reg [2:0] runner;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin hue_ramp<=0;hue_sector<=0;end
        else if(refresh_pulse && enable) begin
            hue_ramp<=hue_ramp+1'b1;
            if(hue_ramp==63) hue_sector<=(hue_sector==5) ? 3'd0 : hue_sector+1'b1;
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin runner_ms<=0;runner<=0;end
        else if(ms_tick && enable) begin
            if(runner_ms==249) begin runner_ms<=0;runner<=(runner==PIXEL_COUNT-1) ? 3'd0 : runner+1'b1;end
            else runner_ms<=runner_ms+1'b1;
        end
    end
    reg [5:0] wheel_r,wheel_g,wheel_b;
    always @* begin
        wheel_r=0;wheel_g=0;wheel_b=0;
        case(hue_sector)
          0:begin wheel_r=63;wheel_g=hue_ramp;end
          1:begin wheel_r=63-hue_ramp;wheel_g=63;end
          2:begin wheel_g=63;wheel_b=hue_ramp;end
          3:begin wheel_g=63-hue_ramp;wheel_b=63;end
          4:begin wheel_b=63;wheel_r=hue_ramp;end
          default:begin wheel_b=63-hue_ramp;wheel_r=63;end
        endcase
    end
    wire [5:0] amplitude = (mute || level<8) ? 6'd0 : level[7:2];
    reg  black_sent;
    reg  load_req;
    wire busy;

    // Freeze the same load-edge values previously stored as a full pixel frame.
    // A 33-bit rendering context replaces 24*PIXEL_COUNT frame bits and their mux.
    // Live input changes while busy must only affect the next accepted frame.
    reg [1:0] frame_mode;
    reg [5:0] frame_r, frame_g, frame_b, frame_amplitude;
    reg [3:0] frame_progress;
    reg [2:0] frame_runner;
    wire [4:0] pixel_index;
    reg [23:0] pixel_grb;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            frame_mode <= 0;
            frame_r <= 0; frame_g <= 0; frame_b <= 0;
            frame_amplitude <= 0;
            frame_progress <= 0;
            frame_runner <= 0;
        end else if (load_req && !busy) begin
            frame_mode <= enable ? mode : 2'd0;
            frame_r <= wheel_r; frame_g <= wheel_g; frame_b <= wheel_b;
            frame_amplitude <= amplitude;
            frame_progress <= progress;
            frame_runner <= runner;
        end
    end
    wire [5:0] ar = frame_r < frame_amplitude ? frame_r : frame_amplitude;
    wire [5:0] ag = frame_g < frame_amplitude ? frame_g : frame_amplitude;
    wire [5:0] ab = frame_b < frame_amplitude ? frame_b : frame_amplitude;
    always @* begin
        pixel_grb = 24'd0;
        if (frame_mode == 1)
            pixel_grb = {2'b0,ag,2'b0,ar,2'b0,ab};
        else if (frame_mode == 2) begin
            // Progress base is dim (max 15); travelling point is at most 63.
            if (pixel_index < frame_progress)
                pixel_grb = {4'b0,frame_g[5:2],4'b0,frame_r[5:2],4'b0,frame_b[5:2]};
            if (pixel_index == frame_runner)
                pixel_grb = {2'b0,frame_g,2'b0,frame_r,2'b0,frame_b};
        end
    end

    // ---- 关闭后补发完整黑帧；此分支中 frame_mode 必然锁存为 0 ----
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)          black_sent <= 1'b0;
        else if (enable)     black_sent <= 1'b0;
        else if (load_req)   black_sent <= 1'b1;
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
        .RESET_CYCLES (RESET_CYCLES),
        .STREAMING    (1)
    ) u_ws2812_driver (
        .clk    (clk),
        .rst_n  (rst_n),
        .load   (load_req),
        .grb_in ({PIXEL_COUNT*24{1'b0}}),
        .stream_grb (pixel_grb),
        .stream_pixel_index (pixel_index),
        .busy   (busy),
        .dout   (ws_data)
    );
endmodule
`endif

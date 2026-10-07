`ifndef EXP_WS2812_EFFECTS_V
`define EXP_WS2812_EFFECTS_V
// =============================================================================
// ws2812_effects —— X1B：WS2812 灯效层（全灭 / 音频律动 / 进度条）
//
// 运行在板级 clk(50 MHz) 域。KEY10 每按一次在三种模式间循环：
//   mode 0 = 全灭（上电默认）
//   mode 1 = 音频律动：彩色包络历史从第 1 颗向右流动，每 60 ms 前进一步
//   mode 2 = 进度条   ：比例底色 + 四颗渐变长脉冲向右，每 80 ms 前进一步
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

    // All animation state is held throughout serialization. At 20 ms refresh,
    // audio history moves right every 60 ms; the four-pixel pulse every 80 ms.
    localparam integer MS_CYCLES = (CLK_FREQ_HZ < 1000) ? 1 : CLK_FREQ_HZ / 1000;
    localparam integer MS_W = (MS_CYCLES < 2) ? 1 : $clog2(MS_CYCLES);
    localparam integer RF_W = (REFRESH_MS < 2) ? 1 : $clog2(REFRESH_MS);
    localparam integer HEAD_W = $clog2(PIXEL_COUNT + 3);
    reg [MS_W-1:0] ms_div;
    reg [RF_W-1:0] rf_ms;
    wire ms_tick = (ms_div == MS_CYCLES-1);
    wire refresh_pulse = ms_tick && (rf_ms == REFRESH_MS-1);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) ms_div <= 0;
        else if (ms_tick) ms_div <= 0;
        else ms_div <= ms_div + 1'b1;
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) rf_ms <= 0;
        else if (ms_tick) rf_ms <= refresh_pulse ? 0 : rf_ms + 1'b1;
    end

    reg black_sent;
    reg load_req;
    wire busy;
    wire accept_frame = load_req && !busy;
    reg [1:0] frame_mode;
    reg [3:0] frame_progress;
    reg [5:0] colour_phase;
    reg [1:0] motion_div;
    reg [HEAD_W-1:0] pulse_head;
    // Six amplitude bits per pixel, instead of a 24-bit RGB framebuffer.
    reg [PIXEL_COUNT*6-1:0] audio_history;
    wire [5:0] amplitude = (mute || level < 8) ? 6'd0 : level[7:2];
    wire mode_start = (mode != frame_mode);
    wire audio_step = mode_start || (motion_div == 2);
    wire pulse_step = (motion_div == 3);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) frame_mode <= 0;
        else if (accept_frame) frame_mode <= enable ? mode : 2'd0;
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) frame_progress <= 0;
        else if (accept_frame) frame_progress <= progress > 8 ? 4'd8 : progress;
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) colour_phase <= 0;
        else if (accept_frame && enable) colour_phase <= colour_phase + 1'b1;
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) motion_div <= 0;
        else if (accept_frame) begin
            if (!enable || mode_start || mode == 0 ||
                (mode == 1 && audio_step) || (mode == 2 && pulse_step)) motion_div <= 0;
            else motion_div <= motion_div + 1'b1;
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) pulse_head <= 0;
        else if (accept_frame) begin
            if (!enable || mode_start || mode != 2) pulse_head <= 0;
            else if (pulse_step)
                pulse_head <= (pulse_head == PIXEL_COUNT+2) ? 0 : pulse_head + 1'b1;
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) audio_history <= 0;
        else if (accept_frame) begin
            if (!enable || mode != 1 || mute) audio_history <= 0;
            else if (mode_start) audio_history <= amplitude;
            else if (audio_step) audio_history <= (audio_history << 6) | amplitude;
        end
    end

    wire [4:0] pixel_index;
    wire [2:0] pixel_colour = pixel_index[2:0] - colour_phase[5:3];
    wire [HEAD_W:0] tail_distance = {1'b0,pulse_head} - pixel_index;
    reg [5:0] brightness;
    reg [7:0] red, green, blue;
    wire [23:0] pixel_grb = {green,red,blue};
    always @* begin
        brightness = 0;
        if (frame_mode == 1)
            brightness = audio_history[pixel_index*6 +: 6];
        else if (frame_mode == 2) begin
            // Fixed progress base: floor(position / total * 8) LEDs.
            if (pixel_index < frame_progress) brightness = 12;
            // A four-pixel gradient travels right and exits before restarting.
            if (pixel_index <= pulse_head) begin
                case (tail_distance)
                    0: brightness = 63;
                    1: brightness = 48;
                    2: brightness = 32;
                    3: brightness = 16;
                    default: ;
                endcase
            end
        end
        red = 0; green = 0; blue = 0;
        case (pixel_colour)
            0: red = {2'b0,brightness};
            1: begin red = {2'b0,brightness}; green = {3'b0,brightness[5:1]}; end
            2: begin red = {2'b0,brightness}; green = {2'b0,brightness}; end
            3: green = {2'b0,brightness};
            4: begin green = {2'b0,brightness}; blue = {2'b0,brightness}; end
            5: blue = {2'b0,brightness};
            6: begin red = {3'b0,brightness[5:1]}; blue = {2'b0,brightness}; end
            7: begin red = {2'b0,brightness}; blue = {2'b0,brightness}; end
        endcase
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

`ifndef EXP_WS2812_EFFECTS_V
`define EXP_WS2812_EFFECTS_V
// =============================================================================
// ws2812_effects —— X1B：WS2812 灯效层（全灭 / 音频律动 / 进度条）
//
// 运行在板级 clk(50 MHz) 域。KEY10 每按一次在三种模式间循环：
//   mode 0 = 全灭（上电默认）
//   mode 1 = VU 电平条：LED[0] 向右连续展开，绿/黄/红分段，快升慢降
//   mode 2 = 充能进度条：有效进度内四颗彗星脉冲 + 终点吸收，区外全暗
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
    // VU attacks within one frame and releases by 8/255 per frame (640 ms max).
    // The comet moves every 60 ms, absorbs at the endpoint, then rests 80 ms.
    localparam integer MS_CYCLES = (CLK_FREQ_HZ < 1000) ? 1 : CLK_FREQ_HZ / 1000;
    localparam integer MS_W = (MS_CYCLES < 2) ? 1 : $clog2(MS_CYCLES);
    localparam integer RF_W = (REFRESH_MS < 2) ? 1 : $clog2(REFRESH_MS);

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
    reg [7:0] vu_envelope;
    reg [2:0] pulse_head;
    reg [1:0] motion_div;
    reg [1:0] charge_state; // 0: flight, 1: absorption, 2: base-only interval
    reg [5:0] charge_energy;
    reg [1:0] gap_count;
    wire [3:0] bounded_progress = progress > 8 ? 4'd8 : progress;
    wire mode_start = (mode != frame_mode);
    wire restart_charge = !enable || mode != 2 || mode_start ||
                          bounded_progress == 0 || bounded_progress != frame_progress;
    // Exactly floor(level * 8 / 255): thresholds 32,64,...,224,255.
    wire [3:0] vu_count = vu_envelope == 255 ? 4'd8 : {1'b0,vu_envelope[7:5]};
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) frame_mode <= 0;
        else if (accept_frame) frame_mode <= enable ? mode : 2'd0;
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) frame_progress <= 0;
        else if (accept_frame) frame_progress <= bounded_progress;
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) vu_envelope <= 0;
        else if (accept_frame) begin
            if (!enable || mode != 1 || mute) vu_envelope <= 0;
            else if (mode_start || level >= vu_envelope) vu_envelope <= level;
            else if (vu_envelope - level <= 8) vu_envelope <= level;
            else vu_envelope <= vu_envelope - 8'd8;
        end
    end
    // Related animation registers update together only at an accepted frame.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pulse_head<=0; motion_div<=0; charge_state<=0; charge_energy<=0; gap_count<=0;
        end else if (accept_frame) begin
            if (restart_charge) begin
                pulse_head<=0; motion_div<=0; charge_state<=0; charge_energy<=0; gap_count<=0;
            end else case (charge_state)
                0: if (motion_div == 2) begin
                    motion_div <= 0;
                    if ({1'b0,pulse_head}+4'd1 >= bounded_progress) begin
                        charge_state<=1; charge_energy<=63;
                    end else pulse_head <= pulse_head + 1'b1;
                end else motion_div <= motion_div + 1'b1;
                1: if (charge_energy > 8) charge_energy <= charge_energy - 6'd8;
                   else begin charge_energy<=0; charge_state<=2; gap_count<=0; end
                2: if (gap_count == 3) begin charge_state<=0; pulse_head<=0; motion_div<=0; end
                   else gap_count <= gap_count + 1'b1;
                default: begin charge_state<=0; pulse_head<=0; motion_div<=0; end
            endcase
        end
    end

    wire [4:0] pixel_index;
    wire [3:0] tail_distance = {1'b0,pulse_head} - pixel_index;
    reg [7:0] red, green, blue;
    wire [23:0] pixel_grb = {green,red,blue};
    always @* begin
        red=0; green=0; blue=0;
        if (frame_mode == 1 && pixel_index < vu_count) begin
            // Four green, two amber, two red: position expresses warning level.
            if (pixel_index < 4) green=48;
            else if (pixel_index < 6) begin red=56; green=32; end
            else red=63;
        end else if (frame_mode == 2 && pixel_index < frame_progress) begin
            // Dim desaturated blue-grey base. All effects are clipped to progress.
            red=5; green=8; blue=10;
            if (charge_state == 0 && pixel_index <= pulse_head) begin
                case (tail_distance)
                    0: begin red=32; green=63; blue=63; end
                    1: begin red=12; green=40; blue=56; end
                    2: begin red=6; green=22; blue=36; end
                    3: begin red=5; green=12; blue=20; end
                    default: ;
                endcase
            end else if (charge_state == 1 && pixel_index == pulse_head) begin
                // Endpoint absorbs the comet: white flash decays into the base.
                red   = charge_energy > 5  ? {2'b0,charge_energy} : 8'd5;
                green = charge_energy > 8  ? {2'b0,charge_energy} : 8'd8;
                blue  = charge_energy > 10 ? {2'b0,charge_energy} : 8'd10;
            end
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

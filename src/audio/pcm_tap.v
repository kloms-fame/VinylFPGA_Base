`ifndef EXP_PCM_TAP_V
`define EXP_PCM_TAP_V
// =============================================================================
// pcm_tap —— X1B：PCM 包络只读旁路（视频域）
//
// 挂在 wav_stream_player 的 sample_out/sample_valid 上，纯观测、不握手、不反压，
// 不访问 SD/音频 FIFO，因此不会给主音频链路带来任何额外 stall。
//
// 包络策略（对标方案"饱和绝对值 / 快升慢降"）：
//   - 取左右声道整流绝对值的较大者；-32768 饱和为 32768（16 位无符号回绕正确）；
//   - 快升：目标值大于当前值直接跟上（攻击=1 个样本）；
//   - 慢降：每 DECAY_DIV 个样本衰减 DECAY_STEP，约 1 s 从满量程落到 0；
//   - level[7:0] 与 upd_tgl 一起作为"数据 + 翻转"跨域捆绑握手交给 clk 域。
//
// upd_tgl 每 UPD_DIV 个样本翻转一次（48 kHz / 64 ≈ 750 Hz），保证 clk 域
// （50 MHz）捕获时 level 已经稳定若干个周期。
// =============================================================================
module pcm_tap #(
    parameter integer DECAY_DIV  = 256,   // 每多少个样本衰减一次
    parameter integer DECAY_STEP = 1      // 每次衰减的步长
)(
    input  wire               clk,        // 视频域时钟
    input  wire               rst_n,

    input  wire               sample_valid,
    input  wire signed [15:0] sample_left,
    input  wire signed [15:0] sample_right,

    output reg  [7:0]         level,      // 0..255 包络
    output reg                upd_tgl     // 数据稳定后翻转，供跨域捕获
);
    wire [15:0] abs_l = sample_left[15]  ? (~sample_left[15:0]  + 16'd1) : sample_left[15:0];
    wire [15:0] abs_r = sample_right[15] ? (~sample_right[15:0] + 16'd1) : sample_right[15:0];
    wire [15:0] mag   = (abs_l > abs_r) ? abs_l : abs_r;

    // 32768 -> 255（饱和），32767 -> 255
    wire [7:0] target = mag[15] ? 8'hFF : mag[14:7];

    localparam integer DECAY_W = $clog2(DECAY_DIV + 1);
    reg [DECAY_W-1:0] decay_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            level     <= 8'd0;
            upd_tgl   <= 1'b0;
            decay_cnt <= {DECAY_W{1'b0}};
        end else if (sample_valid) begin
            // 快升慢降
            if (target >= level)
                level <= target;
            else if (decay_cnt >= (DECAY_DIV - 1))
                level <= (level > DECAY_STEP[DECAY_W-1:0])
                             ? (level - DECAY_STEP[DECAY_W-1:0])
                             : 8'd0;

            if (decay_cnt >= (DECAY_DIV - 1))
                decay_cnt <= {DECAY_W{1'b0}};
            else
                decay_cnt <= decay_cnt + 1'b1;

            // 在衰减边界之后一拍翻转握手：此刻 level 已稳定，
            // clk 域（50 MHz）捕获时不会取到正在变化的 8 位数据。
            // 翻转周期 = DECAY_DIV 个样本（48 kHz / 256 ≈ 187 Hz）。
            if (decay_cnt == 1'b1)
                upd_tgl <= ~upd_tgl;
        end
    end
endmodule
`endif

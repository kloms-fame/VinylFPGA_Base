`ifndef EXP_EXPANSION_IO_HUB_V
`define EXP_EXPANSION_IO_HUB_V
// =============================================================================
// expansion_io_hub —— J2 拓展板输入统一汇聚层（S1）
//
// 职责：把 exp_* 原始异步输入汇聚成"已同步 / 已消抖 / 已边沿检测 / 已解码"的
//       主链路可用信号。内部只复用 J2 标定工程原样移植的输入驱动，不重复实现
//       主链路已有的 key1/key2 消抖（param_menu_controller / key_press_hold），
//       也不与已有逻辑共享寄存器。
//
// 时钟域：本模块整体运行在 50 MHz 板级 clk 域。
//   J2 标定工程顶层 sys_clk 同为 R7 50 MHz，因此 DEBOUNCE_CYCLES=400_000
//   （8 ms）、AB_STABLE_CYCLES=50_000（1 ms）、IR CLK_FREQ_HZ=50 MHz 三组时序
//   参数数值与标定工程完全一致 —— 处理顺序与行为逐条保持不变。
//
// 处理顺序（与标定工程一致）：
//   KEY/DIP : raw -> sync_bit(2FF) -> debounce_filter(计数消抖 + 边沿脉冲)
//   EC      : raw -> sync_bit -> 1 ms 稳定采样四相位判步
//   IR      : raw -> sync_bit -> NEC 引导码 / 32 位数据 / 重复帧解码
// =============================================================================
module expansion_io_hub #(
    parameter integer KEY_COUNT        = 12,
    parameter integer DIP_COUNT        = 6,
    parameter integer DEBOUNCE_CYCLES  = 400_000,
    parameter integer AB_STABLE_CYCLES = 50_000,
    parameter integer IR_CLK_FREQ_HZ   = 50_000_000
)(
    input  wire                 clk,
    input  wire                 rst_n,

    // 原始异步输入（板内上拉；按键与编码器 SW 低有效）
    input  wire [KEY_COUNT-1:0] exp_key_n,
    input  wire [DIP_COUNT-1:0] exp_dip_n,
    input  wire                 exp_enc1_a,
    input  wire                 exp_enc1_b,
    input  wire                 exp_enc1_sw_n,
    input  wire                 exp_enc2_a,
    input  wire                 exp_enc2_b,
    input  wire                 exp_enc2_sw_n,
    input  wire                 exp_ir_rx,

    // KEY / DIP：消抖后电平 + 边沿脉冲
    output wire [KEY_COUNT-1:0] key_level,
    output wire [KEY_COUNT-1:0] key_fall_pulse,
    output wire [KEY_COUNT-1:0] key_rise_pulse,
    output wire [DIP_COUNT-1:0] dip_level,
    output wire [DIP_COUNT-1:0] dip_change_pulse,
    output wire [2:0]           dip_change_index,

    // EC1 / EC2：正交步进 + 计数 + 按压
    output wire                 enc1_step_pulse,
    output wire                 enc1_direction,
    output wire [15:0]          enc1_count,
    output wire                 enc1_sw_level,
    output wire                 enc1_sw_fall_pulse,
    output wire                 enc1_sw_rise_pulse,
    output wire                 enc2_step_pulse,
    output wire                 enc2_direction,
    output wire [15:0]          enc2_count,
    output wire                 enc2_sw_level,
    output wire                 enc2_sw_fall_pulse,
    output wire                 enc2_sw_rise_pulse,

    // NEC 红外
    output wire                 ir_event,
    output wire                 ir_repeat_event,
    output wire [31:0]          ir_code,
    output wire [7:0]           ir_command
);

    // ---- KEY(12) + DIP(6)：消抖与边沿检测（J2 原样驱动）----
    key_dip_monitor #(
        .KEY_COUNT      (KEY_COUNT),
        .DIP_COUNT      (DIP_COUNT),
        .DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)
    ) u_key_dip_monitor (
        .clk             (clk),
        .rst_n           (rst_n),
        .key_async       (exp_key_n),
        .dip_async       (exp_dip_n),
        .key_level       (key_level),
        .key_fall_pulse  (key_fall_pulse),
        .key_rise_pulse  (key_rise_pulse),
        .dip_level       (dip_level),
        .dip_change_pulse(dip_change_pulse),
        .dip_change_index(dip_change_index)
    );

    // ---- EC1 / EC2：正交解码 + 按压消抖（J2 原样驱动）----
    encoder_monitor #(
        .DEBOUNCE_CYCLES (DEBOUNCE_CYCLES),
        .AB_STABLE_CYCLES(AB_STABLE_CYCLES)
    ) u_encoder_monitor (
        .clk               (clk),
        .rst_n             (rst_n),
        .enc1_a_async      (exp_enc1_a),
        .enc1_b_async      (exp_enc1_b),
        .enc1_sw_async     (exp_enc1_sw_n),
        .enc2_a_async      (exp_enc2_a),
        .enc2_b_async      (exp_enc2_b),
        .enc2_sw_async     (exp_enc2_sw_n),
        .enc1_step_pulse   (enc1_step_pulse),
        .enc1_direction    (enc1_direction),
        .enc1_count        (enc1_count),
        .enc1_sw_level     (enc1_sw_level),
        .enc1_sw_fall_pulse(enc1_sw_fall_pulse),
        .enc1_sw_rise_pulse(enc1_sw_rise_pulse),
        .enc2_step_pulse   (enc2_step_pulse),
        .enc2_direction    (enc2_direction),
        .enc2_count        (enc2_count),
        .enc2_sw_level     (enc2_sw_level),
        .enc2_sw_fall_pulse(enc2_sw_fall_pulse),
        .enc2_sw_rise_pulse(enc2_sw_rise_pulse)
    );

    // ---- NEC 红外解码（J2 原样驱动）----
    ir_nec_decoder #(
        .CLK_FREQ_HZ(IR_CLK_FREQ_HZ)
    ) u_ir_nec_decoder (
        .clk          (clk),
        .rst_n        (rst_n),
        .ir_async     (exp_ir_rx),
        .event_valid  (ir_event),
        .code         (ir_code),
        .command      (ir_command),
        .repeat_event (ir_repeat_event)
    );

endmodule
`endif

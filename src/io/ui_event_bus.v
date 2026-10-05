`ifndef EXP_UI_EVENT_BUS_V
`define EXP_UI_EVENT_BUS_V
// =============================================================================
// ui_event_bus —— 统一 UI 事件总线（S1）
//
// 把 expansion_io_hub 的"电平 + 单拍边沿"整理成统一编码的单拍事件流，
// 供消费侧统一消费（S1 为 exp_echo_reporter；S2+ 为业务状态机）。
// 消费侧不再直接读 exp_key_n / exp_enc*_a/b / exp_ir_rx，避免重复消抖与语义分叉。
//
// 同一拍只分发一个事件，优先级：
//   KEY_DOWN > KEY_UP > DIP > EC 步进 > EC 按压 > IR。
// 所有输入与本模块同处 50 MHz clk 域，因此这里不做跨域同步。
// 若 S2 业务运行在 sd_card_clk(100 MHz) 域，需在消费侧按既有 sync_2ff /
// toggle 握手方式把本事件流搬过去（S1 不预先引入未验证的 CDC 通路）。
//
// 事件编码见 src/include/exp_event_defs.vh。
// =============================================================================
module ui_event_bus #(
    parameter integer KEY_COUNT = 12,
    parameter integer DIP_COUNT = 6
)(
    input  wire                 clk,
    input  wire                 rst_n,

    input  wire [KEY_COUNT-1:0] key_fall_pulse,
    input  wire [KEY_COUNT-1:0] key_rise_pulse,

    input  wire [DIP_COUNT-1:0] dip_level,
    input  wire [DIP_COUNT-1:0] dip_change_pulse,
    input  wire [2:0]           dip_change_index,

    input  wire                 enc1_step_pulse,
    input  wire                 enc1_direction,
    input  wire [15:0]          enc1_count,
    input  wire                 enc1_sw_fall_pulse,
    input  wire                 enc1_sw_rise_pulse,

    input  wire                 enc2_step_pulse,
    input  wire                 enc2_direction,
    input  wire [15:0]          enc2_count,
    input  wire                 enc2_sw_fall_pulse,
    input  wire                 enc2_sw_rise_pulse,

    input  wire                 ir_event,
    input  wire                 ir_repeat_event,
    input  wire [31:0]          ir_code,

    output reg                  ev_valid,
    output reg  [3:0]           ev_code,
    output reg  [15:0]          ev_arg,
    output reg  [15:0]          ev_aux
);
    `include "exp_event_defs.vh"

    reg        arb_valid;
    reg [3:0]  arb_code;
    reg [15:0] arb_arg;
    reg [15:0] arb_aux;
    integer    i;

    // 单拍仲裁：组合挑一路事件（与 J2 event_reporter 的优先级写法一致）
    always @* begin
        arb_valid = 1'b0;
        arb_code  = EV_NONE;
        arb_arg   = 16'd0;
        arb_aux   = 16'd0;

        // 按键按下 / 释放（低有效已在 hub 归一为脉冲）
        for (i = 0; i < KEY_COUNT; i = i + 1) begin
            if (!arb_valid && key_fall_pulse[i]) begin
                arb_valid = 1'b1;
                arb_code  = EV_KEY_DOWN;
                arb_arg   = i[15:0];
            end
        end
        for (i = 0; i < KEY_COUNT; i = i + 1) begin
            if (!arb_valid && key_rise_pulse[i]) begin
                arb_valid = 1'b1;
                arb_code  = EV_KEY_UP;
                arb_arg   = i[15:0];
            end
        end

        // 拨码变化：携带变化点索引与当前电平（上拨=1，不二次取反）
        if (!arb_valid && (dip_change_pulse != {DIP_COUNT{1'b0}})) begin
            arb_valid = 1'b1;
            arb_code  = EV_DIP_CHANGE;
            arb_arg   = {13'd0, dip_level[dip_change_index], dip_change_index};
        end

        // 编码器步进：arg=计数，aux={enc_id, direction}
        if (!arb_valid && enc1_step_pulse) begin
            arb_valid = 1'b1;
            arb_code  = EV_ENC_STEP;
            arb_arg   = enc1_count;
            arb_aux   = {14'd0, 1'b0, enc1_direction};
        end
        if (!arb_valid && enc2_step_pulse) begin
            arb_valid = 1'b1;
            arb_code  = EV_ENC_STEP;
            arb_arg   = enc2_count;
            arb_aux   = {14'd0, 1'b1, enc2_direction};
        end

        // 编码器按压：arg={pressed}，aux={enc_id}
        if (!arb_valid && enc1_sw_fall_pulse) begin
            arb_valid = 1'b1;
            arb_code  = EV_ENC_SW;
            arb_arg   = 16'd0;
            arb_aux   = {14'd0, 1'b0, 1'b0};
        end
        if (!arb_valid && enc1_sw_rise_pulse) begin
            arb_valid = 1'b1;
            arb_code  = EV_ENC_SW;
            arb_arg   = 16'd1;
            arb_aux   = {14'd0, 1'b0, 1'b0};
        end
        if (!arb_valid && enc2_sw_fall_pulse) begin
            arb_valid = 1'b1;
            arb_code  = EV_ENC_SW;
            arb_arg   = 16'd0;
            arb_aux   = {14'd0, 1'b1, 1'b0};
        end
        if (!arb_valid && enc2_sw_rise_pulse) begin
            arb_valid = 1'b1;
            arb_code  = EV_ENC_SW;
            arb_arg   = 16'd1;
            arb_aux   = {14'd0, 1'b1, 1'b0};
        end

        // 红外：arg=code[15:0]，aux=code[31:16]，重复帧沿用同一 32 位码
        if (!arb_valid && ir_event) begin
            arb_valid = 1'b1;
            arb_code  = ir_repeat_event ? EV_IR_REPEAT : EV_IR_FRAME;
            arb_arg   = ir_code[15:0];
            arb_aux   = ir_code[31:16];
        end
    end

    // 打一拍，输出干净、与消费侧同域的单拍事件
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ev_valid <= 1'b0;
            ev_code  <= EV_NONE;
            ev_arg   <= 16'd0;
            ev_aux   <= 16'd0;
        end else begin
            ev_valid <= arb_valid;
            ev_code  <= arb_code;
            ev_arg   <= arb_arg;
            ev_aux   <= arb_aux;
        end
    end

endmodule
`endif

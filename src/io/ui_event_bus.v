`ifndef EXP_UI_EVENT_BUS_V
`define EXP_UI_EVENT_BUS_V
// =============================================================================
// ui_event_bus —— 统一 UI 事件总线（S7-03 重构）
//
// S7-03 把原来"同拍只按优先级选一个"的组合仲裁升级为"逐源 pending 位图"：
// 每个会驱动业务的事件源都有自己的 pending 位，同拍到达的多个事件先全部并入
// pending，再由固定优先级逐拍排空输出。这样既保留 S1 的事件编码与串口语义，
// 又不再丢同拍的关键事件（原实现只在 DIP 上保存 pending，其它同拍输入会被
// 优先级直接丢弃）。
//
// pending 语义（资源精简）：
//   KEY_DOWN : 12 位 pending（业务关键，逐键保序）；
//   KEY_UP   : 不设 pending，由 key_rise_pulse 直接进入仲裁。单键 down-before-up
//              由物理时序天然保证；只有"同拍异键释放 + 更高优先级事件"的极端
//              场景才可能丢一个 KEY_UP，仅影响串口回显，不驱动业务；
//   DIP  : 6 位 pending + 6 位最终电平，同一位多次变化合并为最终电平；
//   EC   : 每编码器 step/sw 各一位，direction/pressed 随 pending 捕获；
//   IR   : 一位 pending + repeat 标志，完整 32 位帧由输入直供（pending 极短）。
//
// 溢出：pending 已满又收到同类新事件时输出 ev_overflow 单拍脉冲（供 health_monitor
// 计数），绝不覆盖已 pending 的事件，也绝不伪造确认/暂停等系统动作。
// 所有输入与本模块同处 50 MHz clk 域，因此不做跨域同步。
//
// 事件编码见 src/include/exp_event_defs.vh。
// =============================================================================
module ui_event_bus #(
    parameter integer KEY_COUNT = 12,
    parameter integer DIP_COUNT = 6
)(
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 ev_enable, // 低时保留待处理事件，不推进仲裁

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
    output reg  [15:0]          ev_aux,
    output reg                  ev_overflow
);
    `include "exp_event_defs.vh"

    // ---- 逐源 pending 位图（KEY_UP 直接进仲裁，不设 pending）----
    reg [KEY_COUNT-1:0] key_down_pending;
    reg [DIP_COUNT-1:0] dip_pending;
    reg [DIP_COUNT-1:0] dip_pending_level;
    reg                 enc1_step_pending;
    reg                 enc1_step_dir;
    reg                 enc2_step_pending;
    reg                 enc2_step_dir;
    reg                 enc1_sw_pending;
    reg                 enc1_sw_pressed;
    reg                 enc2_sw_pending;
    reg                 enc2_sw_pressed;
    reg                 ir_pending;
    reg                 ir_pending_repeat;

    // ---- 组合仲裁：按优先级挑选一个事件输出，并标记要清除的 pending 位 ----
    reg                 arb_valid;
    reg [3:0]           arb_code;
    reg [15:0]          arb_arg;
    reg [15:0]          arb_aux;
    reg [KEY_COUNT-1:0] arb_key_down_clr;
    reg [DIP_COUNT-1:0] arb_dip_clr;
    reg                 arb_enc1_step_clr;
    reg                 arb_enc2_step_clr;
    reg                 arb_enc1_sw_clr;
    reg                 arb_enc2_sw_clr;
    reg                 arb_ir_clr;

    integer i;

    // LSB-first priority encoder.  The previous procedural scan produced a
    // 12-stage arb_valid chain on the 50 MHz domain; casez infers a balanced
    // mux tree without changing the pending order.
    function [3:0] key_priority;
        input [KEY_COUNT-1:0] bits;
        begin
            casez (bits)
                12'b???????????1: key_priority = 4'd0;
                12'b??????????10: key_priority = 4'd1;
                12'b?????????100: key_priority = 4'd2;
                12'b????????1000: key_priority = 4'd3;
                12'b???????10000: key_priority = 4'd4;
                12'b??????100000: key_priority = 4'd5;
                12'b?????1000000: key_priority = 4'd6;
                12'b????10000000: key_priority = 4'd7;
                12'b???100000000: key_priority = 4'd8;
                12'b??1000000000: key_priority = 4'd9;
                12'b?10000000000: key_priority = 4'd10;
                default:          key_priority = 4'd11;
            endcase
        end
    endfunction

    wire [3:0] key_down_idx = key_priority(key_down_pending);
    wire [3:0] key_up_idx   = key_priority(key_rise_pulse);

    always @* begin
        arb_valid = 1'b0;
        arb_code  = EV_NONE;
        arb_arg   = 16'd0;
        arb_aux   = 16'd0;
        arb_key_down_clr = {KEY_COUNT{1'b0}};
        arb_dip_clr      = {DIP_COUNT{1'b0}};
        arb_enc1_step_clr = 1'b0;
        arb_enc2_step_clr = 1'b0;
        arb_enc1_sw_clr   = 1'b0;
        arb_enc2_sw_clr   = 1'b0;
        arb_ir_clr        = 1'b0;

        // Keep all pending events in place until the consumer is ready.
        // Inputs continue accumulating below while output arbitration is held.
        if (ev_enable) begin
            // KEY_DOWN（优先级最高，pending 逐键保序）
            if (|key_down_pending) begin
                arb_valid = 1'b1;
                arb_code  = EV_KEY_DOWN;
                arb_arg   = {12'd0, key_down_idx};
                arb_key_down_clr = 12'b1 << key_down_idx;
            end
            // KEY_UP（直接，无 pending）
            else if (|key_rise_pulse) begin
                arb_valid = 1'b1;
                arb_code  = EV_KEY_UP;
                arb_arg   = {12'd0, key_up_idx};
            end
            // DIP
            for (i = 0; i < DIP_COUNT; i = i + 1) begin
                if (!arb_valid && dip_pending[i]) begin
                    arb_valid = 1'b1;
                    arb_code  = EV_DIP_CHANGE;
                    arb_arg   = {12'd0, dip_pending_level[i], i[2:0]};
                    arb_dip_clr[i] = 1'b1;
                end
            end
            // EC step（enc_id 在 aux[1]，direction 在 aux[0]）
            if (!arb_valid && enc1_step_pending) begin
                arb_valid = 1'b1;
                arb_code  = EV_ENC_STEP;
                arb_arg   = enc1_count;
                arb_aux   = {14'd0, 1'b0, enc1_step_dir};
                arb_enc1_step_clr = 1'b1;
            end
            if (!arb_valid && enc2_step_pending) begin
                arb_valid = 1'b1;
                arb_code  = EV_ENC_STEP;
                arb_arg   = enc2_count;
                arb_aux   = {14'd0, 1'b1, enc2_step_dir};
                arb_enc2_step_clr = 1'b1;
            end
            // EC 按压（arg[0]=pressed，aux[1]=enc_id）
            if (!arb_valid && enc1_sw_pending) begin
                arb_valid = 1'b1;
                arb_code  = EV_ENC_SW;
                arb_arg   = {15'd0, enc1_sw_pressed};
                arb_aux   = {14'd0, 1'b0, 1'b0};
                arb_enc1_sw_clr = 1'b1;
            end
            if (!arb_valid && enc2_sw_pending) begin
                arb_valid = 1'b1;
                arb_code  = EV_ENC_SW;
                arb_arg   = {15'd0, enc2_sw_pressed};
                arb_aux   = {14'd0, 1'b1, 1'b0};
                arb_enc2_sw_clr = 1'b1;
            end
            // IR（完整 32 位帧：arg=低16，aux=高16）
            if (!arb_valid && ir_pending) begin
                arb_valid = 1'b1;
                arb_code  = ir_pending_repeat ? EV_IR_REPEAT : EV_IR_FRAME;
                arb_arg   = ir_code[15:0];
                arb_aux   = ir_code[31:16];
                arb_ir_clr = 1'b1;
            end
        end
    end

    // 溢出检测（组合）：pending 已满又来同类新事件。DIP 合并最终电平，不判溢出。
    wire key_down_ovf   = |(key_down_pending & key_fall_pulse);
    wire enc1_step_ovf  = enc1_step_pending & enc1_step_pulse;
    wire enc2_step_ovf  = enc2_step_pending & enc2_step_pulse;
    wire enc1_sw_ovf    = enc1_sw_pending & (enc1_sw_fall_pulse | enc1_sw_rise_pulse);
    wire enc2_sw_ovf    = enc2_sw_pending & (enc2_sw_fall_pulse | enc2_sw_rise_pulse);
    wire ir_ovf         = ir_pending & ir_event;
    wire overflow_now   = key_down_ovf | enc1_step_ovf | enc2_step_ovf |
                          enc1_sw_ovf | enc2_sw_ovf | ir_ovf;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ev_valid      <= 1'b0;
            ev_code       <= EV_NONE;
            ev_arg        <= 16'd0;
            ev_aux        <= 16'd0;
            ev_overflow   <= 1'b0;
            key_down_pending <= {KEY_COUNT{1'b0}};
            dip_pending      <= {DIP_COUNT{1'b0}};
            dip_pending_level<= {DIP_COUNT{1'b0}};
            enc1_step_pending<= 1'b0;
            enc1_step_dir    <= 1'b0;
            enc2_step_pending<= 1'b0;
            enc2_step_dir    <= 1'b0;
            enc1_sw_pending  <= 1'b0;
            enc1_sw_pressed  <= 1'b0;
            enc2_sw_pending  <= 1'b0;
            enc2_sw_pressed  <= 1'b0;
            ir_pending       <= 1'b0;
            ir_pending_repeat<= 1'b0;
        end else begin
            ev_valid    <= arb_valid;
            ev_code     <= arb_code;
            ev_arg      <= arb_arg;
            ev_aux      <= arb_aux;
            ev_overflow <= overflow_now;

            // 并入新脉冲，同时清除本拍已输出的 pending 位。
            key_down_pending <= (key_down_pending | key_fall_pulse) & ~arb_key_down_clr;

            dip_pending <= (dip_pending | dip_change_pulse) & ~arb_dip_clr;
            // DIP 合并最终电平：变化位取当前电平，未变化位保留原 pending 电平。
            dip_pending_level <= (dip_level & dip_change_pulse) |
                                 (dip_pending_level & ~dip_change_pulse);

            enc1_step_pending <= (enc1_step_pending | enc1_step_pulse) & ~arb_enc1_step_clr;
            if (enc1_step_pulse) begin
                enc1_step_dir   <= enc1_direction;
            end

            enc2_step_pending <= (enc2_step_pending | enc2_step_pulse) & ~arb_enc2_step_clr;
            if (enc2_step_pulse) begin
                enc2_step_dir   <= enc2_direction;
            end

            enc1_sw_pending <= (enc1_sw_pending | enc1_sw_fall_pulse | enc1_sw_rise_pulse)
                               & ~arb_enc1_sw_clr;
            if (enc1_sw_fall_pulse)       enc1_sw_pressed <= 1'b0;
            else if (enc1_sw_rise_pulse)  enc1_sw_pressed <= 1'b1;

            enc2_sw_pending <= (enc2_sw_pending | enc2_sw_fall_pulse | enc2_sw_rise_pulse)
                               & ~arb_enc2_sw_clr;
            if (enc2_sw_fall_pulse)       enc2_sw_pressed <= 1'b0;
            else if (enc2_sw_rise_pulse)  enc2_sw_pressed <= 1'b1;

            ir_pending <= (ir_pending | ir_event) & ~arb_ir_clr;
            if (ir_event) begin
                ir_pending_repeat <= ir_repeat_event;
            end
        end
    end

endmodule
`endif

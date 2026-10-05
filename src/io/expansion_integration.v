`ifndef EXP_EXPANSION_INTEGRATION_V
`define EXP_EXPANSION_INTEGRATION_V
// =============================================================================
// expansion_integration —— S1 拓展板集成子系统（单一边界）
//
// 把 S1 的物理通路收进一个自包含子系统，顶层只需对接 exp_* 端口：
//   exp_* 原始输入 -> expansion_io_hub -> ui_event_bus -> exp_echo_reporter
//                                                      -> exp_* 输出回显
//
// 设计边界（与《主链路开发报告》S1 一致）：
//   - 只验证输入/输出物理通路，不接切歌/播放/歌词/MV 等后续业务；
//   - 本层整体运行在 50 MHz clk 域，与 J2 标定工程 sys_clk 同频，
//     因此消抖/正交/红外三组时序参数数值与标定工程完全一致；
//   - 不触碰主链路 key1/key2 消抖、sd_card_clk(100 MHz) 时序预算。
//
// 回显开关与输出安全态：
//   ECHO_ENABLE=1 -> 串口事件上报 KEY/DIP/ENC/IR，LED1-4 低有效镜像 KEY01-04；
//   ECHO_ENABLE=0 -> 串口静默，LED 全灭。
//   WS2812 在 S1 静态全灭（动态灯效按报告 D15 留待 S7）；
//   操作反馈音：board_buzzer_n 驱动母板蜂鸣器（H11，低有效，硬件 SW5 通断），
//   同一蜂鸣波形同时送到 EXT1，供拓展板外接蜂鸣器/蜂鸣器模块；EXT2-6 仍固定 0。
// =============================================================================
module expansion_integration #(
    parameter integer CLK_FREQ_HZ      = 50_000_000,
    parameter integer BAUD_RATE        = 115_200,
    parameter integer DEBOUNCE_CYCLES  = 400_000,
    parameter integer AB_STABLE_CYCLES = 50_000,
    parameter integer IR_CLK_FREQ_HZ   = 50_000_000,
    parameter         ECHO_ENABLE      = 1'b1,
    parameter         BUZZER_ENABLE    = 1'b1
)(
    input  wire        clk,
    input  wire        rst_n,          // 本域"异步生效/同步释放"后的低有效复位

    input  wire [11:0] exp_key_n,
    input  wire [5:0]  exp_dip_n,
    input  wire        exp_enc1_a,
    input  wire        exp_enc1_b,
    input  wire        exp_enc1_sw_n,
    input  wire        exp_enc2_a,
    input  wire        exp_enc2_b,
    input  wire        exp_enc2_sw_n,
    input  wire        exp_ir_rx,

    // 母板输入：KEY1/KEY2 复用主工程既有按键，KEY3=B1 为本阶段新增；
    // SW1-SW4 = 板载乒乓拨码（C8/C7/C6/C5），均按按键/拨码低有效消抖。
    input  wire        key1,
    input  wire        key2,
    input  wire        key3,
    input  wire        sw1,
    input  wire        sw2,
    input  wire        sw3,
    input  wire        sw4,

    output wire [3:0]  exp_led_n,
    output wire        exp_ws2812_data,
    output wire [5:0]  exp_ext_o,
    output wire        board_buzzer_n,
    output wire        uart_tx
);

    // hub -> bus / reporter 的中间信号
    wire [11:0] key_level;
    wire [11:0] key_fall_pulse;
    wire [11:0] key_rise_pulse;
    wire [5:0]  dip_level;
    wire [5:0]  dip_change_pulse;
    wire [2:0]  dip_change_index;

    wire        enc1_step_pulse;
    wire        enc1_direction;
    wire [15:0] enc1_count;
    wire        enc1_sw_fall_pulse;
    wire        enc1_sw_rise_pulse;
    wire        enc2_step_pulse;
    wire        enc2_direction;
    wire [15:0] enc2_count;
    wire        enc2_sw_fall_pulse;
    wire        enc2_sw_rise_pulse;

    wire        ir_event;
    wire        ir_repeat_event;
    wire [31:0] ir_code;

    wire        ev_valid;
    wire [3:0]  ev_code;
    wire [15:0] ev_arg;
    wire [15:0] ev_aux;

    // ---- 输入驱动汇聚层（sync / debounce / edge / 正交 / NEC）----
    expansion_io_hub #(
        .KEY_COUNT        (12),
        .DIP_COUNT        (6),
        .DEBOUNCE_CYCLES  (DEBOUNCE_CYCLES),
        .AB_STABLE_CYCLES (AB_STABLE_CYCLES),
        .IR_CLK_FREQ_HZ   (IR_CLK_FREQ_HZ)
    ) u_expansion_io_hub (
        .clk                (clk),
        .rst_n              (rst_n),
        .exp_key_n          (exp_key_n),
        .exp_dip_n          (exp_dip_n),
        .exp_enc1_a         (exp_enc1_a),
        .exp_enc1_b         (exp_enc1_b),
        .exp_enc1_sw_n      (exp_enc1_sw_n),
        .exp_enc2_a         (exp_enc2_a),
        .exp_enc2_b         (exp_enc2_b),
        .exp_enc2_sw_n      (exp_enc2_sw_n),
        .exp_ir_rx          (exp_ir_rx),
        .key_level          (key_level),
        .key_fall_pulse     (key_fall_pulse),
        .key_rise_pulse     (key_rise_pulse),
        .dip_level          (dip_level),
        .dip_change_pulse   (dip_change_pulse),
        .dip_change_index   (dip_change_index),
        .enc1_step_pulse    (enc1_step_pulse),
        .enc1_direction     (enc1_direction),
        .enc1_count         (enc1_count),
        .enc1_sw_level      (),
        .enc1_sw_fall_pulse (enc1_sw_fall_pulse),
        .enc1_sw_rise_pulse (enc1_sw_rise_pulse),
        .enc2_step_pulse    (enc2_step_pulse),
        .enc2_direction     (enc2_direction),
        .enc2_count         (enc2_count),
        .enc2_sw_level      (),
        .enc2_sw_fall_pulse (enc2_sw_fall_pulse),
        .enc2_sw_rise_pulse (enc2_sw_rise_pulse),
        .ir_event           (ir_event),
        .ir_repeat_event    (ir_repeat_event),
        .ir_code            (ir_code),
        .ir_command         ()
    );

    // ---- 统一事件编码总线 ----
    ui_event_bus #(
        .KEY_COUNT (12),
        .DIP_COUNT (6)
    ) u_ui_event_bus (
        .clk                (clk),
        .rst_n              (rst_n),
        .key_fall_pulse     (key_fall_pulse),
        .key_rise_pulse     (key_rise_pulse),
        .dip_level          (dip_level),
        .dip_change_pulse   (dip_change_pulse),
        .dip_change_index   (dip_change_index),
        .enc1_step_pulse    (enc1_step_pulse),
        .enc1_direction     (enc1_direction),
        .enc1_count         (enc1_count),
        .enc1_sw_fall_pulse (enc1_sw_fall_pulse),
        .enc1_sw_rise_pulse (enc1_sw_rise_pulse),
        .enc2_step_pulse    (enc2_step_pulse),
        .enc2_direction     (enc2_direction),
        .enc2_count         (enc2_count),
        .enc2_sw_fall_pulse (enc2_sw_fall_pulse),
        .enc2_sw_rise_pulse (enc2_sw_rise_pulse),
        .ir_event           (ir_event),
        .ir_repeat_event    (ir_repeat_event),
        .ir_code            (ir_code),
        .ev_valid           (ev_valid),
        .ev_code            (ev_code),
        .ev_arg             (ev_arg),
        .ev_aux             (ev_aux)
    );

    // ---- 硬件回显上报器 ----
    exp_echo_reporter #(
        .CLK_FREQ_HZ (CLK_FREQ_HZ),
        .BAUD_RATE   (BAUD_RATE),
        .ECHO_ENABLE (ECHO_ENABLE)
    ) u_exp_echo_reporter (
        .clk        (clk),
        .rst_n      (rst_n),
        .ev_valid   (ev_valid),
        .ev_code    (ev_code),
        .ev_arg     (ev_arg),
        .ev_aux     (ev_aux),
        .uart_tx    (uart_tx)
    );

    // ---- 母板按键 KEY1-3 / 拨码 SW1-4：复用 J2 移植的消抖驱动 ----
    // 母板按键低有效、拨码上拨=1，与 J2 标定的输入语义一致，故直接复用 key_dip_monitor。
    wire [2:0] board_key_level;
    wire [2:0] board_key_fall_pulse;
    wire [2:0] board_key_rise_pulse;
    wire [3:0] board_sw_level;
    wire [3:0] board_sw_change_pulse;
    wire [2:0] board_sw_change_index;

    key_dip_monitor #(
        .KEY_COUNT      (3),
        .DIP_COUNT      (4),
        .DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)
    ) u_board_key_sw_monitor (
        .clk             (clk),
        .rst_n           (rst_n),
        .key_async       ({key3, key2, key1}),
        .dip_async       ({sw4, sw3, sw2, sw1}),
        .key_level       (board_key_level),
        .key_fall_pulse  (board_key_fall_pulse),
        .key_rise_pulse  (board_key_rise_pulse),
        .dip_level       (board_sw_level),
        .dip_change_pulse(board_sw_change_pulse),
        .dip_change_index(board_sw_change_index)
    );

    // ---- 操作反馈音：复用 J2 标定工程 buzzer_feedback ----
    // 事件源与校验过的互动展示固件一致（KEY / DIP / EC1 / EC2 / 编码器按压 / 红外新帧）。
    // 时钟同为 50 MHz，因此 buzzer_feedback 的默认音调参数无需换算。
    wire key_press_any;
    wire dip_change_any;
    wire dip_target;
    wire encoder_step_any;
    wire encoder_direction_any;
    wire encoder_source_any;
    wire encoder_switch_any;
    wire encoder_switch_source_any;
    wire board_sw_change_any;

    // 母板与拓展板事件并入同一反馈音混合器：任意一侧按键/拨码都发声
    assign board_sw_change_any       = |board_sw_change_pulse;
    assign key_press_any             = (|key_fall_pulse) | (|board_key_fall_pulse);
    assign dip_change_any            = (|dip_change_pulse) | board_sw_change_any;
    assign dip_target                = board_sw_change_any ? board_sw_level[board_sw_change_index]
                                                           : dip_level[dip_change_index];
    assign encoder_step_any          = enc1_step_pulse | enc2_step_pulse;
    assign encoder_direction_any     = enc1_step_pulse ? enc1_direction : enc2_direction;
    assign encoder_source_any        = enc2_step_pulse;
    assign encoder_switch_any        = enc1_sw_fall_pulse | enc2_sw_fall_pulse;
    assign encoder_switch_source_any = enc2_sw_fall_pulse;

    buzzer_feedback u_buzzer_feedback (
        .clk                   (clk),
        .rst_n                 (rst_n),
        .sound_enable          (BUZZER_ENABLE),
        .key_press             (key_press_any),
        .dip_change            (dip_change_any),
        .dip_target            (dip_target),
        .encoder_step          (encoder_step_any),
        .encoder_direction     (encoder_direction_any),
        .encoder_source        (encoder_source_any),
        .encoder_switch        (encoder_switch_any),
        .encoder_switch_source (encoder_switch_source_any),
        .ir_event              (ir_event & ~ir_repeat_event),
        .ir_action             (2'd0),
        .buzzer_n              (board_buzzer_n),
        .busy                  ()
    );

    // ---- J2 输出安全态 / 硬件回显 ----
    // key_level 与 exp_led_n 同为低有效（按下=0 / 点亮=0），因此直连即"按下即点亮"；
    // 关闭回显时输出全 1 = 四路 LED 全灭。
    assign exp_led_n       = ECHO_ENABLE ? key_level[3:0] : 4'hF;
    assign exp_ws2812_data = 1'b0;
    // EXT1 = 操作反馈音波形（拓展板外接蜂鸣器用，与母板同源）；EXT2-6 保持 0。
    assign exp_ext_o       = {5'b00000, board_buzzer_n};

endmodule
`endif

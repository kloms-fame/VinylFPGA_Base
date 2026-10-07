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
    output wire        uart_tx,

    // ===================== S2：开机状态接口（最小新增）=====================
    // ui_ev_valid：任一"已确认"用户输入的单拍脉冲（clk 域），
    //              = J2 统一事件(含按键/拨码/编码器/红外) + 母板 KEY1-3 按下。
    //              S2 顶层用它翻转出一根电平，跨到 video 域作为 Boot 跳过源。
    output wire        ui_ev_valid,
    // boot_active：video 域 Boot 状态（1=STATE_BOOT），仅用于串口可观测性，
    //              不参与任何业务逻辑。
    input  wire        boot_active,
    input  wire [23:0] media_status, // Already synchronized by top

    // ===================== S7-01B：遥测输入（顶层已同步到 clk 域）=====================
    input  wire        underrun_pulse,     // 音频欠载单拍脉冲
    input  wire        wav_buffer_low,     // WAV 缓冲低水位电平
    input  wire        wav_stream_active,  // WAV 流式播放中电平
    input  wire        mv_failed,          // MV 取帧失败电平
    input  wire        osd_err_valid,      // 错误码变化单拍脉冲
    input  wire [7:0]  osd_err_code,       // 已同步错误码

    // ===================== S3：选曲事件出口（S7-03 起由 ui_command_router 净化后输出）=====================
    // 原为 ui_event_bus 单拍事件流；S7-03 起改为 ui_command_router 的"业务命令流"
    // （红外已翻译、DIP5 已使能门控、消隐唤醒已吞首键）。下游 ui_event_bridge 语义不变。
    output wire        ui_event_valid,
    output wire [3:0]  ui_event_code,
    output wire [15:0] ui_event_arg,
    output wire [15:0] ui_event_aux,

    // ===================== S7-03：运行时状态 / 使能冻结输出 =====================
    output wire        blank_active,       // 消隐激活（DIP4 自动 + 遥控息屏手动）
    output wire        led_enable,         // DIP3 LED 总使能（S7-05 接入执行器）
    output wire        ws_enable,          // DIP6 WS 总使能（S7-05 接入执行器）
    output wire        restart_req,        // 重启确认后一拍脉冲（软复位请求）

    // ===================== X1：状态反馈执行器接线（clk 域）=====================
    input  wire [7:0]  pcm_level,          // X1B：PCM 包络（顶层已从视频域跨来）
    input  wire        mv_mode_active,
    input  wire [3:0]  ws_progress,        // X1B：进度点亮颗数 0..8
    input  wire        ws_mode_tgl,        // X1B：KEY10 模式循环翻转电平
    output wire [3:0]  board_sw_level,     // X1C：母板 SW1-4 消抖后电平（上拨=1）
    output wire        disp_mode_tgl       // X1C：母板 KEY3(B1) 每按一次翻转
);

    // 事件编码常量（与 ui_event_bus / exp_echo_reporter 各取一份，module 作用域）
    `include "exp_event_defs.vh"

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
    wire        ev_overflow_bus;   // ui_event_bus 逐源 pending 溢出单拍脉冲
    wire        cmd_valid;
    wire [3:0]  cmd_code;
    wire [15:0] cmd_arg;
    wire [15:0] cmd_aux;

    // X1A：router 给出的"已接受"单拍脉冲（LED1/LED2 业务化输入）
    wire        ir_accepted;
    wire        biz_accepted;

    // ---- S7-01B：health_monitor <-> exp_echo_reporter 的中间信号 ----
    wire        stat_req;
    wire        err_req;
    wire [7:0]  err_code;
    wire [15:0] cnt_underrun;
    wire [15:0] cnt_buffer_low;
    wire [15:0] cnt_video_fail;
    wire [15:0] cnt_ev_overflow;
    wire [31:0] fw_version;
    wire        ev_ovf_pulse;

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
        .ev_aux             (ev_aux),
        .ev_overflow        (ev_overflow_bus)
    );

    // DIP1 is reserved as the user's PRESENT declaration (up=1).
    // L3 uses a weak FPGA pulldown; expansion-board pullup must dominate it.
    // Settle after hotplug before forwarding actions; absence never fabricates KEY UP.
    localparam integer PRESENT_SETTLE = DEBOUNCE_CYCLES + AB_STABLE_CYCLES + 16;
    localparam integer PRESENT_W = $clog2(PRESENT_SETTLE + 1);
    reg [PRESENT_W-1:0] present_count;
    reg io_ready;
    reg exp_present;
    reg exp_actions_ready;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            present_count <= 0;
            io_ready <= 1'b0;
            exp_present <= 1'b0;
            exp_actions_ready <= 1'b0;
        end else if (!io_ready) begin
            if (present_count == PRESENT_SETTLE-1) begin
                io_ready <= 1'b1;
                exp_present <= dip_level[0];
                exp_actions_ready <= dip_level[0];
                present_count <= 0;
            end else
                present_count <= present_count + 1'b1;
        end else if (exp_present != dip_level[0]) begin
            exp_present <= dip_level[0];
            exp_actions_ready <= 1'b0;
            present_count <= 0;
        end else if (exp_present && !exp_actions_ready) begin
            if (present_count == PRESENT_SETTLE-1)
                exp_actions_ready <= 1'b1;
            else
                present_count <= present_count + 1'b1;
        end
    end
    wire action_valid = ev_valid && exp_actions_ready && dip_level[0];
    // DIP state changes still report while the declaration is off.
    wire report_valid = ev_valid && io_ready &&
                        ((ev_code == EV_DIP_CHANGE) || (exp_actions_ready && dip_level[0]));

    // ---- S7-03：业务命令路由（红外白名单/repeat、DIP5 使能、消隐唤醒、重启确认）----
    ui_command_router u_ui_command_router (
        .clk                (clk),
        .rst_n              (rst_n),
        .ev_valid           (action_valid),
        .ev_code            (ev_code),
        .ev_arg             (ev_arg),
        .ev_aux             (ev_aux),
        .dip_level          (dip_level),
        .cmd_valid          (cmd_valid),
        .cmd_code           (cmd_code),
        .cmd_arg            (cmd_arg),
        .cmd_aux            (cmd_aux),
        .blank_active       (blank_active),
        .led_enable         (led_enable),
        .ws_enable          (ws_enable),
        .restart_req        (restart_req),
        .ir_accepted        (ir_accepted),
        .biz_accepted       (biz_accepted)
    );

    // ---- S3：事件流引出（S7-03 起改为 router 的业务命令流，供顶层 ui_event_bridge）----
    assign ui_event_valid = cmd_valid;
    assign ui_event_code  = cmd_code;
    assign ui_event_arg   = cmd_arg;
    assign ui_event_aux   = cmd_aux;

    // ---- S7-01B：健康遥测汇聚（被动旁路，clk 域）----
    health_monitor #(
        .CLK_FREQ_HZ   (CLK_FREQ_HZ),
        .STAT_PERIOD_MS(2000),
        .FW_VERSION    (32'h0703_0002)
    ) u_health_monitor (
        .clk           (clk),
        .rst_n         (rst_n),
        .underrun_pulse(underrun_pulse),
        .buffer_low    (wav_buffer_low),
        .stream_active (wav_stream_active),
        .video_failed  (mv_failed),
        .osd_err_valid (osd_err_valid),
        .osd_err_code  (osd_err_code),
        .ev_overflow   (ev_ovf_pulse | ev_overflow_bus),
        .stat_req      (stat_req),
        .err_req       (err_req),
        .err_code      (err_code),
        .cnt_underrun  (cnt_underrun),
        .cnt_buffer_low(cnt_buffer_low),
        .cnt_video_fail(cnt_video_fail),
        .cnt_ev_overflow(cnt_ev_overflow),
        .fw_version    (fw_version)
    );

    // ---- 硬件回显上报器 ----
    exp_echo_reporter #(
        .CLK_FREQ_HZ (CLK_FREQ_HZ),
        .BAUD_RATE   (BAUD_RATE),
        .ECHO_ENABLE (ECHO_ENABLE)
    ) u_exp_echo_reporter (
        .clk        (clk),
        .rst_n      (rst_n),
        .ev_valid   (report_valid),
        .ev_code    (ev_code),
        .ev_arg     (ev_arg),
        .ev_aux     (ev_aux),
        .boot_active(boot_active),
        .media_status(media_status),
        .io_ready   (io_ready),
        .exp_present(exp_present),
        .dip_state  (dip_level),
        .stat_req   (stat_req),
        .err_req    (err_req),
        .err_code   (err_code),
        .stat_underrun   (cnt_underrun),
        .stat_buffer_low (cnt_buffer_low),
        .stat_video_fail (cnt_video_fail),
        .stat_ev_overflow(cnt_ev_overflow),
        .fw_version (fw_version),
        .uart_tx    (uart_tx),
        .ovf_pulse  (ev_ovf_pulse)
    );

    // ---- 母板按键 KEY1-3 / 拨码 SW1-4：复用 J2 移植的消抖驱动 ----
    // 母板按键低有效、拨码上拨=1，与 J2 标定的输入语义一致，故直接复用 key_dip_monitor。
    wire [2:0] board_key_level;
    wire [2:0] board_key_fall_pulse;
    wire [2:0] board_key_rise_pulse;
    wire [3:0] board_sw_change_pulse;
    wire [2:0] board_sw_change_index;

    assign disp_mode_tgl = 1'b0; // KEY3 display pages removed.

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

    // ---- S2：Boot 跳过源（含电源启动保护）----
    // 只把"用户主动动作"当作跳过请求：按键按下/抬起、编码器步进/按压、红外帧。
    //
    // 为什么不能直接用 ev_valid：
    //   sync_bit / debounce_filter 的上电初值都是 1，若某路输入真实电平时为 0
    //   （J2 拨码拨在 "0" 位、编码器静止相位为低、按键被按住、母板 key1/key2
    //   无内部上拉），消抖时间到后消抖器会判定为一次"变化"并输出脉冲。
    //   若把它当成用户操作，boot_layer 会在上电瞬间被"跳过"，表现为开机黑屏、
    //   直接显示图片 —— 这正是 S2 上板首测失败的原因。
    //
    // 处理：① 明确排除 EV_DIP_CHANGE（拨码是静态配置，不是操作，且上电必然报一次）；
    //       ② 再加 500 ms 上电保护窗，屏蔽所有输入通道的消抖收敛瞬态。
    wire ev_is_dip = (ev_code == EV_DIP_CHANGE);
    wire ev_is_ir  = (ev_code == EV_IR_FRAME) || (ev_code == EV_IR_REPEAT);

    localparam integer SKIP_GUARD_CYCLES = CLK_FREQ_HZ / 2;   // 500 ms
    reg [26:0] skip_guard_cnt;
    reg        skip_guard_done;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            skip_guard_cnt  <= 27'd0;
            skip_guard_done <= 1'b0;
        end else if (!skip_guard_done) begin
            if (skip_guard_cnt >= (SKIP_GUARD_CYCLES - 1))
                skip_guard_done <= 1'b1;
            else
                skip_guard_cnt <= skip_guard_cnt + 27'd1;
        end
    end

    // S7-03：DIP5 关闭时红外既不执行业务、也不作为 Boot 跳过源（红外业务使能门控）。
    wire ir_boot_ok = !ev_is_ir || dip_level[4];
    assign ui_ev_valid = ((action_valid & ~ev_is_dip & ir_boot_ok) | (|board_key_fall_pulse))
                         & skip_guard_done;

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
        .ir_event              (ir_event & ~ir_repeat_event & dip_level[4]),
        .ir_action             (2'd0),
        .buzzer_n              (board_buzzer_n),
        .busy                  ()
    );

    // ===================== X1A：LED1~4 业务化执行器 =====================
    // 不再回显 KEY 电平，改为状态反馈：IR 有效 / 业务动作 / 心跳 / 故障。
    // DIP3(led_enable)=0 时组合全灭（远快于 100 ms 门限）。
    reg [1:0] mv_mode_sync;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) mv_mode_sync<=0;
        else mv_mode_sync<={mv_mode_sync[0],mv_mode_active};
    end
    led_business_driver #(
        .CLK_FREQ_HZ (CLK_FREQ_HZ)
    ) u_led_business_driver (
        .clk          (clk),
        .rst_n        (rst_n),
        .en           (led_enable),
        .ir_accepted  (ir_accepted),
        .biz_accepted (biz_accepted),
        .fault        (err_code != 8'd0),
        .mv_active    (mv_mode_sync[1]),
        .led_n        (exp_led_n)
    );

    // ===================== X1B：WS2812 灯效执行器 =====================
    // level/progress 由顶层从视频域以"数据 + 翻转"方式跨来（只读旁路，不反压音频）。
    // KEY10 在本域翻转模式；DIP6 关闭时先补发整帧黑色再停刷新。
    ws2812_effects #(
        .PIXEL_COUNT  (8),
        .CLK_FREQ_HZ  (CLK_FREQ_HZ),
        .REFRESH_MS   (20)
    ) u_ws2812_effects (
        .clk       (clk),
        .rst_n     (rst_n),
        .enable    (ws_enable),
        .mode_tgl  (ws_mode_tgl),
        .level     (pcm_level),
        .progress  (ws_progress),
        .mute      (1'b0),          // X5 前恒 0
        .ws_data   (exp_ws2812_data)
    );

    // ---- J2 其余输出安全态 / 硬件回显 ----
    // EXT1 = 操作反馈音波形（拓展板外接蜂鸣器用，与母板同源）；EXT2-6 保持 0。
    assign exp_ext_o       = {5'b00000, board_buzzer_n};

endmodule
`endif

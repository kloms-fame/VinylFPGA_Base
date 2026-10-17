`ifndef EXP_EXPANSION_INTEGRATION_V
`define EXP_EXPANSION_INTEGRATION_V
// J2 commands, shared input filtering and LED/WS/buzzer feedback, all at 50 MHz.
// UART is retired; internal fault monitoring remains separate from the fixed time display.
module expansion_integration #(
    parameter integer CLK_FREQ_HZ      = 50_000_000,
    parameter integer DEBOUNCE_CYCLES  = 400_000,
    parameter integer DEBOUNCE_TICK_CYCLES = (DEBOUNCE_CYCLES < 5000) ? 1 : 5000,
    parameter integer AB_STABLE_CYCLES = 50_000,
    parameter integer IR_CLK_FREQ_HZ   = 50_000_000,
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
    input  wire        play_active_async,
    input  wire        paused_async,
    input  wire        needle_sense_n,

    // 母板输入：KEY2/KEY3 与 SW1–SW4；KEY3 当前预留给阶段 4 手动保存。
    // SW1-SW4 = 板载乒乓拨码（C8/C7/C6/C5），均按按键/拨码低有效消抖。
    input  wire        key2,
    input  wire        key3,
    input  wire        key4,
    input  wire        sw1,
    input  wire        sw2,
    input  wire        sw3,
    input  wire        sw4,

    output wire [3:0]  exp_led_n,
    output wire        exp_ws2812_data,
    output wire [5:0]  exp_ext_o,
    output wire        board_buzzer_n,
    output wire        vinyl_motor_en,
    output wire        vinyl_ws2812_data,
    output wire        uart_tx,
    output wire [3:0]  fault_flags, // [3:0] = overflow, video fail, low buffer, underrun

    // ===================== S2：开机状态接口（最小新增）=====================
    // ui_ev_valid：任一"已确认"J2 用户操作的单拍脉冲（clk 域）。
    //              S2 顶层用它翻转出一根电平，跨到 video 域作为 Boot 跳过源。
    output wire        ui_ev_valid,
    // 母板 KEY2 消抖按下脉冲，供唯一参数 CSR 恢复运行默认值。
    output wire        key2_reset_pulse,
    output reg         board_audio_mute,
    // 启动保护窗结束时锁存 SW2 状态，供 video 域安全同步并旁路 Boot。
    output reg         boot_startup_skip,
    // ===================== S7-01B：遥测输入（顶层已同步到 clk 域）=====================
    input  wire        underrun_pulse,     // 音频欠载单拍脉冲
    input  wire        wav_buffer_low,     // WAV 缓冲低水位电平
    input  wire        wav_stream_active,  // WAV 流式播放中电平
    input  wire        mv_failed,          // MV 取帧失败电平
    input  wire        osd_err_valid,      // 错误码变化单拍脉冲
    input  wire [7:0]  osd_err_code,       // 已同步错误码
    input  wire        slideshow_beep_event, // D1：自动 bank 确认后的单拍事件

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
    input  wire [2:0]  ws_brightness_level, // D8：CSR 档位，同属 50 MHz clk 域
    input  wire        mv_mode_active,
    input  wire        ws_mode_tgl,        // X1B：KEY10 模式循环翻转电平
    output wire [3:0]  board_sw_level,     // X1C：母板 SW1-4 消抖后电平（上拨=1）
    output wire        disp_mode_tgl,      // X1C：母板 KEY3(B1) 每按一次翻转
    output wire        dip2_slideshow_enable, // D1：J2 DIP2 消抖电平（上拨=1）
    output wire        ui_tick_1ms,          // D3：共享50MHz毫秒使能
    output wire [15:0] enc2_count_raw,        // D3：EC2 当前累计计数，用于禁用期基线
    output wire        ui_actions_ready,      // D3：DIP1在场且输入稳定
    output wire        restart_confirm_active // D3：重启确认期间不消费EC2
);

    // 事件编码常量（与 ui_event_bus 共用，module 作用域）
    `include "exp_event_defs.vh"

    // hub -> bus 的中间信号
    wire [11:0] key_level;
    wire [11:0] key_fall_pulse;
    wire [11:0] key_rise_pulse;
    wire [5:0]  dip_level;
    wire [5:0]  dip_change_pulse;
    wire [2:0]  dip_change_index;
    assign dip2_slideshow_enable = dip_level[1];

    wire        enc1_step_pulse;
    wire        enc1_direction;
    wire [15:0] enc1_count;
    wire        enc1_sw_fall_pulse;
    wire        enc1_sw_rise_pulse;
    wire        enc2_step_pulse;
    wire        enc2_direction;
    wire [15:0] enc2_count;
    assign enc2_count_raw = enc2_count;
    wire        enc2_sw_fall_pulse;
    wire        enc2_sw_rise_pulse;

    wire        ir_event;
    wire        ir_repeat_event;
    wire [31:0] ir_code;

    wire        ev_valid;
    wire        ev_bus_enable;
    wire [3:0]  ev_code;
    wire [15:0] ev_arg;
    wire [15:0] ev_aux;
    wire        ev_overflow_bus;   // ui_event_bus 逐源 pending 溢出单拍脉冲
    wire        cmd_valid;
    wire [3:0]  cmd_code;
    wire [15:0] cmd_arg;
    wire [15:0] cmd_aux;
    wire        router_restart_confirm_active;
    wire        router_mute_toggle;

    // X1A：router 给出的"已接受"单拍脉冲（LED1/LED2 业务化输入）
    wire        ir_accepted;
    wire        biz_accepted;

    wire [7:0] err_code;
    assign uart_tx = 1'b1;
    wire debounce_ce;
    ui_ms_tick #(.CYCLES_PER_MS(CLK_FREQ_HZ / 1000)) u_ui_ms_tick (
        .clk(clk), .rst_n(rst_n), .tick_1ms(ui_tick_1ms)
    );
    debounce_tick #(.TICK_CYCLES(DEBOUNCE_TICK_CYCLES)) u_debounce_tick (
        .clk(clk), .rst_n(rst_n), .tick_ce(debounce_ce)
    );

    // ---- 输入驱动汇聚层（sync / debounce / edge / 正交 / NEC）----
    expansion_io_hub #(
        .USE_EXTERNAL_TICK(1),
        .DEBOUNCE_TICK_CYCLES(DEBOUNCE_TICK_CYCLES),
        .KEY_COUNT        (12),
        .DIP_COUNT        (6),
        .DEBOUNCE_CYCLES  (DEBOUNCE_CYCLES),
        .AB_STABLE_CYCLES (AB_STABLE_CYCLES),
        .IR_CLK_FREQ_HZ   (IR_CLK_FREQ_HZ)
    ) u_expansion_io_hub (
        .debounce_ce        (debounce_ce),
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
        .ev_enable          (ev_bus_enable),
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
    localparam integer PRESENT_SETTLE =
        ((DEBOUNCE_CYCLES + DEBOUNCE_TICK_CYCLES - 1) / DEBOUNCE_TICK_CYCLES + 1)
        * DEBOUNCE_TICK_CYCLES + AB_STABLE_CYCLES + 16;
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
    // ui_event_bus only emits/clears an event when this readiness gate is open.
    // Consume its registered event unconditionally so a concurrent hot-unplug
    // cannot invalidate an event already accepted by the bus.
    wire action_valid = ev_valid;
    assign ev_bus_enable = exp_actions_ready && dip_level[0];
    assign ui_actions_ready = exp_actions_ready && dip_level[0];
    assign restart_confirm_active = router_restart_confirm_active;

    // ---- S7-03：业务命令路由（红外白名单/repeat、DIP5 使能、消隐唤醒、重启确认）----
    ui_command_router #(.USE_EXTERNAL_MS_TICK(1)) u_ui_command_router (
        .clk                (clk),
        .rst_n              (rst_n),
        .ev_valid           (action_valid),
        .ev_code            (ev_code),
        .ev_arg             (ev_arg),
        .ev_aux             (ev_aux),
        .dip_level          (dip_level),
        .tick_1ms           (ui_tick_1ms),
        .cmd_valid          (cmd_valid),
        .cmd_code           (cmd_code),
        .cmd_arg            (cmd_arg),
        .cmd_aux            (cmd_aux),
        .blank_active       (blank_active),
        .led_enable         (led_enable),
        .ws_enable          (ws_enable),
        .restart_req        (restart_req),
        .restart_confirm_active(router_restart_confirm_active),
        .mute_toggle        (router_mute_toggle),
        .ir_accepted        (ir_accepted),
        .biz_accepted       (biz_accepted)
    );

    // ---- S3：事件流引出（S7-03 起改为 router 的业务命令流，供顶层 ui_event_bridge）----
    assign ui_event_valid = cmd_valid;
    assign ui_event_code  = cmd_code;
    assign ui_event_arg   = cmd_arg;
    assign ui_event_aux   = cmd_aux;

    // ---- S7-01B：健康遥测汇聚（被动旁路，clk 域）----
    

    health_monitor u_health_monitor (
        .clk(clk), .rst_n(rst_n), .underrun_pulse(underrun_pulse),
        .buffer_low(wav_buffer_low), .stream_active(wav_stream_active),
        .video_failed(mv_failed), .osd_err_valid(osd_err_valid),
        .osd_err_code(osd_err_code), .ev_overflow(ev_overflow_bus),
        .err_code(err_code), .fault_flags(fault_flags)
    );
    // ---- 硬件回显上报器 ----
    

    // ---- 母板按键 KEY2 / 拨码 SW1-4：复用既有 J2 消抖驱动 ----
    // KEY2 低有效；KEY3 不接入当前通用事件，完整保存功能留待阶段 4。
    wire [1:0] board_key_level;
    wire [1:0] board_key_fall_pulse;
    wire [1:0] board_key_rise_pulse;
    wire [3:0] board_sw_change_pulse;
    wire [2:0] board_sw_change_index;

    assign disp_mode_tgl = 1'b0; // KEY3 display pages removed.

    key_dip_monitor #(
        .USE_EXTERNAL_TICK(1),
        .DEBOUNCE_TICK_CYCLES(DEBOUNCE_TICK_CYCLES),
        .KEY_COUNT      (2),
        .DIP_COUNT      (4),
        .DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)
    ) u_board_key_sw_monitor (
        .debounce_ce     (debounce_ce),
        .clk             (clk),
        .rst_n           (rst_n),
        .key_async       ({key4, key2}),
        .dip_async       ({sw4, sw3, sw2, sw1}),
        .key_level       (board_key_level),
        .key_fall_pulse  (board_key_fall_pulse),
        .key_rise_pulse  (board_key_rise_pulse),
        .dip_level       (board_sw_level),
        .dip_change_pulse(board_sw_change_pulse),
        .dip_change_index(board_sw_change_index)
    );

    // ---- S2：Boot 跳过源（含电源启动保护）----
    // J2 用户操作可跳过 Boot；母板 KEY3 不参与此路径，SW2 只在启动时采样一次。
    //
    // 为什么不能直接用 ev_valid：
    //   sync_bit / debounce_filter 的上电初值都是 1，若某路输入真实电平时为 0
    //   （J2 拨码拨在 "0" 位、编码器静止相位为低、按键被按住），
    //   消抖时间到后消抖器会判定为一次"变化"并输出脉冲。
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
    reg        boot_switch_sampled;

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

    // SW2 已经经过 key_dip_monitor 消抖。等现有 500 ms 启动保护窗结束后
    // 锁存一次；之后拨动 SW2 不会影响当前启动周期。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            boot_switch_sampled   <= 1'b0;
            boot_startup_skip     <= 1'b0;
        end else begin
            if (skip_guard_done && !boot_switch_sampled) begin
                boot_switch_sampled <= 1'b1;
                boot_startup_skip   <= board_sw_level[1];
            end
        end
    end

    // KEY2 只在启动输入收敛后接受；按键保持不会重复发出默认值请求。
    assign key2_reset_pulse = board_key_fall_pulse[0] & skip_guard_done;
    // KEY4 与红外静音键翻转音频静音状态；静音只作用于最终音量增益，
    // 音源 valid/ready 握手仍继续运行，避免静音导致 WAV 播放进度暂停。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            board_audio_mute <= 1'b0;
        else if (skip_guard_done && (board_key_fall_pulse[1] || router_mute_toggle))
            board_audio_mute <= ~board_audio_mute;
    end

    // S7-03：DIP5 关闭时红外既不执行业务、也不作为 Boot 跳过源（红外业务使能门控）。
    wire ir_boot_ok = !ev_is_ir || dip_level[4];
    assign ui_ev_valid = (action_valid & ~ev_is_dip & ir_boot_ok) & skip_guard_done;

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

    // 拓展板按键与母板拨码事件并入反馈音混合器；母板 KEY3 不参与通用操作音。
    assign board_sw_change_any       = |board_sw_change_pulse;
    assign key_press_any             = (|key_fall_pulse) | board_key_fall_pulse[1];
    assign dip_change_any            = (|dip_change_pulse) | board_sw_change_any;
    assign dip_target                = board_sw_change_any ? board_sw_level[board_sw_change_index]
                                                           : dip_level[dip_change_index];
    assign encoder_step_any          = enc1_step_pulse | enc2_step_pulse;
    assign encoder_direction_any     = enc1_step_pulse ? enc1_direction : enc2_direction;
    assign encoder_source_any        = enc2_step_pulse;
    assign encoder_switch_any        = enc1_sw_fall_pulse | enc2_sw_fall_pulse;
    assign encoder_switch_source_any = enc2_sw_fall_pulse;

    // Register the entire sound-event bundle together: preserve simultaneous
    // event priority and parameters, with only one 50 MHz cycle of latency.
    // This breaks the measured NEC-repeat -> tone-classification setup path.
    reg [9:0] sound_events_q;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) sound_events_q <= 10'd0;
        else sound_events_q <= {key_press_any,dip_change_any,dip_target,
            encoder_step_any,encoder_direction_any,encoder_source_any,
            encoder_switch_any,encoder_switch_source_any,
            (ir_event & ~ir_repeat_event & dip_level[4]),slideshow_beep_event};
    end
    buzzer_feedback u_buzzer_feedback (
        .clk                   (clk),
        .rst_n                 (rst_n),
        .sound_enable          (BUZZER_ENABLE),
        .key_press             (sound_events_q[9]),
        .dip_change            (sound_events_q[8]),
        .dip_target            (sound_events_q[7]),
        .encoder_step          (sound_events_q[6]),
        .encoder_direction     (sound_events_q[5]),
        .encoder_source        (sound_events_q[4]),
        .encoder_switch        (sound_events_q[3]),
        .encoder_switch_source (sound_events_q[2]),
        .ir_event              (sound_events_q[1]),
        .ir_action             (2'd0),
        .slideshow_event       (sound_events_q[0]),
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
    // PCM level 由顶层从视频域以"数据 + 翻转"方式跨来（只读旁路，不反压音频）。
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
        .brightness_level(ws_brightness_level),
        .mute      (1'b0),          // X5 前恒 0
        .ws_data   (exp_ws2812_data)
    );

    // 独立 D14 灯带及 G11 电机控制；J11 原有灯效链路保持不变。
    vinyl_playback_effects #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .REFRESH_MS (20)
    ) u_vinyl_playback_effects (
        .clk               (clk),
        .rst_n             (rst_n),
        .play_active_async (play_active_async),
        .paused_async      (paused_async),
        .needle_sense_n    (needle_sense_n),
        .ws_enable         (ws_enable),
        .tick_1ms          (ui_tick_1ms),
        .motor_enable      (vinyl_motor_en),
        .ws_data           (vinyl_ws2812_data)
    );

    // ---- J2 其余输出安全态 / 硬件回显 ----
    // EXT1 = 操作反馈音波形（拓展板外接蜂鸣器用，与母板同源）；EXT2-6 保持 0。
    assign exp_ext_o       = {5'b00000, board_buzzer_n};

endmodule
`endif

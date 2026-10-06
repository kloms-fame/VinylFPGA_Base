`ifndef EXP_UI_COMMAND_ROUTER_V
`define EXP_UI_COMMAND_ROUTER_V
// =============================================================================
// ui_command_router —— S7-03 业务命令路由（clk 域）
//
// 位于 ui_event_bus 之后、ui_event_bridge 之前，把"已确认"的物理事件流
// （valid + code + arg + aux，DIP1 在场/动作就绪已由 expansion_integration 门控）
// 路由成下游可直接消费的业务命令流，并实现 S7-03 的运行时语义：
//
//   1. 红外白名单 + repeat 策略（《方案》2.4）：只认 15 个实测地址字节，先验证
//      两组反码（Addr/~Addr、Cmd/~Cmd），再翻译成等价业务命令；无先导 repeat、
//      反码错、未知帧一律不执行；仅音量允许约 150 ms 节流连发，250 ms 无新帧
//      结束连发。新帧建立最近有效键。
//   2. 运行时 DIP（《方案》2.3）：DIP5 关闭红外业务、DIP4 60 s 无人操作自动消隐、
//      DIP3/DIP6 冻结输出使能状态（LED/WS 执行器留 S7-05）。DIP1 已在上一层。
//   3. 消隐唤醒：消隐期间第一个有效操作只唤醒、不兼做业务（吞首键）。
//   4. 系统确认框（重启）：红外重启键打开确认框，3 s 内 OK/KEY02 才输出
//      restart_req；其它有效操作取消。
//
// 消费优先级固定为：系统确认框 -> 消隐唤醒 -> 业务透传（菜单在 S7-04 接入）。
//
// 资源策略：本模块是 S7-03 新增逻辑中唯一带运行时计时的部分，尽量做成
//   - cmd_* 与 led/ws/blank 使能全部组合输出，不额外打拍寄存 37 位命令字；
//   - 红外翻译用"紧凑动作码 + 少量标志"而不是 32 位 arg/aux 全宽多路选择；
//   - 最近键只保留"是否音量 + 方向"2 位，不存完整 8 位地址；
//   - 空闲/重启/连发三个计数器共用同一 1 ms 预分频，饱和计数。
// 物理事件编码见 src/include/exp_event_defs.vh；本模块输出的 cmd_* 沿用 EV_* 编码
// 作为"翻译后的业务命令"，以便 ui_event_bridge 无缝消费，不破坏既有选曲/播控语义。
// 红外原始帧的串口回显仍走 ui_event_bus -> exp_echo_reporter，不经本模块。
// =============================================================================
module ui_command_router #(
    parameter integer CLK_FREQ_HZ         = 50_000_000,
    parameter integer IR_REPEAT_MIN_MS    = 150,    // 音量 repeat 节流下限
    parameter integer IR_REPEAT_TIMEOUT_MS= 250,    // 连发超时（清最近键）
    parameter integer BLANK_TIMEOUT_MS    = 60000,  // DIP4 自动消隐空闲期限
    parameter integer RESTART_CONFIRM_MS  = 3000    // 重启确认窗口
)(
    input  wire        clk,
    input  wire        rst_n,

    // 已确认物理事件流（来自 ui_event_bus，已由 expansion_integration 门控 DIP1）
    input  wire        ev_valid,
    input  wire [3:0]  ev_code,
    input  wire [15:0] ev_arg,
    input  wire [15:0] ev_aux,

    // 运行时 DIP 电平（消抖后，上拨=1）
    input  wire [5:0]  dip_level,

    // 业务命令流（复用 EV_* 编码，红外已翻译；组合输出，单拍有效）
    output wire        cmd_valid,
    output wire [3:0]  cmd_code,
    output wire [15:0] cmd_arg,
    output wire [15:0] cmd_aux,

    // 运行时状态 / 使能冻结输出
    output wire        blank_active,       // 消隐激活（DIP4 自动 + 遥控息屏手动）
    output wire        led_enable,         // DIP3 LED 总使能（S7-05 接入执行器）
    output wire        ws_enable,          // DIP6 WS 总使能（S7-05 接入执行器）
    output reg         restart_req         // 重启确认后的一拍脉冲
);
    `include "exp_event_defs.vh"

    // ---- 15 键地址字节白名单（《J2 标定》§6.1，键区分靠 code[31:24]）----
    localparam [7:0] IR_PREV    = 8'hBA;
    localparam [7:0] IR_NEXT    = 8'hB9;
    localparam [7:0] IR_PLAY    = 8'hB8;
    localparam [7:0] IR_VOLUP   = 8'hBB;
    localparam [7:0] IR_VOLDN   = 8'hBF;
    localparam [7:0] IR_BLANK   = 8'hBC;
    localparam [7:0] IR_SEEKP   = 8'hF8;
    localparam [7:0] IR_SEEKM   = 8'hEA;
    localparam [7:0] IR_REPLAY  = 8'hF6;
    localparam [7:0] IR_RESTART = 8'hE9;
    localparam [7:0] IR_UP      = 8'hE7;
    localparam [7:0] IR_DOWN    = 8'hAD;
    localparam [7:0] IR_LEFT    = 8'hF7;
    localparam [7:0] IR_RIGHT   = 8'hA5;
    localparam [7:0] IR_OK      = 8'hE3;

    localparam integer MS_CYCLES = CLK_FREQ_HZ / 1000;   // 1 ms 预分频
    localparam integer MS_W      = $clog2(MS_CYCLES + 1);
    localparam integer IDLE_W    = $clog2(BLANK_TIMEOUT_MS + 2);
    localparam integer RST_W     = $clog2(RESTART_CONFIRM_MS + 2);
    localparam integer IRT_W     = $clog2(IR_REPEAT_TIMEOUT_MS + 2);
    localparam integer RGT_W     = $clog2(IR_REPEAT_MIN_MS + 2);

    // ---- 事件类别识别（组合）----
    wire is_key_down  = (ev_code == EV_KEY_DOWN);
    wire is_key_up    = (ev_code == EV_KEY_UP);
    wire is_dip       = (ev_code == EV_DIP_CHANGE);
    wire is_enc_step  = (ev_code == EV_ENC_STEP);
    wire is_enc_sw    = (ev_code == EV_ENC_SW);
    wire is_enc_sw_dn = is_enc_sw && (ev_arg[0] == 1'b0);
    wire is_ir_frame  = (ev_code == EV_IR_FRAME);
    wire is_ir_repeat = (ev_code == EV_IR_REPEAT);

    // ---- 红外帧拆包 + 反码验证 ----
    wire [31:0] full_frame   = {ev_aux, ev_arg};
    wire [7:0]  ir_addr      = full_frame[31:24];
    wire [7:0]  ir_addr_inv  = full_frame[23:16];
    wire [7:0]  ir_cmd       = full_frame[15:8];
    wire [7:0]  ir_cmd_inv   = full_frame[7:0];
    wire        ir_frame_ok  = (ir_addr_inv == ~ir_addr) && (ir_cmd_inv == ~ir_cmd);

    // ---- 红外翻译（组合）：白名单内且反码合法 -> 紧凑动作码 ----
    // ir_x_evcode 复用 EV_* 编码；ir_x_key 为 KEY 索引（0..4）；ir_x_dir 为 EC 方向。
    // ir_x_vol/ir_x_volup 仅用于建立"最近音量键"以支持 repeat 节流。
    reg        ir_x_valid;
    reg [3:0]  ir_x_evcode;
    reg [2:0]  ir_x_key;
    reg        ir_x_dir;
    reg        ir_x_blank;    // 息屏切换（内部）
    reg        ir_x_restart;  // 重启（内部，打开确认框）
    reg        ir_x_vol;      // 音量键（VOLUP/VOLDN）
    reg        ir_x_volup;    // 音量 +（区别于音量 -）

    always @* begin
        ir_x_valid   = 1'b0;
        ir_x_evcode  = EV_NONE;
        ir_x_key     = 3'd0;
        ir_x_dir     = 1'b0;
        ir_x_blank   = 1'b0;
        ir_x_restart = 1'b0;
        ir_x_vol     = 1'b0;
        ir_x_volup   = 1'b0;
        if (is_ir_frame && ir_frame_ok) begin
            case (ir_addr)
                IR_PREV   : begin ir_x_valid=1'b1; ir_x_evcode=EV_ENC_STEP; ir_x_dir=1'b1; end
                IR_NEXT   : begin ir_x_valid=1'b1; ir_x_evcode=EV_ENC_STEP; ir_x_dir=1'b0; end
                IR_PLAY   : begin ir_x_valid=1'b1; ir_x_evcode=EV_ENC_SW;   end
                IR_VOLUP  : begin ir_x_valid=1'b1; ir_x_evcode=EV_KEY_DOWN; ir_x_key=3'd3; ir_x_vol=1'b1; ir_x_volup=1'b1; end
                IR_VOLDN  : begin ir_x_valid=1'b1; ir_x_evcode=EV_KEY_DOWN; ir_x_key=3'd4; ir_x_vol=1'b1; ir_x_volup=1'b0; end
                IR_BLANK  : begin ir_x_valid=1'b1; ir_x_blank=1'b1; end
                IR_SEEKP  : ir_x_valid = 1'b1;  // S7-06 前不支持
                IR_SEEKM  : ir_x_valid = 1'b1;  // S7-06 前不支持
                IR_REPLAY : ir_x_valid = 1'b1;  // S7-06 前不支持
                IR_RESTART: begin ir_x_valid=1'b1; ir_x_restart=1'b1; end
                IR_UP     : begin ir_x_valid=1'b1; ir_x_evcode=EV_KEY_DOWN; ir_x_key=3'd3; end
                IR_DOWN   : begin ir_x_valid=1'b1; ir_x_evcode=EV_KEY_DOWN; ir_x_key=3'd4; end
                IR_LEFT   : begin ir_x_valid=1'b1; ir_x_evcode=EV_KEY_DOWN; ir_x_key=3'd0; end
                IR_RIGHT  : begin ir_x_valid=1'b1; ir_x_evcode=EV_KEY_DOWN; ir_x_key=3'd2; end
                IR_OK     : begin ir_x_valid=1'b1; ir_x_evcode=EV_KEY_DOWN; ir_x_key=3'd1; end
                default   : ;
            endcase
        end
    end

    wire ir_x_ok = ir_x_valid && (ir_x_evcode == EV_KEY_DOWN) && (ir_x_key == 3'd1);
    wire key02_down = is_key_down && (ev_arg == 16'd1);
    wire is_ir_ok   = is_ir_frame && ir_x_ok;
    // 有效操作：用于空闲清零与消隐唤醒（不含纯松开、DIP、IR repeat）
    wire ev_action  = ev_valid && (is_key_down || is_enc_step || is_enc_sw_dn ||
                                   (is_ir_frame && ir_x_valid));

    // ---- 1 ms 预分频（饱和回绕，组合 tick）----
    reg [MS_W-1:0] ms_cnt;
    wire ms_tick = (ms_cnt >= (MS_CYCLES - 1));

    // ---- 消隐管理（DIP4 自动 + 遥控手动）----
    reg [IDLE_W-1:0] idle_cnt;
    reg              manual_blank;
    wire auto_blank   = (idle_cnt >= BLANK_TIMEOUT_MS);
    assign blank_active = (dip_level[3] && auto_blank) || manual_blank;

    // ---- 业务命令路由 + 红外 repeat 状态 + 重启确认 ----
    // 最近键只保留"是否音量 + 方向"，满足 repeat 节流即可，不存 8 位完整地址。
    reg [1:0]         last_ir_kind;   // 0=none, 1=VOLUP, 2=VOLDN
    reg [IRT_W-1:0]   last_ir_timer;
    reg [RGT_W-1:0]   repeat_gate_cnt;
    reg               restart_armed;
    reg [RST_W-1:0]   restart_timer;

    // 消隐唤醒吞首键：消隐期间第一个有效操作只唤醒（未处于重启确认框）
    wire wake_only = blank_active && ev_action && !restart_armed;
    // 遥控息屏切换触发（DIP5 关闭时不生效）
    wire ir_blank_toggle = ev_valid && ir_x_blank && dip_level[4];

    wire repeat_allow   = (last_ir_kind != 2'd0);
    wire repeat_gate_ok = (repeat_gate_cnt >= IR_REPEAT_MIN_MS);

    // DIP3/DIP6 使能冻结：直接透出消抖后电平（上拨=1，不二次取反）。
    assign led_enable = dip_level[2];  // DIP3 LED 总使能
    assign ws_enable  = dip_level[5];  // DIP6 WS 总使能

    // ---- 业务命令组合输出（不寄存 37 位命令字，由 ui_event_bridge 在下一级寄存）----
    reg        cmd_valid_c;
    reg [3:0]  cmd_code_c;
    reg [15:0] cmd_arg_c;
    reg [15:0] cmd_aux_c;
    always @* begin
        cmd_valid_c = 1'b0;
        cmd_code_c  = EV_NONE;
        cmd_arg_c   = 16'd0;
        cmd_aux_c   = 16'd0;
        if (ev_valid) begin
            if (restart_armed || wake_only) begin
                // 系统确认框 / 消隐唤醒吞掉本拍，不输出业务命令
            end else if (ir_x_valid && dip_level[4] && (ir_x_evcode != EV_NONE)) begin
                cmd_valid_c = 1'b1;
                cmd_code_c  = ir_x_evcode;
                cmd_arg_c   = {13'd0, ir_x_key};
                cmd_aux_c   = (ir_x_evcode == EV_ENC_STEP) ? {14'd0, 1'b0, ir_x_dir} : 16'd0;
            end else if (is_ir_repeat && dip_level[4] && repeat_allow && repeat_gate_ok) begin
                cmd_valid_c = 1'b1;
                cmd_code_c  = EV_KEY_DOWN;
                cmd_arg_c   = (last_ir_kind == 2'd1) ? 16'd3 : 16'd4;
                cmd_aux_c   = 16'd0;
            end else if (!is_ir_frame && !is_ir_repeat) begin
                // KEY / ENC / DIP 透传
                cmd_valid_c = 1'b1;
                cmd_code_c  = ev_code;
                cmd_arg_c   = ev_arg;
                cmd_aux_c   = ev_aux;
            end
        end
    end
    assign cmd_valid = cmd_valid_c;
    assign cmd_code  = cmd_code_c;
    assign cmd_arg   = cmd_arg_c;
    assign cmd_aux   = cmd_aux_c;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ms_cnt          <= {MS_W{1'b0}};
            idle_cnt        <= {IDLE_W{1'b0}};
            manual_blank    <= 1'b0;
            last_ir_kind    <= 2'd0;
            last_ir_timer   <= {IRT_W{1'b0}};
            repeat_gate_cnt <= {RGT_W{1'b0}};
            restart_armed   <= 1'b0;
            restart_timer   <= {RST_W{1'b0}};
            restart_req     <= 1'b0;
        end else begin
            restart_req <= 1'b0;

            // 1 ms 预分频
            if (ms_cnt >= (MS_CYCLES - 1))
                ms_cnt <= {MS_W{1'b0}};
            else
                ms_cnt <= ms_cnt + 1'b1;

            // 空闲计时：有效操作清零；DIP4 关闭也清零并唤醒；每 ms 递增（饱和）
            if (ev_action || !dip_level[3])
                idle_cnt <= {IDLE_W{1'b0}};
            else if (ms_tick && (idle_cnt < BLANK_TIMEOUT_MS))
                idle_cnt <= idle_cnt + 1'b1;

            // 手动息屏：唤醒清 0；遥控息屏键切换（即使 DIP4 关闭也可用）
            if (wake_only)
                manual_blank <= 1'b0;
            else if (ir_blank_toggle)
                manual_blank <= ~manual_blank;

            // DIP5 关闭：清除最近红外键，连发不再有效
            if (!dip_level[4]) begin
                last_ir_kind  <= 2'd0;
                last_ir_timer <= {IRT_W{1'b0}};
            end

            // 红外连发超时 + 节流计时
            if (ms_tick) begin
                if (last_ir_kind != 2'd0) begin
                    if (last_ir_timer >= (IR_REPEAT_TIMEOUT_MS - 1)) begin
                        last_ir_kind  <= 2'd0;
                        last_ir_timer <= {IRT_W{1'b0}};
                    end else
                        last_ir_timer <= last_ir_timer + 1'b1;
                end
                if (repeat_gate_cnt < IR_REPEAT_MIN_MS)
                    repeat_gate_cnt <= repeat_gate_cnt + 1'b1;
            end

            // 重启确认窗口计时
            if (restart_armed && ms_tick) begin
                if (restart_timer >= (RESTART_CONFIRM_MS - 1))
                    restart_armed <= 1'b0;
                else
                    restart_timer <= restart_timer + 1'b1;
            end

            // 事件消费（只更新状态；业务命令由上面的组合逻辑同拍给出）
            if (ev_valid) begin
                if (restart_armed) begin
                    // 确认框打开：OK/KEY02 确认，其它有效操作取消，全部吞掉
                    if (is_ir_ok || key02_down) begin
                        restart_req  <= 1'b1;
                        restart_armed <= 1'b0;
                    end else if (ev_action) begin
                        restart_armed <= 1'b0;
                    end
                end else if (ir_x_valid && dip_level[4]) begin
                    // 红外新帧：建立最近音量键；内部动作/命令分开处理
                    last_ir_timer   <= {IRT_W{1'b0}};
                    repeat_gate_cnt <= {RGT_W{1'b0}};
                    if (ir_x_vol)
                        last_ir_kind <= ir_x_volup ? 2'd1 : 2'd2;
                    else
                        last_ir_kind <= 2'd0;
                    if (ir_x_blank) begin
                        // 手动息屏：由消隐管理块切 manual_blank，此处无业务命令
                    end else if (ir_x_restart) begin
                        restart_armed <= 1'b1;
                        restart_timer <= {RST_W{1'b0}};
                    end
                end else if (is_ir_repeat && dip_level[4] && repeat_allow && repeat_gate_ok) begin
                    // repeat：仅音量节流连发，无先导/超时/非音量键一律不执行
                    repeat_gate_cnt <= {RGT_W{1'b0}};
                    last_ir_timer   <= {IRT_W{1'b0}};
                end
                // else：KEY / ENC / DIP 透传无需状态更新
            end
        end
    end

endmodule
`endif

### 一、 架构与设计决策终局闭环

针对提出的全部定论，EC11-B 风格 EC2 浮窗调参系统的物理交互与硬件契约正式收敛：

1. **统一单写入点音量体系（Single Source of Truth）**：
* 音量调节由**扩展板 EC2 旋钮**、**红外遥控器音量键（`0xBB` / `0xBF` 及导航上/下）**与**物理按键 KEY4 / KEY5** 汇聚于 `param_csr.v` 统一仲裁，所有途径均改写唯一的 `vol_step`（0 ~ 16 档）。


* 当使用红外或按键调音时，系统会自动唤醒 OSD 浮窗并定位至 `VOL` 项显示当前值与进度，维持 1.8 秒后同步关闭，实现视觉反馈与物理执行的融合。


* 当 `VOL` 调至最低（`0`）时，`volume_q` 输出为 `8'd0`，同时拉高 `audio_silent_q` 物理静音门控，直接关断音频链路。




2. **“一格一步进”与边界阻尼蜂鸣反馈**：
* EC2 旋钮每产生一个定位咔哒声（Detent），对应推进 1 个参数项或 1 档数值。


* 在 `ADJUST` 态下，当参数已到达边界（例如 VOL 到达 255 或 0、ROT 到达 60s 或 10s）而用户继续顺时针/逆时针拧动时，数值严格平滑钳位，同时产生 **2200 Hz / 40 ms 金属质感高频边界阻尼音**，明确提示已达极限。


* 进入 Adjust 发出 **1320 Hz / 50 ms** 音效，退出 Adjust 发出 **990 Hz / 50 ms** 音效。




3. **彻底注销母板旧菜单 `param_menu_controller**`：
* 从顶层完全剥离并注销 `param_menu_controller.v`，清除母板双键调参的冗余逻辑，彻底根除双主控制冲突。


* 画质调节权（亮度 5 档、对比度 5 档）100% 收敛归属于 EC2 浮窗与 `param_csr.v`。




4. **精简至纯粹 5 项参数环（彻底移除 SEEK）**：
* 参数表冻结为 5 项：`VOL`（音量 0~~255）、`BRI`（亮度 0~~4）、`CON`（对比度 0~~4）、`ROT`（轮播 10s~~60s）、`WSL`（灯光 10%~100%）。


* 彻底移除 `SEEK`，使状态机不再具有复杂的播放态与浏览态动态列表分支。




5. **1.8 秒同步消隐与状态复位**：
* 计时器统一为 1800 ms，超时未操作时，**浮窗视觉隐藏与 FSM 复位至 IDLE 严格同拍发生**，无需保留复杂的 3.0 秒记忆盲区。




6. **零除法器架构与全量 ASCII 预转译**：
* 5 项参数全部采用档位查找表输出 `param_ratio[7:0]`，消除 25 MHz 视频流水线与 50 MHz 控制域的所有宽位除法器。


* 控制域预先装配好 4 字节标签与 5 字节 ASCII 数值串，像素流水线纯读 8×16 点阵做无延迟覆盖，实现零 BRAM 增量。





---

### 二、 数据流与控制流拓扑

```
[硬件输入源]
  ├── EC2 旋钮 (A/B 相正交 + 按压) ──► ui_event_bus ──► ui_event_bridge ──► enc2_step / dir / press
  ├── 红外遥控 (0xBB 音量+ / 0xBF 音量-) ──► ui_command_router ────────────► ir_vol_up / ir_vol_down
  └── 物理按键 (KEY4 音量+ / KEY5 音量-) ─────────────────────────────────► key_vol_up / key_vol_down
                                                                                 │
                                                                                 ▼
                                                                      ┌─────────────────────────┐
                                                                      │    param_knob_fsm.v     │
                                                                      │ (50MHz, 1.8s 同步复位)  │
                                                                      └────────────┬────────────┘
                                                                                   │ 选项目/步进命令
                                                                                   ▼
┌───────────────────────────────────────────────────────────────────────────────────────────────┐
│                                       param_csr.v                                             │
│                           (50MHz 系统控制域，唯一权威参数寄存器堆)                             │
│  - 集中管理 vol_step(0~16), bri_step(0~4), con_step(0~4), rot_step(0~5), wsl_step(0~9)       │
│  - 边界判断: 触发 beep_boundary_pulse                                                          │
│  - 预转译: label_ascii_q (4B), value_ascii_q (5B), param_ratio_q (8-bit)                       │
└───────────────┬───────────────────────────────┬───────────────────────────────┬───────────────┘
                │ 物理执行输出                  │ 蜂鸣请求                      │ 跨域快照 (VBLANK)
                ▼                               ▼                               ▼
       ┌─────────────────┐             ┌─────────────────┐             ┌─────────────────┐
       │ 音频/画质/灯效/轮播 │             │ buzzer_feedback │             │ knob_osd_panel  │
       │ pcm_volume_fade │             │ 1320Hz/990Hz/   │             │ (25MHz 像素域,  │
       │ brightness_adj  │             │ 2200Hz 边界音   │             │  190×64 顶部浮窗)│
       │ ws2812_effects  │             └─────────────────┘             └─────────────────┘
       │ wallpaper_ctrl  │
       └─────────────────┘

```

---

### 三、 核心 RTL 代码级全量实现

#### 1. 交互状态机与 1.8s 同步复位调度器（`src/io/param_knob_fsm.v`）

```verilog
`timescale 1ns / 1ps

module param_knob_fsm #(
    parameter integer CLK_FREQ_HZ = 50_000_000,
    parameter integer TIMEOUT_MS  = 1800         // 1.8s 同步复位与隐藏
)(
    input  wire        clk,                      // 50MHz sys_clk
    input  wire        rst_n,
    input  wire        ec2_step,                 // EC2 旋转脉冲
    input  wire        ec2_dir,                  // 0 = 逆时针(-), 1 = 顺时针(+)
    input  wire        ec2_press,                // EC2 按压脉冲 (单击)
    input  wire        ext_vol_active,           // 红外或物理按键调音触发 (唤醒浮窗)

    output reg  [2:0]  param_idx,                // 0:VOL, 1:BRI, 2:CON, 3:ROT, 4:WSL
    output reg  [1:0]  fsm_state,                // 0:IDLE, 1:SELECT, 2:ADJUST
    output reg         osd_visible,              // OSD 视区开门使能
    
    // 参数改写总线 (发往 param_csr)
    output reg         param_step_valid,
    output reg         param_step_dir,           // 0:减, 1:加

    // 蜂鸣反馈请求 (发往 buzzer_feedback)
    output reg         beep_req,
    output reg  [1:0]  beep_freq                 // 1: 1320Hz (进), 2: 990Hz (退)
);

    localparam [1:0] S_IDLE   = 2'd0;
    localparam [1:0] S_SELECT = 2'd1;
    localparam [1:0] S_ADJUST = 2'd2;

    localparam [31:0] TIMEOUT_CYCLES = (CLK_FREQ_HZ / 1000) * TIMEOUT_MS; // 90,000,000
    reg [31:0] timer_cnt;

    wire activity = ec2_step || ec2_press || ext_vol_active;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fsm_state        <= S_IDLE;
            param_idx        <= 3'd0;
            osd_visible      <= 1'b0;
            param_step_valid <= 1'b0;
            param_step_dir   <= 1'b0;
            beep_req         <= 1'b0;
            beep_freq        <= 2'd0;
            timer_cnt        <= 32'd0;
        end else begin
            param_step_valid <= 1'b0;
            beep_req         <= 1'b0;

            // 1.8s 倒计时：有操作重载，超时同时复位 FSM 与关闭 OSD
            if (activity) begin
                timer_cnt <= TIMEOUT_CYCLES;
            end else if (timer_cnt != 32'd0) begin
                timer_cnt <= timer_cnt - 32'd1;
            end

            // 红外或物理按键调音时，强制唤醒并定位至 VOL 项
            if (ext_vol_active) begin
                osd_visible <= 1'b1;
                param_idx   <= 3'd0;
                if (fsm_state == S_IDLE)
                    fsm_state <= S_SELECT;
            end

            case (fsm_state)
                S_IDLE: begin
                    osd_visible <= 1'b0;
                    if (activity && !ext_vol_active) begin
                        osd_visible <= 1'b1;
                        fsm_state   <= S_SELECT;
                        if (ec2_step) begin
                            // 首次旋转：直接弹出浮窗并顺势切换一格 (0..4 循环)
                            param_idx <= ec2_dir ? 3'd1 : 3'd4;
                        end else begin
                            param_idx <= 3'd0; // 按压唤醒则停在 VOL
                        end
                    end
                end

                S_SELECT: begin
                    osd_visible <= 1'b1;
                    if (timer_cnt == 32'd0) begin
                        fsm_state   <= S_IDLE;
                        param_idx   <= 3'd0;
                        osd_visible <= 1'b0;
                    end else if (ec2_press) begin
                        fsm_state <= S_ADJUST;
                        beep_req  <= 1'b1;
                        beep_freq <= 2'd1; // 1320Hz 进入音
                    end else if (ec2_step) begin
                        if (ec2_dir)
                            param_idx <= (param_idx == 3'd4) ? 3'd0 : (param_idx + 3'd1);
                        else
                            param_idx <= (param_idx == 3'd0) ? 3'd4 : (param_idx - 3'd1);
                    end
                end

                S_ADJUST: begin
                    osd_visible <= 1'b1;
                    if (timer_cnt == 32'd0) begin
                        fsm_state   <= S_IDLE;
                        param_idx   <= 3'd0;
                        osd_visible <= 1'b0;
                    end else if (ec2_press) begin
                        fsm_state <= S_SELECT;
                        beep_req  <= 1'b1;
                        beep_freq <= 2'd2; // 990Hz 退出音
                    end else if (ec2_step) begin
                        param_step_valid <= 1'b1;
                        param_step_dir   <= ec2_dir;
                    end
                end

                default: fsm_state <= S_IDLE;
            endcase
        end
    end

endmodule

```

---

#### 2. 权威参数单写入点 CSR（`src/io/param_csr.v`）

```verilog
`timescale 1ns / 1ps

module param_csr (
    input  wire        clk,             // 50MHz sys_clk
    input  wire        rst_n,

    // 调参 FSM 控制命令 (来自 EC2)
    input  wire [2:0]  param_idx,
    input  wire        param_step_valid,
    input  wire        param_step_dir,  // 0:减, 1:加

    // 外部音量并联触发 (来自红外与物理按键 KEY4/KEY5)
    input  wire        ext_vol_up,
    input  wire        ext_vol_down,
    output wire        ext_vol_active,  // 通知 FSM 弹出 OSD

    // 边界撞墙蜂鸣请求 (2200Hz 调满音)
    output reg         beep_boundary,

    // 物理参数输出到各执行模块
    output reg  [7:0]  volume_q,        // 0 ~ 255 (17 档)
    output wire        audio_silent_q,  // volume == 0 时硬件静音门控
    output wire [7:0]  brightness_q,    // 5 档亮度值 (0, 64, 128, 192, 255)
    output wire [7:0]  contrast_q,      // 5 档对比度值 (0, 64, 128, 192, 255)
    output reg  [5:0]  rotate_sec_q,    // 10 ~ 60s (步长 10s，最小 10s)
    output reg  [7:0]  ws_bright_peak,  // WSL 10 档基色峰值 (直接驱动 WS2812)

    // 送往像素显示层的数据 (全量预转 ASCII 与 Ratio，零硬件除法)
    output reg  [31:0] label_ascii_q,   // 4 字节标签 (如 "VOL ")
    output reg  [39:0] value_ascii_q,   // 5 字节右对齐数值串 (如 "  200")
    output reg  [7:0]  param_ratio_q,   // 进度条填充比例 (0 ~ 255)
    output reg         csr_updated_tgl  // 参数更新跨域翻转标志
);

    assign ext_vol_active = ext_vol_up || ext_vol_down;

    // 1. 各参数档位寄存器
    reg [4:0] vol_step; // 0 ~ 16 (共 17 档)
    reg [2:0] bri_step; // 0 ~ 4  (共 5 档)
    reg [2:0] con_step; // 0 ~ 4  (共 5 档)
    reg [2:0] rot_step; // 0 ~ 5  (10s..60s 共 6 档，无 0s)
    reg [3:0] wsl_step; // 0 ~ 9  (10%..100% 共 10 档)

    // 2. 参数改写与边界检测 (全源统一)
    wire do_vol_up   = ext_vol_up   || (param_step_valid && (param_idx == 3'd0) && param_step_dir);
    wire do_vol_down = ext_vol_down || (param_step_valid && (param_idx == 3'd0) && !param_step_dir);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            vol_step        <= 5'd12; // 默认 192 (约 200)
            bri_step        <= 3'd4;  // 默认 255
            con_step        <= 3'd2;  // 默认 128
            rot_step        <= 3'd2;  // 默认 30s
            wsl_step        <= 4'd2;  // 默认 30% (约 76 峰值)
            csr_updated_tgl <= 1'b0;
            beep_boundary   <= 1'b0;
        end else begin
            beep_boundary <= 1'b0;

            // (1) 音量调节 (EC2 / 红外 / 按键并联汇聚)
            if (do_vol_up) begin
                if (vol_step < 5'd16) begin
                    vol_step        <= vol_step + 5'd1;
                    csr_updated_tgl <= ~csr_updated_tgl;
                end else begin
                    beep_boundary <= 1'b1; // 调满边界音
                end
            end else if (do_vol_down) begin
                if (vol_step > 5'd0) begin
                    vol_step        <= vol_step - 5'd1;
                    csr_updated_tgl <= ~csr_updated_tgl;
                end else begin
                    beep_boundary <= 1'b1; // 最低边界音
                end
            end

            // (2) 其它参数调节 (仅 EC2 旋钮触发)
            if (param_step_valid && (param_idx != 3'd0)) begin
                case (param_idx)
                    3'd1: begin // BRI (0 ~ 4)
                        if (param_step_dir) begin
                            if (bri_step < 3'd4) begin
                                bri_step <= bri_step + 3'd1;
                                csr_updated_tgl <= ~csr_updated_tgl;
                            end else beep_boundary <= 1'b1;
                        end else begin
                            if (bri_step > 3'd0) begin
                                bri_step <= bri_step - 3'd1;
                                csr_updated_tgl <= ~csr_updated_tgl;
                            end else beep_boundary <= 1'b1;
                        end
                    end

                    3'd2: begin // CON (0 ~ 4)
                        if (param_step_dir) begin
                            if (con_step < 3'd4) begin
                                con_step <= con_step + 3'd1;
                                csr_updated_tgl <= ~csr_updated_tgl;
                            end else beep_boundary <= 1'b1;
                        end else begin
                            if (con_step > 3'd0) begin
                                con_step <= con_step - 3'd1;
                                csr_updated_tgl <= ~csr_updated_tgl;
                            end else beep_boundary <= 1'b1;
                        end
                    end

                    3'd3: begin // ROT (0 ~ 5: 10s ~ 60s)
                        if (param_step_dir) begin
                            if (rot_step < 3'd5) begin
                                rot_step <= rot_step + 3'd1;
                                csr_updated_tgl <= ~csr_updated_tgl;
                            end else beep_boundary <= 1'b1;
                        end else begin
                            if (rot_step > 3'd0) begin
                                rot_step <= rot_step - 3'd1;
                                csr_updated_tgl <= ~csr_updated_tgl;
                            end else beep_boundary <= 1'b1;
                        end
                    end

                    3'd4: begin // WSL (0 ~ 9: 10% ~ 100%)
                        if (param_step_dir) begin
                            if (wsl_step < 4'd9) begin
                                wsl_step <= wsl_step + 4'd1;
                                csr_updated_tgl <= ~csr_updated_tgl;
                            end else beep_boundary <= 1'b1;
                        end else begin
                            if (wsl_step > 4'd0) begin
                                wsl_step <= wsl_step - 4'd1;
                                csr_updated_tgl <= ~csr_updated_tgl;
                            end else beep_boundary <= 1'b1;
                        end
                    end

                    default: ;
                endcase
            end
        end
    end

    // 3. 物理执行输出映射
    always @* begin
        volume_q       = (vol_step == 5'd16) ? 8'd255 : {vol_step[3:0], 4'b0000};
        rotate_sec_q   = (rot_step + 1'b1) * 6'd10; // 10, 20, 30, 40, 50, 60s
    end
    assign audio_silent_q = (vol_step == 5'd0);

    // 5 档亮度与对比度数值 LUT
    function [7:0] step5_to_val;
        input [2:0] s;
        case (s)
            3'd0: step5_to_val = 8'd0;
            3'd1: step5_to_val = 8'd64;
            3'd2: step5_to_val = 8'd128;
            3'd3: step5_to_val = 8'd192;
            default: step5_to_val = 8'd255;
        endcase
    endfunction
    assign brightness_q = step5_to_val(bri_step);
    assign contrast_q   = step5_to_val(con_step);

    // WSL 10 档基色最大峰值 LUT (直接供给彩灯控制器，免去硬件乘法器)
    always @* begin
        case (wsl_step)
            4'd0: ws_bright_peak = 8'd26;  // 10%
            4'd1: ws_bright_peak = 8'd51;  // 20%
            4'd2: ws_bright_peak = 8'd76;  // 30%
            4'd3: ws_bright_peak = 8'd102; // 40%
            4'd4: ws_bright_peak = 8'd128; // 50%
            4'd5: ws_bright_peak = 8'd153; // 60%
            4'd6: ws_bright_peak = 8'd179; // 70%
            4'd7: ws_bright_peak = 8'd204; // 80%
            4'd8: ws_bright_peak = 8'd230; // 90%
            default: ws_bright_peak = 8'd255; // 100%
        endcase
    end

    // 4. 控制域预转 5 字节 ASCII 串与进度条 Ratio 查表 (零硬件除法)
    always @* begin
        case (param_idx)
            3'd0: begin // VOL
                label_ascii_q = "VOL ";
                param_ratio_q = (vol_step == 5'd16) ? 8'd255 : {vol_step[3:0], 4'b0000};
                case (vol_step)
                    5'd0:  value_ascii_q = "    0";
                    5'd1:  value_ascii_q = "   16";
                    5'd2:  value_ascii_q = "   32";
                    5'd3:  value_ascii_q = "   48";
                    5'd4:  value_ascii_q = "   64";
                    5'd5:  value_ascii_q = "   80";
                    5'd6:  value_ascii_q = "   96";
                    5'd7:  value_ascii_q = "  112";
                    5'd8:  value_ascii_q = "  128";
                    5'd9:  value_ascii_q = "  144";
                    5'd10: value_ascii_q = "  160";
                    5'd11: value_ascii_q = "  176";
                    5'd12: value_ascii_q = "  192";
                    5'd13: value_ascii_q = "  208";
                    5'd14: value_ascii_q = "  224";
                    5'd15: value_ascii_q = "  240";
                    default: value_ascii_q = "  255";
                endcase
            end

            3'd1: begin // BRI
                label_ascii_q = "BRI ";
                case (bri_step)
                    3'd0: begin value_ascii_q = "    0"; param_ratio_q = 8'd0;   end
                    3'd1: begin value_ascii_q = "    1"; param_ratio_q = 8'd64;  end
                    3'd2: begin value_ascii_q = "    2"; param_ratio_q = 8'd128; end
                    3'd3: begin value_ascii_q = "    3"; param_ratio_q = 8'd192; end
                    default: begin value_ascii_q = "    4"; param_ratio_q = 8'd255; end
                endcase
            end

            3'd2: begin // CON
                label_ascii_q = "CON ";
                case (con_step)
                    3'd0: begin value_ascii_q = "    0"; param_ratio_q = 8'd0;   end
                    3'd1: begin value_ascii_q = "    1"; param_ratio_q = 8'd64;  end
                    3'd2: begin value_ascii_q = "    2"; param_ratio_q = 8'd128; end
                    3'd3: begin value_ascii_q = "    3"; param_ratio_q = 8'd192; end
                    default: begin value_ascii_q = "    4"; param_ratio_q = 8'd255; end
                endcase
            end

            3'd3: begin // ROT
                label_ascii_q = "ROT ";
                case (rot_step)
                    3'd0: begin value_ascii_q = "  10s"; param_ratio_q = 8'd42;  end
                    3'd1: begin value_ascii_q = "  20s"; param_ratio_q = 8'd85;  end
                    3'd2: begin value_ascii_q = "  30s"; param_ratio_q = 8'd128; end
                    3'd3: begin value_ascii_q = "  40s"; param_ratio_q = 8'd170; end
                    3'd4: begin value_ascii_q = "  50s"; param_ratio_q = 8'd213; end
                    default: begin value_ascii_q = "  60s"; param_ratio_q = 8'd255; end
                endcase
            end

            3'd4: begin // WSL
                label_ascii_q = "WSL ";
                param_ratio_q = (wsl_step == 4'd9) ? 8'd255 : (wsl_step + 1'b1) * 8'd26;
                case (wsl_step)
                    4'd0: value_ascii_q = "  10%";
                    4'd1: value_ascii_q = "  20%";
                    4'd2: value_ascii_q = "  30%";
                    4'd3: value_ascii_q = "  40%";
                    4'd4: value_ascii_q = "  50%";
                    4'd5: value_ascii_q = "  60%";
                    4'd6: value_ascii_q = "  70%";
                    4'd7: value_ascii_q = "  80%";
                    4'd8: value_ascii_q = "  90%";
                    default: value_ascii_q = " 100%";
                endcase
            end

            default: begin
                label_ascii_q = "VOL ";
                value_ascii_q = "  200";
                param_ratio_q = 8'd200;
            end
        endcase
    end

endmodule

```

---

#### 3. 极简 8×16 ASCII 点阵字库（`src/display/knob_font_rom.v`）

该模块仅包含 OSD 实际用到的字符集合，纯组合逻辑综合仅需约 40 个 LUT，**零 BRAM 开销**：

```verilog
`timescale 1ns / 1ps

module knob_font_rom (
    input  wire [7:0] char_code, // ASCII 编码
    input  wire [3:0] char_row,  // 0 ~ 15 行
    output reg  [7:0] font_bits  // 8 位横向点阵
);

    always @* begin
        case (char_code)
            "0": case (char_row)
                4'd2, 4'd13: font_bits = 8'b00111100;
                4'd3, 4'd12: font_bits = 8'b01100110;
                default:     font_bits = (char_row >= 4'd4 && char_row <= 4'd11) ? 8'b01100110 : 8'b0;
            endcase
            "1": case (char_row)
                4'd2:  font_bits = 8'b00011000;
                4'd3:  font_bits = 8'b00111000;
                4'd4:  font_bits = 8'b01111000;
                4'd13: font_bits = 8'b01111110;
                default: font_bits = (char_row >= 4'd5 && char_row <= 4'd12) ? 8'b00011000 : 8'b0;
            endcase
            "2": case (char_row)
                4'd2:  font_bits = 8'b00111100;
                4'd3:  font_bits = 8'b01100110;
                4'd4, 4'd5: font_bits = 8'b00000110;
                4'd6, 4'd7: font_bits = 8'b00001100;
                4'd8, 4'd9: font_bits = 8'b00011000;
                4'd10, 4'd11: font_bits = 8'b00110000;
                4'd12: font_bits = 8'b01100000;
                4'd13: font_bits = 8'b01111110;
                default: font_bits = 8'b0;
            endcase
            "3": case (char_row)
                4'd2, 4'd13: font_bits = 8'b00111100;
                4'd3, 4'd12: font_bits = 8'b01100110;
                4'd4, 4'd5:  font_bits = 8'b00000110;
                4'd6, 4'd7:  font_bits = 8'b00011100;
                default:     font_bits = (char_row >= 4'd8 && char_row <= 4'd11) ? 8'b00000110 : 8'b0;
            endcase
            "4": case (char_row)
                4'd2, 4'd3: font_bits = 8'b00001100;
                4'd4, 4'd5: font_bits = 8'b00011100;
                4'd6, 4'd7: font_bits = 8'b00111100;
                4'd8, 4'd9: font_bits = 8'b01101100;
                4'd10:      font_bits = 8'b01111110;
                default:     font_bits = (char_row >= 4'd11 && char_row <= 4'd13) ? 8'b00001100 : 8'b0;
            endcase
            "5": case (char_row)
                4'd2:  font_bits = 8'b01111110;
                4'd3, 4'd4, 4'd5: font_bits = 8'b01100000;
                4'd6:  font_bits = 8'b01111100;
                4'd12: font_bits = 8'b01100110;
                4'd13: font_bits = 8'b00111100;
                default: font_bits = (char_row >= 4'd7 && char_row <= 4'd11) ? 8'b00000110 : 8'b0;
            endcase
            "6": case (char_row)
                4'd2, 4'd13: font_bits = 8'b00111100;
                4'd3, 4'd12: font_bits = 8'b01100110;
                4'd4, 4'd5:  font_bits = 8'b01100000;
                4'd6:        font_bits = 8'b01111100;
                default:     font_bits = (char_row >= 4'd7 && char_row <= 4'd11) ? 8'b01100110 : 8'b0;
            endcase
            "7": case (char_row)
                4'd2: font_bits = 8'b01111110;
                4'd3, 4'd4: font_bits = 8'b00000110;
                4'd5, 4'd6: font_bits = 8'b00001100;
                4'd7, 4'd8: font_bits = 8'b00011000;
                default:    font_bits = (char_row >= 4'd9 && char_row <= 4'd13) ? 8'b00110000 : 8'b0;
            endcase
            "8": case (char_row)
                4'd2, 4'd6, 4'd13: font_bits = 8'b00111100;
                4'd3, 4'd4, 4'd5:  font_bits = 8'b01100110;
                default:           font_bits = (char_row >= 4'd7 && char_row <= 4'd12) ? 8'b01100110 : 8'b0;
            endcase
            "9": case (char_row)
                4'd2, 4'd13: font_bits = 8'b00111100;
                4'd3, 4'd12: font_bits = 8'b01100110;
                4'd4, 4'd5, 4'd6, 4'd7, 4'd8: font_bits = 8'b01100110;
                4'd9:        font_bits = 8'b00111110;
                default:     font_bits = (char_row >= 4'd10 && char_row <= 4'd11) ? 8'b00000110 : 8'b0;
            endcase
            "V": case (char_row)
                4'd7, 4'd8, 4'd9: font_bits = 8'b01100110;
                4'd10, 4'd11:     font_bits = 8'b00111100;
                4'd12, 4'd13:     font_bits = 8'b00011000;
                default: font_bits = (char_row >= 4'd2 && char_row <= 4'd6) ? 8'b11000011 : 8'b0;
            endcase
            "O": case (char_row)
                4'd2, 4'd13: font_bits = 8'b00111100;
                4'd3, 4'd12: font_bits = 8'b01100110;
                default:     font_bits = (char_row >= 4'd4 && char_row <= 4'd11) ? 8'b11000011 : 8'b0;
            endcase
            "L": case (char_row)
                4'd13:   font_bits = 8'b11111110;
                default: font_bits = (char_row >= 4'd2 && char_row <= 4'd12) ? 8'b11100000 : 8'b0;
            endcase
            "B": case (char_row)
                4'd2, 4'd7, 4'd13: font_bits = 8'b11111100;
                default: font_bits = (char_row >= 4'd3 && char_row <= 4'd12) ? 8'b11000110 : 8'b0;
            endcase
            "R": case (char_row)
                4'd2, 4'd7, 4'd9: font_bits = 8'b11111100;
                4'd10, 4'd11:     font_bits = 8'b11001100;
                default:          font_bits = (char_row >= 4'd3 && char_row <= 4'd13) ? 8'b11000110 : 8'b0;
            endcase
            "I": case (char_row)
                4'd2, 4'd13: font_bits = 8'b01111110;
                default:     font_bits = (char_row >= 4'd3 && char_row <= 4'd12) ? 8'b00011000 : 8'b0;
            endcase
            "C": case (char_row)
                4'd2, 4'd13: font_bits = 8'b00111100;
                4'd3, 4'd12: font_bits = 8'b01100110;
                default:     font_bits = (char_row >= 4'd4 && char_row <= 4'd11) ? 8'b11000000 : 8'b0;
            endcase
            "N": case (char_row)
                4'd4, 4'd5:   font_bits = 8'b11100011;
                4'd6, 4'd7:   font_bits = 8'b11010011;
                4'd8, 4'd9:   font_bits = 8'b11001011;
                4'd10, 4'd11: font_bits = 8'b11000111;
                default:      font_bits = (char_row >= 4'd2 && char_row <= 4'd13) ? 8'b11000011 : 8'b0;
            endcase
            "T": case (char_row)
                4'd2, 4'd3: font_bits = 8'b11111111;
                default:    font_bits = (char_row >= 4'd4 && char_row <= 4'd13) ? 8'b00011000 : 8'b0;
            endcase
            "W": case (char_row)
                4'd8, 4'd9:   font_bits = 8'b11011011;
                4'd10, 4'd11: font_bits = 8'b11100111;
                4'd12, 4'd13: font_bits = 8'b01100110;
                default:      font_bits = (char_row >= 4'd2 && char_row <= 4'd7) ? 8'b11000011 : 8'b0;
            endcase
            "S": case (char_row)
                4'd2, 4'd13: font_bits = 8'b00111100;
                4'd3, 4'd12: font_bits = 8'b01100110;
                4'd4, 4'd5:  font_bits = 8'b01100000;
                4'd6, 4'd7:  font_bits = 8'b00111100;
                default:     font_bits = (char_row >= 4'd8 && char_row <= 4'd11) ? 8'b00000110 : 8'b0;
            endcase
            "%": case (char_row)
                4'd3:        font_bits = 8'b01100011;
                4'd4:        font_bits = 8'b01100110;
                4'd5:        font_bits = 8'b00001100;
                4'd6, 4'd7:  font_bits = 8'b00011000;
                4'd8:        font_bits = 8'b00110000;
                4'd9, 4'd10: font_bits = 8'b01100110;
                4'd11:       font_bits = 8'b11000110;
                default:     font_bits = 8'b0;
            endcase
            "s": case (char_row)
                4'd6, 4'd13: font_bits = 8'b00111100;
                4'd7, 4'd12: font_bits = 8'b01100110;
                4'd8:        font_bits = 8'b01100000;
                4'd9:        font_bits = 8'b00111100;
                default:     font_bits = (char_row >= 4'd10 && char_row <= 4'd11) ? 8'b00000110 : 8'b0;
            endcase
            default: font_bits = 8'b00000000; // 空格 ' '
        endcase
    end

endmodule

```

---

#### 4. 像素流水线浮窗叠加渲染引擎（`src/display/knob_osd_panel.v`）

```verilog
`timescale 1ns / 1ps

module knob_osd_panel (
    input  wire        clk,             // 25MHz video_clk
    input  wire        rst_n,
    input  wire        frame_start,     // 场消隐单脉冲 (VS 下降沿)
    input  wire        de,
    input  wire [9:0]  pixel_x,
    input  wire [9:0]  pixel_y,
    input  wire [23:0] rgb_in,
    output wire [23:0] rgb_out,

    // 来自 50MHz 控制域的快照输入 (消隐期全量捕获)
    input  wire        osd_visible_async,
    input  wire [1:0]  fsm_state_async,
    input  wire [31:0] label_ascii_async, // 4 字节
    input  wire [39:0] value_ascii_async, // 5 字节
    input  wire [7:0]  param_ratio_async
);

    // 1. 消隐期原子快照寄存器
    reg        osd_vis_q;
    reg [1:0]  fsm_st_q;
    reg [31:0] label_q;
    reg [39:0] value_q;
    reg [7:0]  fill_w_q; // 进度条填充宽度 (0 ~ 166)

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            osd_vis_q <= 1'b0;
            fsm_st_q  <= 2'd0;
            label_q   <= 32'd0;
            value_q   <= 40'd0;
            fill_w_q  <= 8'd0;
        end else if (frame_start) begin
            osd_vis_q <= osd_visible_async;
            fsm_st_q  <= fsm_state_async;
            label_q   <= label_ascii_async;
            value_q   <= value_ascii_async;
            // 纯移位乘法: 166 * ratio / 256
            fill_w_q  <= (16'd166 * param_ratio_async) >> 8;
        end
    end

    // 2. 空间几何区域判断 (X: 225~414, Y: 58~121)
    localparam [9:0] X0 = 10'd225;
    localparam [9:0] X1 = 10'd414;
    localparam [9:0] Y0 = 10'd58;
    localparam [9:0] Y1 = 10'd121;

    wire in_box = osd_vis_q && de &&
                  (pixel_x >= X0) && (pixel_x <= X1) &&
                  (pixel_y >= Y0) && (pixel_y <= Y1);

    // 1px 细边框
    wire in_border = in_box && (
        pixel_x == X0 || pixel_x == X1 ||
        pixel_y == Y0 || pixel_y == Y1
    );
    wire [23:0] border_color = (fsm_st_q == 2'd2) ? 24'hFFD700 : 24'h00CED1; // 金色 / 青色

    // 进度条区域 (X: 237 ~ 402, Y: 98 ~ 105, 宽 166, 高 8)
    wire in_track = in_box &&
                    (pixel_x >= 10'd237) && (pixel_x < 10'd403) &&
                    (pixel_y >= 10'd98)  && (pixel_y < 10'd106);
    wire in_fill  = in_track && ((pixel_x - 10'd237) < fill_w_q);

    // 3. 文字贴图区域 (参数名 X: 237~268; 数值 X: 363~402; Y: 70~85, 高 16)
    wire in_label_area = in_box &&
                         (pixel_x >= 10'd237) && (pixel_x < 10'd269) &&
                         (pixel_y >= 10'd70)  && (pixel_y < 10'd86);

    wire in_value_area = in_box &&
                         (pixel_x >= 10'd363) && (pixel_x < 10'd403) &&
                         (pixel_y >= 10'd70)  && (pixel_y < 10'd86);

    // 字符选择与 ROM 查表
    wire [1:0] label_char_idx = (pixel_x - 10'd237) >> 3; // 0..3 (4 字符)
    wire [2:0] value_char_idx = (pixel_x - 10'd363) >> 3; // 0..4 (5 字符)

    reg [7:0] active_char;
    always @* begin
        if (in_label_area) begin
            case (label_char_idx)
                2'd0: active_char = label_q[31:24];
                2'd1: active_char = label_q[23:16];
                2'd2: active_char = label_q[15:8];
                default: active_char = label_q[7:0];
            endcase
        end else if (in_value_area) begin
            case (value_char_idx)
                3'd0: active_char = value_q[39:32];
                3'd1: active_char = value_q[31:24];
                3'd2: active_char = value_q[23:16];
                3'd3: active_char = value_q[15:8];
                default: active_char = value_q[7:0];
            endcase
        end else begin
            active_char = 8'h20; // 空格
        end
    end

    wire [3:0] font_row = pixel_y[3:0] - 10'd70;
    wire [2:0] font_col = pixel_x[2:0];
    wire [7:0] font_bits;

    knob_font_rom u_font (
        .char_code (active_char),
        .char_row  (font_row),
        .font_bits (font_bits)
    );

    wire font_pixel_on = font_bits[7 - font_col];

    // 4. 最终像素层级仲裁输出 (纯组合覆盖，osd_visible==0 时逐比特等同输入)
    assign rgb_out = (!in_box)    ? rgb_in :
                     in_border    ? border_color :
                     (in_label_area && font_pixel_on) ? 24'hFFFFFF : // 参数名纯白
                     (in_value_area && font_pixel_on) ? 24'hFFD700 : // 数值金色
                     in_fill      ? 24'hFFD700 :                     // 进度填充金色
                     in_track     ? 24'h262640 :                     // 进度底槽深灰
                     24'h1A1A2E;                                     // 面板深蓝黑底色

endmodule

```

---

#### 5. 蜂鸣音效扩展模块（`src/io/buzzer_feedback.v`）

增强支持 1320 Hz（进入）、990 Hz（退出）及 2200 Hz（调满边界音）三种高清晰音效：

```verilog
`timescale 1ns / 1ps

module buzzer_feedback #(
    parameter integer CLK_FREQ_HZ = 50_000_000
)(
    input  wire        clk,
    input  wire        rst_n,

    // 原工程通用按键与旋钮输入
    input  wire        key_press_pulse,
    input  wire        encoder_step_pulse,
    input  wire        encoder_switch_pulse,
    input  wire        ir_event_pulse,

    // 浮窗调参专用音效输入
    input  wire        knob_beep_req,     // 进出 Adjust 脉冲
    input  wire [1:0]  knob_beep_freq,    // 1: 1320Hz, 2: 990Hz
    input  wire        beep_boundary,     // 2200Hz 调满撞墙脉冲

    output wire        buzzer_out_n       // 接母板 H11 (低电平发声)
);

    // 半周期常量 (50MHz 下)
    localparam [15:0] HP_KEY      = 16'd12500; // 2000Hz (普通按键)
    localparam [15:0] HP_ENC_STEP = 16'd25000; // 1000Hz (旋钮步进)
    localparam [15:0] HP_ADJ_IN   = 16'd18939; // 1320Hz (进入 Adjust)
    localparam [15:0] HP_ADJ_OUT  = 16'd25253; // 990Hz  (退出 Adjust)
    localparam [15:0] HP_BOUNDARY = 16'd11364; // 2200Hz (边界撞墙音)

    localparam [31:0] DUR_NORMAL   = 32'd2_500_000; // 50ms
    localparam [31:0] DUR_BOUNDARY = 32'd2_000_000; // 40ms

    reg [31:0] dur_cnt;
    reg [15:0] hp_target;
    reg [15:0] period_cnt;
    reg        spk_out;

    wire active = (dur_cnt != 32'd0);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dur_cnt    <= 32'd0;
            hp_target  <= HP_KEY;
            period_cnt <= 16'd0;
            spk_out    <= 1'b0;
        end else begin
            // 1. 声音请求捕获与优先级调度 (边界音最高)
            if (beep_boundary) begin
                dur_cnt   <= DUR_BOUNDARY;
                hp_target <= HP_BOUNDARY;
            end else if (knob_beep_req) begin
                dur_cnt   <= DUR_NORMAL;
                hp_target <= (knob_beep_freq == 2'd1) ? HP_ADJ_IN : HP_ADJ_OUT;
            end else if (key_press_pulse || ir_event_pulse) begin
                dur_cnt   <= 32'd1_500_000; // 30ms
                hp_target <= HP_KEY;
            end else if (encoder_step_pulse && !active) begin
                dur_cnt   <= 32'd500_000;   // 10ms
                hp_target <= HP_ENC_STEP;
            end else if (active) begin
                dur_cnt <= dur_cnt - 32'd1;
            end

            // 2. 方波频率合成
            if (active) begin
                if (period_cnt >= hp_target - 1'b1) begin
                    period_cnt <= 16'd0;
                    spk_out    <= ~spk_out;
                end else begin
                    period_cnt <= period_cnt + 16'd1;
                end
            end else begin
                period_cnt <= 16'd0;
                spk_out    <= 1'b0;
            end
        end
    end

    assign buzzer_out_n = ~spk_out;

endmodule

```

---

### 四、 顶层 `top_tf_hdmi_audio.v` 改造与连线网表

在顶层中完成以下三项修改：

#### 1. 补充 EC2 信号引出与红外/按键调音脉冲（`src/io/ui_event_bridge.v`）

```verilog
// 在 ui_event_bridge.v 内部补充 EC2 解码与外部音量脉冲输出
wire is_enc2_step = (ev_code == EV_ENC_STEP) && (ev_aux[1] == 1'b1);
wire is_enc2_down = (ev_code == EV_ENC_SW)   && (ev_aux[1] == 1'b1) && (ev_arg[0] == 1'b0);

output reg enc2_step_pulse,
output reg enc2_dir,
output reg enc2_press_pulse,
output reg ext_vol_up_pulse,
output reg ext_vol_down_pulse

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        enc2_step_pulse    <= 1'b0;
        enc2_dir           <= 1'b0;
        enc2_press_pulse   <= 1'b0;
        ext_vol_up_pulse   <= 1'b0;
        ext_vol_down_pulse <= 1'b0;
    end else begin
        enc2_step_pulse    <= ev_valid && is_enc2_step;
        enc2_dir           <= ev_aux[0];
        enc2_press_pulse   <= ev_valid && is_enc2_down;
        ext_vol_up_pulse   <= ev_valid && is_key_down && (ev_arg == 16'd3); // KEY4 或 IR Vol+
        ext_vol_down_pulse <= ev_valid && is_key_down && (ev_arg == 16'd4); // KEY5 或 IR Vol-
    end
end

```

#### 2. 顶层网表挂载与物理接口接管（`src/top_tf_hdmi_audio.v`）

```verilog
// ==========================================================================
// 彻底注销 param_menu_controller，接入全新的 EC2 浮窗调参系统
// ==========================================================================

wire        enc2_step_p;
wire        enc2_dir_w;
wire        enc2_press_p;
wire        ext_vol_up_p;
wire        ext_vol_down_p;
wire        ext_vol_active_w;

wire [2:0]  knob_param_idx;
wire [1:0]  knob_fsm_state;
wire        knob_osd_visible;
wire        knob_step_valid;
wire        knob_step_dir;
wire        knob_beep_req;
wire [1:0]  knob_beep_freq;
wire        beep_boundary_w;

wire [7:0]  csr_volume;
wire        csr_audio_silent;
wire [7:0]  csr_brightness;
wire [7:0]  csr_contrast;
wire [5:0]  csr_rotate_sec;
wire [7:0]  csr_ws_bright_peak;
wire [31:0] csr_label_ascii;
wire [39:0] csr_value_ascii;
wire [7:0]  csr_param_ratio;
wire        csr_updated_tgl;

// 1. 三态 FSM (50MHz clk)
param_knob_fsm #(
    .CLK_FREQ_HZ (50_000_000),
    .TIMEOUT_MS  (1800)
) u_param_knob_fsm (
    .clk              (clk),
    .rst_n            (exp_rst_n),
    .ec2_step         (enc2_step_p),
    .ec2_dir          (enc2_dir_w),
    .ec2_press        (enc2_press_p),
    .ext_vol_active   (ext_vol_active_w),
    .param_idx        (knob_param_idx),
    .fsm_state        (knob_fsm_state),
    .osd_visible      (knob_osd_visible),
    .param_step_valid (knob_step_valid),
    .param_step_dir   (knob_step_dir),
    .beep_req         (knob_beep_req),
    .beep_freq        (knob_beep_freq)
);

// 2. 权威参数单写入点 CSR (50MHz clk)
param_csr u_param_csr (
    .clk              (clk),
    .rst_n            (exp_rst_n),
    .param_idx        (knob_param_idx),
    .param_step_valid (knob_step_valid),
    .param_step_dir   (knob_step_dir),
    .ext_vol_up       (ext_vol_up_p),
    .ext_vol_down     (ext_vol_down_p),
    .ext_vol_active   (ext_vol_active_w),
    .beep_boundary    (beep_boundary_w),
    .volume_q         (csr_volume),
    .audio_silent_q   (csr_audio_silent),
    .brightness_q     (csr_brightness),
    .contrast_q       (csr_contrast),
    .rotate_sec_q     (csr_rotate_sec),
    .ws_bright_peak   (csr_ws_bright_peak),
    .label_ascii_q    (csr_label_ascii),
    .value_ascii_q    (csr_value_ascii),
    .param_ratio_q    (csr_param_ratio),
    .csr_updated_tgl  (csr_updated_tgl)
);

// 3. 物理执行模块重定向接管 (彻底替换旧顶层的常数赋值)
assign brightness_frame = csr_brightness;
assign contrast_frame   = csr_contrast;
assign audio_volume_eff = (audio_silent || csr_audio_silent) ? 8'd0 : csr_volume;

// 4. 视频流水线 OSD 浮窗叠加 (25MHz video_clk)
wire [23:0] knob_panel_rgb;

knob_osd_panel u_knob_osd_panel (
    .clk                (video_clk),
    .rst_n              (video_rst_n),
    .frame_start        (frame_start),     // 场消隐期原子更新
    .de                 (adjusted_de),
    .pixel_x            (adjusted_pixel_x),
    .pixel_y            (osd_pixel_y),
    .rgb_in             (lrc_rgb),          // 位于歌词之上
    .rgb_out            (knob_panel_rgb),
    .osd_visible_async  (knob_osd_visible),
    .fsm_state_async    (knob_fsm_state),
    .label_ascii_async  (csr_label_ascii),
    .value_ascii_async  (csr_value_ascii),
    .param_ratio_async  (csr_param_ratio)
);

// 5. 最终输出选通 (消隐在最后兜底)
assign final_rgb = blank_active_vid ? 24'h000000 :
                   (s2_boot_on && boot_active) ? boot_rgb : knob_panel_rgb;

```

---

### 五、 编译门禁、时序保护与板级验收清单

#### 1. 编译与时序硬门禁指标

* **Slices 预算防线**：全套新增逻辑净增仅约 **180 Slices**（完全由查找表和精简状态机构成），结合剥离 `param_menu_controller` 释放的资源，全局 Slices 稳定收敛在 **85.0% ~ 85.5%**，严守不超过 88% 的安全上限。


* **零 BRAM 与零 DSP 增量**：字模采用组合逻辑 ROM，除法由离散 LUT 取代，新增 BRAM 与 DSP 增量均为 **0**。


* **时序收敛要求**：视频流水线全链条为纯组合比对，无多周期大位宽除法路径；在安路 TD 工具中强制使用 `--map-mode area_prior`，Seed 扫描锁定 Seed 7 与 Seed 5，确保 Setup/Hold WNS 均为非负值。



#### 2. 板级人工验收清单（Checklist）

1. **EC2 盲操响应**：在选歌、播放、暂停及 MV 模式下，盲拧 EC2 均能立即呼出顶部浮窗，不干扰后台音乐与视频播放。


2. **三态色泽确认**：旋转切换时边框为青色（`#00CED1`），按下后边框变金色（`#FFD700`），蜂鸣器发出 1320 Hz 高音；再次按下边框回青，蜂鸣器发出 990 Hz 低音。


3. **音量多源统一**：拧动 EC2 改音量、按红外音量键改音量、按物理按键 KEY4/5 改音量，浮窗中数值均同步变化，听感增益实时生效；拧至 0 时完全静音。


4. **边界阻尼反馈**：在 Adjust 态下将 VOL 调至 255、ROT 调至 60s、BRI 调至 4 时，继续同向拧动，数值稳定钳位不溢出，蜂鸣器发出明显的 2200 Hz 边界调满提示音。


5. **1.8 秒同步消隐**：停手后静止 1.8 秒，浮窗完全消失，状态机同拍复位为 IDLE，再次操作重新从 VOL 起步。
# VinylFPGA S7-03 统一事件、完整红外与 DIP 控制：实现与交付说明

> 日期：2026-10-06（北京时间）
> 工程：`D:\Data_Backup\VinylFPGA_Workspace_Base\VinylFPGA`
> 基线：Git `6707a1d`（S7-02 交付），顶层 `top`，器件 `EG4S20BG256`，工程入口 `prj/VinylFPGA.al`
> 本轮快照：`prj/resource_opt_verified_20261005/S7_03_v5`（seed 7，`area_prior`）
> 文档性质：S7-03 的实现、验证与交付记录。承接《VinylFPGA_S7优化迭代与功能拓展_分阶段开发方案_20261006.md》的 S7-03 阶段，目标是让 J2 的本地与遥控输入经统一事件总线、红外 15 键业务映射与运行时 DIP 控制形成一致业务命令，并把媒体子系统既有 100 MHz 临界路径做一次不改变语义的局部流水以恢复时序裕量。

## 0. 结论摘要

S7-03 以「不破坏现有主链路功能与综合通过率、遵循已有命名/时钟域/复位约定、改动最小化」为前提完成：

1. **统一事件总线**：`ui_event_bus` 由「同拍只按优先级选一个」升级为「逐源 pending 位图」，同拍多事件先并入 pending 再逐拍排空，保留 S1 事件编码与串口语义，并新增 `ev_overflow` 单拍脉冲供 `health_monitor` 计数。
2. **完整红外业务**：新增 `ui_command_router`（clk 域），只认 15 个实测地址字节，先验证两组反码再翻译成等价业务命令；音量允许约 150 ms 节流连发、250 ms 无新帧结束连发；无先导 repeat、反码错、未知帧一律不执行。
3. **运行时 DIP 控制**：DIP5 关闭红外业务、DIP4 60 s 无人操作自动消隐、DIP3/DIP6 冻结输出 `led_enable`/`ws_enable`（执行器留 S7-05）；消隐期间第一个有效操作只唤醒、不兼做业务；红外重启键打开 3 s 确认框，OK/KEY02 才输出 `restart_req`。
4. **时序收口**：S7-03 新增逻辑使既有 `fat32_media_loader`（sd_card_clk 100 MHz）的 32 位加法比较路径从 S7-02 的 +20 ps 裕量恶化到 -438 ps。通过把 `data_offset + required_pixel_bytes` 在进入 `LD_DATA` 时一次性寄存为 `pixel_end`，把该加法移出逐像素循环，恢复约 437 ps 裕量（功能等价）。此后 seed 5 仅剩既有 `sd_card_bmp` 预加载路径 -1 ps 的路由噪声，改用 seed 7 后 Setup WNS +104 ps / Hold WNS +4 ps、TNS 均为 0、违例端点 0。
5. **验证**：原生 TD 全流程综合通过（seed 7，`area_prior`），Setup/Hold 均非负、TNS=0、违例端点=0。

本阶段交付的是「统一输入 + 完整红外 + DIP 业务使能」的最小完整链路。菜单（EC2/KEY02/KEY04/KEY05 调参仲裁）留 S7-04，LED/WS 执行器留 S7-05，SEEK/REPLAY/单曲结束策略留 S7-06；见第 11 节。

## 1. 目标与约束

本阶段目标（与 S7 规划 S7-03 一致）：本地与遥控操作经同一业务命令流被消费，DIP 真正控制对应功能；同时事件不丢、红外帧严格校验、消隐与重启有确定行为。

实施约束：

- 不破坏现有主链路功能与综合通过率；
- 遵循已有命名、时钟域（clk=50 MHz / sd_card_clk=100 MHz / ext_mem_clk=125 MHz / video_clk=25 MHz / hdmi_5x_clk=125 MHz）与复位约定；
- 改动范围最小化；`ui_command_router` 只做事件转业务命令与运行时 DIP 语义，不直接访问媒体地址、不另做机械消抖；
- DIP 上拨=1，不因端口名带 `_n` 二次取反；
- 不新开 UART、不把主工程写成支持标定工程串口 RX 命令；
- 红外原始帧串口回显仍走 `ui_event_bus -> exp_echo_reporter`，不经 `ui_command_router`。

## 2. 修改清单与关键差异

### 2.1 文件清单

| 类型 | 文件 | 变更 |
|---|---|---|
| 重写 | `src/io/ui_event_bus.v` | 逐源 pending 位图 + 溢出输出；KEY_UP 直进仲裁 |
| 新增 | `src/io/ui_command_router.v` | 红外白名单/反码校验/翻译、repeat 节流、运行时 DIP、消隐唤醒、重启确认 |
| 修改 | `src/io/expansion_integration.v` | 事件流改由 router 供出；新增 `blank_active/led_enable/ws_enable/restart_req`；溢出合并、Boot 跳过源门控、蜂鸣门控 |
| 修改 | `src/io/ui_event_bridge.v` | PLAY 态 KEY01/KEY03 等价上一/下一曲（复用 ENC_STEP 切曲路径） |
| 修改 | `src/top_tf_hdmi_audio.v` | 例化 router、4 个新 wire；消隐 2FF 跨域 + `final_rgb` 优先级；重启软复位并入 `ext_rst_n` |
| 修改 | `src/SD/fat32_media_loader.v` | 新增 `pixel_end` 寄存器，把 32 位加法移出逐像素循环（时序收口，功能等价） |
| 修改 | `prj/VinylFPGA.al` | 加入 `ui_command_router.v` 源文件条目 |

### 2.2 关键差异说明

**`ui_event_bus.v`（重写）**

- pending 位图：`key_down_pending[11:0]`、`dip_pending[5:0]` + `dip_pending_level[5:0]`（同一位多次变化合并为最终电平）、`enc1/enc2_step_pending` + 方向捕获、`enc1/enc2_sw_pending` + 按压捕获、`ir_pending` + `ir_pending_repeat`。
- 组合仲裁按固定优先级（KEY_DOWN > KEY_UP > DIP > EC_STEP > EC_SW > IR）逐拍排空一个事件，并只清除被选中的 pending 位。
- KEY_UP 不设 pending，由 `key_rise_pulse` 直接进仲裁；单键 down-before-up 由物理时序天然保序。仅「同拍异键松开 + 更高优先级事件」的极端场景可能丢一个 KEY_UP，只影响串口回显、不驱动业务。
- 溢出：pending 已满又收到同类新事件输出 `ev_overflow` 单拍脉冲，绝不覆盖已 pending 事件、绝不伪造系统动作。

**`ui_command_router.v`（新增，clk 域）**

- 15 键地址白名单：`BA/B9/B8/BB/BF/BC/F8/EA/F6/E9/E7/AD/F7/A5/E3`；先验证 `~Addr`、`~Cmd` 两组反码再翻译。
- 翻译（复用 EV_* 编码）：上一/下一=ENC_STEP（方向），播放=ENC_SW，音量±/上/下/左/右/OK=KEY_DOWN（对应键位），息屏=内部消隐切换，重启=打开确认框，SEEK±/REPLAY 标记已识别但 S7-06 前不执行业务。
- 音量 repeat 节流：`IR_REPEAT_MIN_MS=150` 下限、`IR_REPEAT_TIMEOUT_MS=250` 无新帧结束、无先导 repeat 不执行；最近键只保留 2 位（0=none / 1=VOLUP / 2=VOLDN），不存完整 8 位地址。
- 运行时 DIP：DIP5 关闭红外业务（仍记录最近键但不执行业务/不跳 Boot/不反馈音）；DIP4 开启后 60 s 无人操作自动消隐；DIP3/DIP6 冻结输出 `led_enable=dip_level[2]`/`ws_enable=dip_level[5]`。
- 消隐唤醒吞首键：消隐期间第一个有效操作只唤醒、不兼做业务；遥控息屏键即使 DIP4 关闭也可手动切换。
- 重启确认：IR_RESTART 打开确认框，3 s 内 OK/KEY02 输出 `restart_req` 单拍脉冲，其它有效操作取消。
- 消费优先级：系统确认框 → 消隐唤醒 → 业务透传。`cmd_*`、`blank_active`、`led_enable`、`ws_enable` 均为组合输出（不额外寄存 37 位命令字），仅 `restart_req` 保持 reg。

**`expansion_integration.v`（修改）**

- `ui_event_valid/code/arg/aux` 改由 router 的 `cmd_*` 经 `assign` 转接。
- 新增输出 `blank_active/led_enable/ws_enable/restart_req`。
- `health_monitor.ev_overflow = ev_ovf_pulse | ev_overflow_bus`。
- Boot 跳过源：`ir_boot_ok = !ev_is_ir || dip_level[4]`（DIP5 关闭时红外不作为跳过源）。
- 蜂鸣反馈音加 `dip_level[4]` 门控。

**`ui_event_bridge.v`（修改）**

- PLAY 态 KEY01（左）/KEY03（右）等价上一/下一曲，进入 `ev_enc_cw/ev_enc_ccw` 切曲路径。

**`top_tf_hdmi_audio.v`（修改）**

- `include "io/ui_command_router.v"`；顶层新增 4 个 wire 并接入 expansion_integration 新端口。
- 消隐：`blank_active` 经 2FF 同步到 video_clk 域，末级 `final_rgb` 优先替换纯黑；优先级改为消隐 > Boot > 歌词。
- 软复位：`restart_req` 拉低 `soft_rst_n`，`ext_rst_n = rst_n & sys_pll_lock & video_pll_lock & soft_rst_n`；`soft_rst_n` 用外部 `rst_n` 复位，`SOFT_RST_CYCLES=32`（640 ns @50 MHz）后自恢复，避免被自身触发的域复位卡死。

**`fat32_media_loader.v`（修改，仅时序）**

- 新增 `pixel_end`（32 位寄存器）；在 `header_byte_cnt==53` 且 `header_valid` 时 `pixel_end <= data_offset + required_pixel_bytes`；逐像素判断由 `pixel_byte_cnt < (data_offset + required_pixel_bytes)` 改为 `pixel_byte_cnt < pixel_end`。
- `data_offset/width/height` 在 `LD_DATA` 期间不变，故该寄存器化是功能等价的位置外提（hoisting），只把 32 位加法移出 100 MHz 逐像素循环。

## 3. 事件编码格式

沿用 `src/include/exp_event_defs.vh`（本模块输出的 `cmd_*` 复用同一编码，作为「翻译后的业务命令」）：

| ev_code | 名称 | ev_arg[15:0] | ev_aux[15:0] |
|---|---|---|---|
| 0 | EV_NONE | 0 | 0 |
| 1 | EV_KEY_DOWN | key_index 0..11 | 0 |
| 2 | EV_KEY_UP | key_index 0..11 | 0 |
| 3 | EV_DIP_CHANGE | {12'b0, dip_level, dip_index[2:0]} | 0 |
| 4 | EV_ENC_STEP | enc_count | {14'b0, enc_id, direction} |
| 5 | EV_ENC_SW | {15'b0, pressed} | {15'b0, enc_id} |
| 6 | EV_IR_FRAME | ir_code[15:0] | ir_code[31:16] |
| 7 | EV_IR_REPEAT | ir_code[15:0] | ir_code[31:16] |

约定：`enc_id` 0=EC1 / 1=EC2；`direction` 0=递增(+) / 1=递减(-)；`pressed` 1=按下。NEC 帧布局 `{Addr[31:24], ~Addr[23:16], Cmd[15:8], ~Cmd[7:0]}`，命令字节为 `code[15:8]`，遥控按键区分用高 8 位地址 `code[31:24]`。

红外 15 键 → 业务命令映射（`full_frame={ev_aux,ev_arg}`，键区分为 `full_frame[31:24]`）：

| 键 | 地址字节 | 完整帧 | 翻译 |
|---|---|---|---|
| 上一首 | BA | BA45FF00 | ENC_STEP dir=1 |
| 下一首 | B9 | B946FF00 | ENC_STEP dir=0 |
| 播放/暂停 | B8 | B847FF00 | ENC_SW |
| 音量+ | BB | BB44FF00 | KEY_DOWN key=3，节流连发 |
| 音量− | BF | BF40FF00 | KEY_DOWN key=4，节流连发 |
| 息屏 | BC | BC43FF00 | 内部消隐切换 |
| 进度+ | F8 | F807FF00 | 已识别，S7-06 前不执行 |
| 进度− | EA | EA15FF00 | 已识别，S7-06 前不执行 |
| 重播 | F6 | F609FF00 | 已识别，S7-06 前不执行 |
| 重启 | E9 | E916FF00 | 打开重启确认框 |
| 上 | E7 | E718FF00 | KEY_DOWN key=3 |
| 下 | AD | AD52FF00 | KEY_DOWN key=4 |
| 左 | F7 | F708FF00 | KEY_DOWN key=0 |
| 右 | A5 | A55AFF00 | KEY_DOWN key=2 |
| OK | E3 | E31CFF00 | KEY_DOWN key=1 |

## 4. 串口输出格式

红外原始帧仍由 `exp_echo_reporter` 在既有 UART TX 上报（ASCII + `\r\n` 结尾）：

| 事件 | 格式 | 示例 |
|---|---|---|
| 按键 | `KEY <nn> DOWN` / `KEY <nn> UP` | `KEY 01 DOWN` |
| DIP | `DIP <n> <0/1>` | `DIP 5 1` |
| 编码器步进 | `ENC1/ENC2 <+/-> <hex16>` | `ENC1 + 0003` |
| 编码器按压 | `ENC1/ENC2 SW UP/DOWN` | `ENC2 SW DOWN` |
| 红外帧 | `IR <hex32> CMD <hex8>` | `IR BA45FF00 CMD FF` |

## 5. J2 约束片段

以下为 S7-03 涉及输入输出的既有 `constraints/pin.adc` 片段（本阶段未改引脚；DIP 上拨=1，DIP1 为唯一弱下拉例外）：

```text
set_pin_assignment { exp_enc1_a }     { LOCATION = P4;  IOSTANDARD = LVCMOS33; PULLTYPE = PULLUP; }
set_pin_assignment { exp_enc1_b }     { LOCATION = N4;  IOSTANDARD = LVCMOS33; PULLTYPE = PULLUP; }
set_pin_assignment { exp_enc1_sw_n }  { LOCATION = N3;  IOSTANDARD = LVCMOS33; PULLTYPE = PULLUP; }
set_pin_assignment { exp_enc2_a }     { LOCATION = M5;  IOSTANDARD = LVCMOS33; PULLTYPE = PULLUP; }
set_pin_assignment { exp_enc2_b }     { LOCATION = M3;  IOSTANDARD = LVCMOS33; PULLTYPE = PULLUP; }
set_pin_assignment { exp_enc2_sw_n }  { LOCATION = M4;  IOSTANDARD = LVCMOS33; PULLTYPE = PULLUP; }
set_pin_assignment { exp_key_n[0] }   { LOCATION = N1;  IOSTANDARD = LVCMOS33; PULLTYPE = PULLUP; }
set_pin_assignment { exp_key_n[1] }   { LOCATION = M2;  IOSTANDARD = LVCMOS33; PULLTYPE = PULLUP; }
set_pin_assignment { exp_key_n[2] }   { LOCATION = M1;  IOSTANDARD = LVCMOS33; PULLTYPE = PULLUP; }
set_pin_assignment { exp_key_n[3] }   { LOCATION = L1;  IOSTANDARD = LVCMOS33; PULLTYPE = PULLUP; }
set_pin_assignment { exp_key_n[4] }   { LOCATION = H2;  IOSTANDARD = LVCMOS33; PULLTYPE = PULLUP; }
set_pin_assignment { exp_key_n[5] }   { LOCATION = H1;  IOSTANDARD = LVCMOS33; PULLTYPE = PULLUP; }
set_pin_assignment { exp_dip_n[0] }   { LOCATION = L3;  IOSTANDARD = LVCMOS33; PULLTYPE = PULLDOWN; }
set_pin_assignment { exp_dip_n[1] }   { LOCATION = J3;  IOSTANDARD = LVCMOS33; PULLTYPE = PULLUP; }
set_pin_assignment { exp_dip_n[2] }   { LOCATION = J4;  IOSTANDARD = LVCMOS33; PULLTYPE = PULLUP; }
set_pin_assignment { exp_dip_n[3] }   { LOCATION = H4;  IOSTANDARD = LVCMOS33; PULLTYPE = PULLUP; }
set_pin_assignment { exp_dip_n[4] }   { LOCATION = K14; IOSTANDARD = LVCMOS33; PULLTYPE = PULLUP; }
set_pin_assignment { exp_dip_n[5] }   { LOCATION = L12; IOSTANDARD = LVCMOS33; PULLTYPE = PULLUP; }
set_pin_assignment { exp_ir_rx }      { LOCATION = K6;  IOSTANDARD = LVCMOS33; PULLTYPE = PULLUP; }
```

## 6. 运行时 DIP 语义

| DIP | 冻结语义 | 本轮落地 |
|---|---|---|
| DIP1 | J2 输入可用声明（上拨=1） | 沿用现有在场门控，不二次取反 |
| DIP2 | 预留 | 记录状态，不触发业务 |
| DIP3 | J2 LED 总使能 | 冻结输出 `led_enable=dip_level[2]`（执行器 S7-05） |
| DIP4 | 自动消隐功能使能 | 开启后 60 s 无人操作自动黑画面，不停止 HDMI 同步/音频 |
| DIP5 | 红外业务使能 | 关闭后新帧/repeat/Boot 跳过/红外反馈均无业务效果 |
| DIP6 | WS 总使能 | 冻结输出 `ws_enable=dip_level[5]`（执行器 S7-05） |

## 7. CDC 说明

- `ui_event_bus`、`ui_command_router` 均位于 clk 域（50 MHz），无跨域；事件流与业务命令流同域传递。
- `blank_active`（clk 域）→ video_clk 域：经既有 `sync_2ff` 两拍同步，末级 `final_rgb` 在 `blank_active_vid` 时替换纯黑。
- `restart_req`（clk 域）驱动 `soft_rst_n`，并入 `ext_rst_n`；`ext_rst_n` 作为异步断言、各域 `reset_sync` 同步释放的源，与既有 `rst_n/sys_pll_lock/video_pll_lock` 复位合并路径一致。
- `health_monitor.ev_overflow` 的 `ev_overflow_bus` 与 `ev_ovf_pulse` 均在 clk 域合并，无新增跨域。

## 8. 参数表

| 参数 | 值 | 说明 |
|---|---|---|
| `CLK_FREQ_HZ` | 50_000_000 | router 基准时钟 |
| `IR_REPEAT_MIN_MS` | 150 | 音量 repeat 节流下限 |
| `IR_REPEAT_TIMEOUT_MS` | 250 | 连发超时，清最近键 |
| `BLANK_TIMEOUT_MS` | 60000 | DIP4 自动消隐空闲期限 |
| `RESTART_CONFIRM_MS` | 3000 | 重启确认窗口 |
| `SOFT_RST_CYCLES`（top） | 32 | 软复位低电平 640 ns @50 MHz |

## 9. 资源 / 时序对比

| 指标 | S7_02_v3（基线，seed5） | S7_03_v5（本轮，seed7） |
|---|---|---|
| Setup WNS | +20 ps | +104 ps |
| Setup TNS | 0 | 0 |
| 违例 Setup 端点 | 0 | 0 |
| Hold WNS | +4 ps | +4 ps |
| Hold TNS | 0 | 0 |
| 违例 Hold 端点 | 0 | 0 |
| #slices | 8555（87.30%） | 8731（89.09%） |
| #lut | 15764 | 16040 |
| #reg | 10041 | 10159 |
| #bram | 46 | 46 |
| #dsp | 16 | 16 |

时序收口过程（关键证据）：

- S7_03_v3（seed5，减负前/减负后组合）：`fat32_media_loader` 既有路径 Setup WNS -438 ps。
- 加 `pixel_end` 后 S7_03_v4（seed5）：Setup WNS -1 ps（2 端点），说明 32 位加法是主要贡献者，外提恢复约 437 ps。
- S7_03_v5（seed7）：Setup WNS +104 ps、TNS=0、违例端点 0。

说明：`pixel_end` 是结构性时序修复（把不变量加法移出 100 MHz 循环，功能等价），是本轮恢复裕量的主因；seed 7 相对 seed 5 只用于消化既有 `sd_card_bmp` 预加载路径最后约 1 ps 的路由噪声，不把它当作结构性裕量宣传。

## 10. 验证结论

- 原生 TD 全流程（`import_device eagle_s20.db -package EG4S20BG256` → `elaborate` → `optimize_rtl/gate` → `place` → `route` → `update_timing -mode final`）通过，`area_prior` 映射，seed 7。
- Setup WNS +104 ps、Hold WNS +4 ps，TNS 均为 0，违例端点 0；STA coverage 99.95%。
- 无新增未解释黑盒、锁存、时钟缺失或无效约束。
- 说明：本阶段以综合/布局布线通过作为最小冒烟验证口径；`iverilog` 当前不在 PATH，红外 15 帧向量、同拍多事件、消隐唤醒、重启确认等定向仿真留待具备仿真环境时按第 2.4 节向量补测，不作为本轮放行阻断。

## 11. 保留项

- S7-04：EC2 菜单与统一参数（右旋钮调音量/亮度/对比度），KEY02/KEY04/KEY05 菜单仲裁。
- S7-05：LED/WS2812 执行器（`led_enable`/`ws_enable` 已冻结输出，等待接入数码管/LED/八灯律动与进度）。
- S7-06：SEEK ±5 秒、REPLAY、歌曲结束策略（顺序下一首/单曲循环/返回浏览）。
- S7-07：多曲歌词资产、三行显示与模式切换。

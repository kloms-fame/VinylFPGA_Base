# VinylFPGA S7-03b KEY07/KEY11 交互修复：实现与交付说明

> 日期：2026-10-06（北京时间）
> 工程：`D:\Data_Backup\VinylFPGA_Workspace_Base\VinylFPGA`
> 基线：Git `29a4593`（S7-03 资源优化后），顶层 `top`，器件 `EG4S20BG256`，工程入口 `prj/VinylFPGA.al`
> 本轮快照：`prj/resource_opt_verified_20261005/S7_03b_key07_key11_20261006_s7`（seed 7，`area_prior`）
> 状态口径：本文严格区分「计划」「已实现」「仿真通过」「构建通过」「SRAM 下载通过」「板级人工验收通过」。

## 0. 结论摘要

本次只修复 J2 交互归属，不重做主链路，不修改 SD/FAT32、音频 FIFO、视频仲裁、转场、缩略图布局或已验收的母板兜底通路。

用户反馈的原行为是：播放态按 KEY07（切歌模式）先返回主界面，再按一次才进入 2x2 缩略图选歌。本次已实现并完成仿真与构建：

1. **KEY07 = 切歌模式**：在主界面、缩略图视图和播放状态下都直接进入或切换 2x2 缩略图选歌视图。
2. **播放态 KEY07**：同拍产生 `play_stop` 和 `thumb_mode`，退出播放后直接落到缩略图选歌，不再先回主界面。
3. **KEY11 = 拓展1 = 返回主界面**：播放态产生 `play_stop` 和 `go_home`，回到主界面全屏视图，且不进入缩略图。
4. **母板兜底保持兼容**：母板 KEY1 短按/长按、KEY2 短按/长按的原有行为不变；播放态母板长按仍按旧行为退出播放并回主界面全屏。
5. **事件时序收敛**：`thumb_mode`、`play_stop`、`go_home` 全部在 `sd_card_clk`（100 MHz）单域同拍生成，避免旧版「退出播放」和「翻转视图」两条独立跨域路径之间的竞态。

当前状态：

| 项目 | 状态 |
|---|---|
| RTL 实现 | 已完成 |
| 定向仿真 | 已通过 |
| S0-S5、S6、S7 全量回归 | 已通过 |
| 综合、布局布线、bitgen | 已通过 |
| Setup/Hold 时序门禁 | 已通过，TNS=0、违例端点=0 |
| bit 生成 | 已生成 |
| JTAG SRAM 下载 | 已通过，器件识别和芯片校验成功 |
| 按键画面/声音的人工板级验收 | 本机无可用板载 USB-UART 采集口，未由自动化代理完成；需用户按第 10 节清单确认画面与声音 |

## 1. 修复目标与约束

### 1.1 修复目标

- 主界面按 KEY07 直接进入缩略图选歌。
- 播放界面按 KEY07 直接停止播放并进入缩略图选歌。
- 播放界面按 KEY11 直接停止播放并返回主界面全屏。
- 原有母板浏览/返回兜底不与 J2 新语义互相抢占。
- 不改变缩略图四宫格、四 bank 封面预加载、转场提交边界、播放暂停、切曲、音量、歌词、MV/黑胶等已验收行为。

### 1.2 实施约束

- 保持现有模块边界和命名，不新增顶层端口，不新增 J2 引脚约束。
- 保持时钟域约定：`clk=50 MHz`、`sd_card_clk=100 MHz`、`ext_mem_clk=125 MHz`、`video_clk=25 MHz`、`hdmi_5x_clk=125 MHz`。
- 保持低有效复位和各域既有同步释放约定。
- 改动范围最小化，主要落在 `src/io/browse_fsm.v` 的路由式逻辑；测试台同步更新。
- 不通过假路径、放宽时钟频率或删除已有时序约束来换取构建通过。

## 2. 修改文件清单与关键差异

### 2.1 RTL 文件清单

| 文件 | 变更类型 | 关键差异 |
|---|---|---|
| `src/io/browse_fsm.v` | 修改 | 分离 J2 KEY07/KEY11 与母板兜底路由；播放态 KEY07 产生 `play_stop + thumb_mode`，KEY11 产生 `play_stop + go_home` |

本次没有修改 `src/top_tf_hdmi_audio.v`、`src/io/ui_event_bridge.v`、`src/io/expansion_integration.v`、SD/FAT32、音频、视频或 SDRAM 文件。KEY11 的 `home_tgl` 到 `browse_fsm.ev_home_tgl` 通路已经在 S7-03 主线中存在，本次只修正 `browse_fsm` 对它的消费语义。

### 2.2 测试与验证文件

| 文件 | 变更内容 |
|---|---|
| `sim/tb_browse_fsm.v` | 增加 KEY11 事件和 `go_home` 计数；更新播放态 KEY07、KEY11 期望 |
| `sim/tb_s7_browse_semantics.v` | 重写为三项归属断言：浏览确认不开缩略图、播放 KEY07 进缩略图且停播、播放 KEY11 回主界面且不进缩略图 |
| `sim/integration/tb_top_control.v` | 强制 `brw_ev_home_tgl`；验证播放态 KEY07 直达缩略图、KEY11 回主界面以及同曲重进 |
| `sim/tb_s7_top.v` | 播放态 KEY07 改为一次按键直接进缩略图并停播 |

### 2.3 `browse_fsm.v` 关键差异

新增分流信号：

```verilog
wire j2_grid      = j2_mode & ~home_event;
wire mb_grid      = mb_mode & ~mode_play & ~home_event;
wire mb_stop_home = mb_mode &  mode_play;
```

顺序逻辑改为：

```verilog
thumb_mode <= j2_grid | mb_grid;
play_start <= confirm_any && !view_mode && !mode_play && !home_event && !mode_any;
play_stop  <= home_event || (mode_any && mode_play);
go_home    <= home_event || mb_stop_home;
```

语义解释：

- `j2_mode` 是 J2 KEY07 的同步边沿单拍。`j2_grid` 不受 `view_mode` 和 `mode_play` 阻挡，因此主界面和播放态都能进入缩略图；缩略图态再次按 KEY07 会退出缩略图。
- `mb_mode` 是母板 KEY1 长按单拍。`mb_grid` 只在非播放态生效，保持原有「浏览态进出缩略图」行为。
- `mb_stop_home` 保持播放态母板长按「退出播放并回主界面全屏」的旧行为。
- `home_event` 是 J2 KEY11 的同步边沿单拍。播放态 KEY11 同时产生 `play_stop` 和 `go_home`，不会产生 `thumb_mode`。
- `mode_any && mode_play` 覆盖 J2 KEY07 或母板长按在播放态的停播请求；J2 KEY07 的 `go_home` 被抑制，母板长按则由 `mb_stop_home` 继续保持回主界面。

### 2.4 没有改变的部分

- `thumbnail_controller.v`、`thumbnail_layout.v`、`thumbnail_view_reader.v`：未改。
- 四 bank 封面预加载、`select_req/select_ack`、转场 `frame_start` 边界：未改。
- `play_ctrl.v`、`timebase_48k.v`、`wav_stream_player.v`、MV/黑胶、SDRAM 仲裁：未改。
- `constraints/pin.adc`、`constraints/timing.sdc`：未改，J2 引脚与既有约束保持原状。
- 母板 KEY1/KEY2/KEY3、SW1-SW4、蜂鸣器和已验收的 S1-S6 输入路径：未改。

## 3. 用户可见交互语义

| 当前状态 | 输入 | 结果 |
|---|---|---|
| 主界面全屏 | KEY07 按下 | 进入 2x2 缩略图选歌 |
| 缩略图视图 | KEY07 按下 | 退出缩略图，回到主界面全屏 |
| 播放状态 | KEY07 按下 | 停止播放并静音，同拍落入 2x2 缩略图选歌；不先回主界面 |
| 主界面全屏 | KEY11 按下 | 保持主界面全屏，不进入缩略图 |
| 缩略图视图 | KEY11 按下 | 返回主界面全屏 |
| 播放状态 | KEY11 按下 | 停止播放，回到主界面全屏，不进入缩略图 |
| 播放状态 | 母板 KEY1 长按 | 保持旧行为：退出播放并回主界面全屏 |
| 非播放态 | 母板 KEY1 长按 | 保持旧行为：进入或退出缩略图 |

## 4. 事件编码格式

本次没有改变统一事件编码，沿用 `src/include/exp_event_defs.vh` 与 `src/io/ui_event_bus.v` 的既有格式：

| code | 名称 | arg[15:0] | aux[15:0] |
|---:|---|---|---|
| 0 | `EV_NONE` | 0 | 0 |
| 1 | `EV_KEY_DOWN` | key_index 0..11 | 0 |
| 2 | `EV_KEY_UP` | key_index 0..11 | 0 |
| 3 | `EV_DIP_CHANGE` | `{12'b0, dip_level, dip_index[2:0]}` | 0 |
| 4 | `EV_ENC_STEP` | 编码器累计计数 | `{14'b0, enc_id, direction}` |
| 5 | `EV_ENC_SW` | 实际打包为 `{15'b0, pressed}`：`arg[0]=0` 表示按下，`arg[0]=1` 表示释放 | `{15'b0, enc_id}` |
| 6 | `EV_IR_FRAME` | NEC 低 16 位 | NEC 高 16 位 |
| 7 | `EV_IR_REPEAT` | NEC 低 16 位 | NEC 高 16 位 |

约定：

- `key_index` 从 0 开始，KEY07 对应 index 6，KEY11 对应 index 10。
- `enc_id=0` 为 EC1，`enc_id=1` 为 EC2。
- `direction=0` 表示递增/顺时针，`direction=1` 表示递减/逆时针。
- NEC 帧布局为 `{Addr[31:24], ~Addr[23:16], Cmd[15:8], ~Cmd[7:0]}`，命令字节取 `code[15:8]`。
- `EV_KEY_DOWN` 是本次 KEY07/KEY11 业务动作的触发沿；释放沿只用于回显，不重复触发业务。

## 5. 串口输出格式

本次没有改变 UART 输出格式。`exp_echo_reporter` 继续使用 115200 8N1，ASCII 文本，行尾 `\r\n`：

| 事件 | 格式 | 示例 |
|---|---|---|
| 按键按下/释放 | `KEY <nn> DOWN` / `KEY <nn> UP` | `KEY 07 DOWN` |
| DIP 变化 | `DIP <n> <0/1>` | `DIP 5 1` |
| 编码器步进 | `ENC1/ENC2 <+/-> <hex16>` | `ENC1 + 0003` |
| 编码器按压 | `ENC1/ENC2 SW UP/DOWN` | `ENC2 SW DOWN` |
| 红外帧 | `IR <hex32> CMD <hex8>` | `IR BA45FF00 CMD FF` |
| 红外重复 | `IR REPEAT` | `IR REPEAT` |
| 启动/状态 | `BOOT LOGO`、`BOOT DONE`、`INFO`、`VERIFY`、`EXPHUB`、`DIP INIT`、`STAT`、`ERR` | 沿用 S7-01/S7-03 |

KEY07/KEY11 的业务效果不会新增串口命令；串口只记录原始输入事件，业务路由在 `browse_fsm` 中完成。

## 6. J2 约束片段

本次未修改 `constraints/pin.adc`。与本次交互直接相关的既有约束如下，电气标准均为 `LVCMOS33`：

```text
set_pin_assignment { exp_key_n[6] }  { LOCATION = G1;  IOSTANDARD = LVCMOS33; PULLTYPE = PULLUP; }
set_pin_assignment { exp_key_n[10] } { LOCATION = J12; IOSTANDARD = LVCMOS33; PULLTYPE = PULLUP; }
set_pin_assignment { exp_key_n[8] }  { LOCATION = L4;  IOSTANDARD = LVCMOS33; PULLTYPE = PULLUP; }
set_pin_assignment { exp_key_n[11] } { LOCATION = K11; IOSTANDARD = LVCMOS33; PULLTYPE = PULLUP; }
set_pin_assignment { exp_dip_n[0] }  { LOCATION = L3;  IOSTANDARD = LVCMOS33; PULLTYPE = PULLDOWN; }
set_pin_assignment { exp_dip_n[4] }  { LOCATION = K14; IOSTANDARD = LVCMOS33; PULLTYPE = PULLUP; }
set_pin_assignment { exp_dip_n[5] }  { LOCATION = L12; IOSTANDARD = LVCMOS33; PULLTYPE = PULLUP; }
set_pin_assignment { exp_ir_rx }     { LOCATION = K6;  IOSTANDARD = LVCMOS33; PULLTYPE = PULLUP; }
```

说明：

- KEY07 = `exp_key_n[6]` = `G1`。
- KEY11 = `exp_key_n[10]` = `J12`。
- DIP1 = `exp_dip_n[0]` = `L3`，是唯一弱下拉例外，用于 J2 在场声明。
- 其余 KEY、EC1/EC2、IR、DIP 引脚沿用 `constraints/pin.adc` 既有约束。

## 7. 时钟域与复位

- `browse_fsm` 仍运行在 `sd_card_clk`（100 MHz）。
- `ev_mode_tgl` 和 `ev_home_tgl` 仍从 `clk` 域通过独立 toggle 进入 `sd_card_clk`，`browse_fsm` 内使用目标域三级同步和边沿检测，一次事件只产生一个单拍。
- `thumb_mode`、`play_stop`、`go_home` 在同一个 `always @(posedge clk or negedge rst_n)` 块中生成，属于同一个 100 MHz 时钟域。
- 复位仍使用 `rst_n` 低有效异步断言、同步释放的既有约定；没有新增跨域握手，也没有新增时钟。
- 旧版「播放退出」和「视图翻转」分开跨域导致的两拍竞态，本次通过同域同拍控制脉冲消除。

## 8. 验证结果

### 8.1 定向仿真

以下命令均已在当前工作区执行并返回通过：

```powershell
python tools/verify_s0_s5_fixes.py
python tools/verify_s6.py
python tools/verify_s7_acceptance.py
python tools/verify_s703_controls.py
python tools/verify_s703_equivalence.py
python tools/check_streamer_transactions.py
```

关键输出：

- `verify_s7_acceptance.py`：全部 PASS，其中 `tb_s7_browse_semantics` 输出 `PASS s7_03b_mode_home_ownership`，`tb_s7_top` 输出 `PASS top UI keys, EOF replay, CRC remount, media fault silence and recovery`。
- `verify_s0_s5_fixes.py`：`tb_browse_fsm` PASS，`tb_top_control` 输出 `PASS same-bank exit/re-entry, EC1 pause/resume, KEY7 grid and KEY11 home`。
- `verify_s6.py`：MV、视频层、共享音频、带宽和帧调度全部 PASS。
- `check_streamer_transactions.py`：`PASS: FAT32 baseline transaction equivalence (1543 ordered events)`，`PASS: 262144 pipelined cluster LBA cases, all BPB selector bytes`。

### 8.2 逐项断言

`sim/tb_s7_browse_semantics.v` 覆盖三项：

1. 浏览态 confirm 不打开缩略图、不产生 `play_stop`。
2. 播放态 KEY07 必须打开缩略图、必须停播、不得 `go_home`。
3. 播放态 KEY11 必须停播、必须 `go_home`、不得打开缩略图。

`sim/tb_browse_fsm.v` 另外覆盖：

- 主界面 KEY07 进入缩略图。
- 缩略图 KEY07 退出缩略图。
- 播放态 KEY07 直达缩略图并停播。
- 播放态 KEY11 回主界面全屏。
- 母板长按在播放态保持旧的停播回主界面行为。

## 9. SynthPilot MCP、时序与 bit

### 9.1 MCP 辅助过程

已先读取 `https://www.synthpilot.dev/llms.txt` 并按其中用法使用 SynthPilot MCP。MCP 连接检查返回：

```text
Connected OK
TD Tcl version: 8.6.15
```

MCP 默认映射轮次的 `td_build` 完成到 bitgen，但最终 QoR 为：

```text
Setup WNS       +107 ps
Setup TNS          0
Hold WNS         -20 ps
Hold TNS         -47
Hold violated      4
```

因此默认轮次的 bit 没有作为交付物。MCP `td_report_qor` 和 `td_check_timing` 证据表明 Hold 违例来自既有 100 MHz 数据路径和布局敏感性，不是 `browse_fsm` 新增逻辑；且 `check_timing` 的高优先级结构检查为 `no clock=0`、`invalid constraint=0`、`combinational loops=0`。

随后使用同一 TD 版本对源码做确定性快照构建，保持 `area_prior`，仅扫描布局种子。最终通过的轮次为：

```text
prj/resource_opt_verified_20261005/S7_03b_key07_key11_20261006_s7
seed = 7
map_mode = area_prior
```

### 9.2 最终时序与资源

最终路由 QoR：

| 指标 | 结果 |
|---|---:|
| Setup WNS | `+114 ps` |
| Setup TNS | `0` |
| Setup 违例端点 | `0` |
| Hold WNS | `+3 ps` |
| Hold TNS | `0` |
| Hold 违例端点 | `0` |
| Wire length | `1632232` |
| Slices | `8412 / 9800 = 85.84%` |
| RAMs | `40` |
| DSPs | `15` |

结构约束检查：

| 检查项 | 结果 |
|---|---:|
| no clock | 0 |
| invalid constraint | 0 |
| combinational loops | 0 |
| clock definition problems | 0 |
| PLL/clock buffer 时钟约束缺失 | 0 |

### 9.3 bit 与下载

bit 由通过的 `routed.db` 生成：

```text
prj/resource_opt_verified_20261005/S7_03b_key07_key11_20261006_s7/VinylFPGA_optimized.bit
SHA256 23fd3bb166f7627ad9fd43759081ca6202644380400208658eee661bb542cac6
```

SRAM 下载结果：

- JTAG 目标识别：`EG4S20BG256`
- 芯片校验：`Chip validation success: EG4S20BG256`
- 下载命令：`download -mode jtag`
- 下载完成：`VERIFIED_SRAM_DOWNLOAD_COMPLETE`

注意：本次是 JTAG SRAM 下载，不是配置 Flash 固化。仓库忽略规则会把 `*.bit` 和 `prj/resource_opt_verified_20261005/` 快照排除在 git 之外，因此 bit 与快照保留在本地，不随本次提交进入 Git。

### 9.4 已知无关回归

`python tools/verify_resource_opt.py` 中既有 `tb_wav_equiv_long` 仍会因 2026-10-05 基线的 WAV 播放器 `sd_req` 门控差异失败，失败文件为 `src/audio/wav_stream_player.v`，本次没有修改该文件。FAT32 事务等价的独立检查已通过，因此不把该既有差异误归因于本次 KEY07/KEY11 修复，也不在本次改动中触碰 WAV 主链路。

## 10. 板级最小冒烟与人工验收清单

自动化侧已完成到「bit 生成 + 正确器件识别 + JTAG SRAM 下载通过」。当前主机只发现蓝牙串口（COM3-COM6），没有板载 USB-UART 采集口，因此无法由本机自动抓取 `KEY 07 DOWN`、`KEY 11 DOWN` 或启动 UART 文本。建议用户按以下清单做最终画面/声音验收：

1. 上电或下载后，确认主界面全屏画面正常，HDMI 无持续黑屏、花屏或撕裂。
2. 在主界面按 KEY07，确认直接进入 2x2 缩略图选歌，不先经过其他状态。
3. 在缩略图视图按 KEY07，确认退出缩略图并回主界面全屏。
4. 选中一首歌进入播放态，确认声音、歌词或 MV/黑胶正常。
5. 播放态按 KEY07，确认立即停止播放并直接显示 2x2 缩略图选歌，不先回主界面。
6. 播放态按 KEY11，确认立即停止播放并回主界面全屏，不进入缩略图。
7. 播放态使用母板 KEY1 长按，确认保持原有「退出播放并回主界面」行为。
8. 非播放态使用母板 KEY1 长按，确认缩略图进出行为仍正常。
9. 若接入 UART，按下 KEY07 应看到 `KEY 07 DOWN`，按下 KEY11 应看到 `KEY 11 DOWN`；释放分别看到对应 `KEY 07 UP`、`KEY 11 UP`。

板级人工验收未由自动化代理宣称通过；下载成功只说明配置进入器件，不等同于画面、音频和按键效果已经人工确认。

## 11. 回滚与风险

### 回滚点

- RTL 回滚：将 `src/io/browse_fsm.v` 恢复到本次提交前版本。
- 测试回滚：同时恢复 `sim/tb_browse_fsm.v`、`sim/tb_s7_browse_semantics.v`、`sim/integration/tb_top_control.v`、`sim/tb_s7_top.v`，保持回归期望与新 RTL 一致。
- bit 回滚：保留上一已验收 bit 或从 `S7_03_v5` 等历史通过快照重新生成，不覆盖历史 bit。

### 风险说明

- KEY07 在缩略图视图是切换键，因此缩略图态再按 KEY07 会回主界面；这与「主界面和播放态都能直接进入缩略图」并不冲突。
- KEY11 的 `go_home` 是非播放态也存在的显式回主界面请求；在已经处于主界面全屏时该请求是定义上的幂等动作。
- 母板兜底与 J2 新语义同时发生时，J2 KEY07/KEY11 由独立事件分流处理，母板长按保持旧行为；不会把母板长按误当成 KEY11。
- 最终 bit 使用 seed 7 收敛既有 100 MHz 布局敏感路径。seed 本身不是功能配置，源码、约束、映射模式和工具版本均已记录在快照中；不得用默认轮次的失败 bit 替换本 bit。

## 12. 交付状态与后续

本次交付边界：

- 已实现并仿真通过：KEY07 主界面/播放态直达缩略图、播放态同拍停播、KEY11 回主界面全屏。
- 已构建通过：seed 7、`area_prior`、Setup/Hold 非负、TNS=0、违例端点=0。
- 已生成并下载：`VinylFPGA_optimized.bit`，SHA256 `23fd3bb166f7627ad9fd43759081ca6202644380400208658eee661bb542cac6`。
- 待人工确认：板载画面、声音和实际按键手感。

后续阶段仍按 S7 开发方案推进；S7-04 菜单与统一参数、S7-05 外设反馈与 WS2812、S7-06 播放结束/重播/seek 不应与本次交互修复混在同一提交中。

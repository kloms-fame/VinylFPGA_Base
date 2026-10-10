# VinylFPGA 资源占用盘点与优化分析（Slice/LUT 优先）· 复核与最终执行方案

> 日期：2026-10-07（北京时间）
> 工程：`D:\Data_Backup\VinylFPGA_Workspace_Base\VinylFPGA`
> 器件：EG4S20BG256　工具：Tang Dynasty v6.2.168116
> 顶层：`src/top_tf_hdmi_audio.v` 中的 `top`
> 文档性质：资源复核、结论冲突裁定、删除边界与优化执行方案。**本次未修改任何生产 RTL、未重新综合、未布线、未生成位流、未烧录。**

---

## 0. 本次复核的三个决定性发现

| # | 发现 | 影响 |
|---|---|---|
| **A** | **`X2_r15s5_20261007` 基线已经过期。** 112 项输入哈希实测 **100 项一致、12 项已变** | 所有资源/时序数字只能作为「历史候选」引用，**不能**作为当前工作区的优化起点 |
| **B** | 工作区存在 **13 个已修改未提交的生产源文件 + pin.adc**，包含数码管 6→8 位重构、KEY3 停用、EC1/EC2 Seek 语义对调 | 现行方案中「保留 KEY3」「数码管为 6 位」等前提**已不成立**；本报告按当前源码重述 |
| **C** | **SynthPilot MCP 在本会话不可用**（工具检索未返回任何 synthpilot 工具） | 本报告资源数字全部来自报告文件与源码实测，**不含** MCP 综合结果；不伪造调用 |

---

## 1. 结论摘要

### 1.1 资源基线（历史候选，非当前源码）

来源：`prj/resource_opt_verified_20261005/X2_r15s5_20261007/final.area:4-29`、`final.qor:6-24`

| 资源 | 使用/容量 | 使用率 | 余量 | 判断 |
|---|---:|---:|---:|---|
| **Slice** | **9288/9800** | **94.78%** | **512** | 第一瓶颈，已越过 90% 风险线 |
| **LUT** | **17415/19600** | 88.85% | 2185 | 第二目标 |
| FF/REG | 10527/19600 | 53.71% | 9073 | 非瓶颈，不需专门牺牲流水 |
| BRAM9K | 40/64 | 62.50% | 24 | **有余量，可换 LUT** |
| BRAM32K | 0/16 | 0% | 16 | 标称 16，不与 BRAM9K 余量相加承诺 |
| DSP | 17/29 | 58.62% | 12 | 非瓶颈，保留现乘法映射 |
| IO | 71/188 | 37.77% | 117 | 输入 35 / 输出 35 / 双向 1 |
| PLL | 2/4 | 50% | 2 | 无需删时钟 |
| GCLK | 2/16 | 12.50% | 14 | 非瓶颈 |

LE 17982 = LUT-only 7455 + REG-only 567 + LUT&REG 9960。Slice 占用率高于 LUT 占用率，说明瓶颈同时来自**打包与物理实现**，不能按 LUT 数线性折算 Slice。

### 1.2 时序（历史候选）

`final.timing`：Setup WNS **+0.048 ns**、Hold WNS **+0.024 ns**、TNS 均 0、违例端点均 0、STA coverage 99.95%、总端点 9649。
最紧 Setup 在 `sd_card_clk`(100 MHz) 域，`video_rgb_to_axis_640x480/I_rgb[12]_syn_*` 路径族。

`final.qor` 与 `final.timing` 时钟汇总一致核对：

| 时钟 | 频率 | Fanout | SWNS | HWNS |
|---|---:|---:|---:|---:|
| `sd_card_clk` | 100 MHz | 2894 | **0.048 ns** | 0.077 ns |
| `video_clk` | 25 MHz | 1841 | 9.187 ns | 0.024 ns |
| `clk` | 50 MHz | 1312 | 3.542 ns | 0.076 ns |
| `ext_mem_clk` | 125 MHz | 597 | 0.176 ns | 0.037 ns |
| `hdmi_5x_clk` | 125 MHz | 32 | 4.606 ns | 0.214 ns |
| `ext_mem_clk_sft` | 125 MHz | 1 | 0.000 ns | 0.000 ns |

### 1.3 优化方向结论

**首要目标 Slice/LUT 下降的方向成立且明确**，最高收益入口是三处：**UART 遥测整体退出、母板 KEY1/KEY2 旧交互整链撤销、字库转 BRAM**。共享消抖时基是第四入口，需在 KEY1/2 撤销后按剩余通道重算。

---

## 2. 资料交叉核对：冲突与不一致

### 2.1 四份资料一致性裁定

| 资料 | 裁定 | 依据 |
|---|---|---|
| `最终优化执行方案_Slice与LUT优先` | **主体成立**，但前提已过期 | 其 O1–O7 顺序、删除闭包、字库 +2 BRAM 结论经本次源码验证正确；但「当前 = 66da60f」「KEY3 保留」「数码管 6 位」三条前提被本次实测推翻（见 §2.3） |
| `资源占用盘点与优化分析` | **全局数字正确，逐模块表不可用** | 其 `reporter 943 / menu 269 / seek 297 / hub 1229 / key_dip 731 / lrc_osd 624 / rgb2axis 650` 与 `gate.area` 实测全部不符（见 §2.2） |
| `第1课_从官方例程到完赛工程` | **教学/对照资料，非当前网表** | 官方例程为 3 PLL / 100 MHz SDRAM / `bmp_read`；当前工程为 2 PLL / SDRAM 125 MHz / 自建 FAT32 栈。保留其分层、CDC、单变量验证与证据分级方法论 |
| `11111VinylFPGA_最终执行方案_代码与资料综合核对` | **产品路线有效，基线数字全过期** | 其基线 `a357339` / `8412 Slice` / `DSP 15` 均已被 X0R/X1/X2 后续提交取代；其 X5「保留 param_menu_controller 与母板组合键」条款被本次需求取代 |

### 2.2 逐模块资源数字冲突（以 `gate.area` 实测为准）

`X2_r15s5_20261007/gate.area` 解析 194 行层次表，顶层行 `lut=14944 rip=1824 seq=10530 bram=40 dsp=17`。

| 实例 | `资源占用盘点` 声称 | **`gate.area` 实测** | 差异 |
|---|---:|---:|---:|
| `u_exp_echo_reporter` | 943 | **860** | −83 |
| `u_param_menu_controller` | 269 | **267** | −2 |
| `u_seek_controller` | 297 | **337** | +40 |
| `u_expansion_io_hub` | 1229 | **1259** | +30 |
| `u_key_dip_monitor`(J2) | 731 | **738** | +7 |
| `u_lrc_osd` | 624 | **623** | −1 |
| `u_video_rgb_to_axis_640x480` | 650 | **597** | −53 |
| `u_s6_video_layer` | 545 | **628** | +83 |
| `u_frame_read_write_m0` | 459 | **471** | +12 |
| `u_wav_stream_player` | 458 | **448** | −10 |
| `u_thumbnail_view_reader` | 270 | **294** | +24 |
| `u_ui_event_bridge` | 236 | **203** | −33 |
| `u_health_monitor` | 118 | **112** | −6 |

**判定**：`资源占用盘点` 的 §2.4/§2.5 逐模块表混入了其它映射/其它轮次的结果，**逐模块收益不得直接沿用**；其 §0.1/§2.1 的全局数字（9288/17415/10527/40/17）经 `final.area` 与 `final.qor` 双向核对**正确**。

### 2.3 与当前源码不一致之处（本次新增裁定）

| # | 现行方案表述 | 当前源码实测 | 裁定 |
|---|---|---|---|
| 1 | 「当前源码 `66da60f`」「112/112 哈希一致」 | `git rev-parse HEAD` = `66da60f`，但工作区 13 个生产文件已改；`inputs.sha256.json` 实测 **100/112 一致、12 项 DIFF** | **前提失效**。差异文件：`top_tf_hdmi_audio.v`、`timebase_48k.v`、`seg_business_mux.v`、`seg_scan.v`、`expansion_integration.v`、`led_business_driver.v`、`ui_command_router.v`、`ui_event_bridge.v`、`ws2812_effects.v`、`mv_frame_scheduler.v`、`s6_video_layer.v`、`constraints/pin.adc` |
| 2 | 「母板 KEY3、SW1–4 保留」 | `top_tf_hdmi_audio.v` 例化处已写 `.key3 (1'b1)`；`expansion_integration.v:356` 已改 `assign disp_mode_tgl = 1'b0; // KEY3 display pages removed.` | **KEY3 事实上已停用**（未提交）。删除范围应按「KEY3 已停用」而非「KEY3 保留」重述；`key3` 引脚仍占用 B1 |
| 3 | 「数码管 6 位」「`seg_sel[5:0]`」 | `top` 已改 `output [7:0] seg_sel`；`seg_scan.v` 已重写为 8 位含消隐；`pin.adc` 已把 `seg_sel[0..7]` 改到 F16/E16/E12/E10/C13/F10/E11/D11 | **数码管已 8 位化**，并新增 2 个 IO |
| 4 | 「`seg_business_mux` 有独立 ms/秒/BCD 计时，需交 X2 补验」 | `seg_business_mux` 已重写为接收 `sample_position` / `song_index`，计时移交 `timebase_48k`；`timebase_48k` 已改为 32 周期精确除 48 | 该合并项**已由未提交改动实现**，应改为「验证」而非「候选」 |
| 5 | 「X2 Seek 由 EC2 旋钮触发」 | `ui_event_bridge.v` 已删 `ev_seek_fwd2/ev_seek_bwd2`，改为 `enc_delta` 驱动 `seek_fwd2/seek_bwd2`；`ui_command_router.v` 红外 F8/EA 对调 | 属未提交的行为变更，**必须先回归再谈资源** |
| 6 | 「顶层 `.al` 与 include 的 22 个未登记文件」 | 实测 **28 个** `.v` 仅经顶层 `include` 参与构建、未在 `prj/VinylFPGA.al` 登记（含 `health_monitor.v`、`param_menu_controller.v` 同级的 `lrc_osd.v`、`s6_video_layer.v`、`seek_controller.v` 等） | 数量修正为 28；`health_monitor.v` 本身不在 `.al`，删除时**不能只改 `.al`** |

---

## 3. 模块盘点表

### 3.1 全量 RTL 清单（105 个 `.v` + 4 个 `.vh`）

`src` 目录构成：

| 目录 | `.v` 数 | 职责 | 本轮边界 |
|---|---:|---|---|
| `src/` 根 | 13 | 顶层/PLL 接线、同步复位、HDMI PHY、RGB→AXIS | 裁旧接线；PHY/AXIS 保留 |
| `src/SD/` | 26 | SD 协议、FAT32、索引、媒体监督、帧缓冲、数码管、旧母板控制 | 裁旧 KEY 链；FAT/SDRAM 时序不重构 |
| `src/audio/` | 13 | WAV、play/Seek/session、PCM 桥、音量、时基 | 保留 X2 行为与流水 |
| `src/display/` | 15 | 旧 OSD/歌词/波形/转场/画质/缩略图/数码管业务 | 删旧三行 OSD；字库 BRAM |
| `src/io/` | 23 | J2 驱动/事件/路由、母板监控、UART、反馈 | 删 UART 与母板两键；共享消抖 |
| `src/boot/` | 2 | Logo 层与 ROM | 保留已优化 BRAM 分组 |
| `src/video/` | 4 | MV 流/调度/仲裁/S6 层 | 保留 PCM 优先与扇区所有权 |
| `src/IP/`、`src/include/`、加密目录 | 12 | PLL/FIFO/SDRAM 核/参数/加密实现 | 黑盒接口保留 |

`.v` 含加密 IP 与仅宏定义文件，**不能把 105 叫作 105 个有效逻辑模块**；静态 module 定义 106 个（含生成 FIFO 子模块与同文件辅助模块），有效映射层次见 `gate.area` 194 行。

### 3.2 主要资源来源（`gate.area`，父实例含子实例，不可相加）

| 直接子实例 | 模块 | LUT | ripple | seq | BRAM | DSP |
|---|---|---:|---:|---:|---:|---:|
| `sd_card_bmp_m0` | `sd_card_bmp` | 3997 | 260 | 3367 | 0 | 0 |
| `u_expansion_integration` | `expansion_integration` | 3268 | 517 | 1768 | 0 | 0 |
| `u_hdmi_1_4b_transmitter_core_wrapper` | HDMI 加密核 | 1248 | 149 | 1503 | 16 | 0 |
| `u_s6_video_layer` | `s6_video_layer` | 628 | 131 | 312 | 0 | 4 |
| `u_lrc_osd` | `lrc_osd` | 623 | 13 | 88 | 0 | 0 |
| `u_video_rgb_to_axis_640x480` | `video_rgb_to_axis_640x480` | 597 | 0 | 26 | 0 | 0 |
| `frame_read_write_m0` | `frame_read_write` | 471 | 115 | 357 | 4 | 0 |
| `u_wav_stream_player` | `wav_stream_player` | 448 | 69 | 292 | 8 | 0 |
| `u_seek_controller` | `seek_controller` | 337 | 27 | 230 | 0 | 0 |
| `u_thumbnail_view_reader` | `thumbnail_view_reader` | 294 | 65 | 246 | 2 | 1 |
| `u_param_menu_controller` | `param_menu_controller` | 267 | 41 | 168 | 0 | 0 |
| `u_board_key_sw_monitor` | `key_dip_monitor` | 267 | 52 | 187 | 0 | 0 |
| `u_key_next_transition` | `key_press_hold` | 85 | 13 | 55 | 0 | 0 |
| `u_key_thumb_left_confirm` | `key_press_hold` | 84 | 13 | 55 | 0 | 0 |
| `u_sync_fade_gain` | `sync_fade_gain` | 165 | 0 | 101 | 0 | 0 |
| `u_media_supervisor` | `media_supervisor` | 145 | 28 | 62 | 0 | 0 |
| `u_boot_layer` | `boot_layer` | 142 | 40 | 53 | 10 | 3 |

**SD/FAT32 与扩展集成合计 7265 LUT，占层次 LUT 14944 的 48.6%。** 但 SD 域最大不等于应先重写 FAT32 —— 扩展板遥测与旧母板交互是更明确、风险更低的减负入口。

### 3.3 删除候选热点

| 深入热点 | LUT/ripple/seq | 归属 |
|---|---|---|
| `fat32_media_loader_m0` | 3491/221/3060 | 含 scanner 792、index 715、streamer 550；父子不可相加 |
| **`u_exp_echo_reporter`** | **860/23/358** | UART 文本遥测，**明确可删** |
| `u_key_dip_monitor`(J2) | 738/198/432 | 18 路 J2 键/DIP 消抖 |
| `u_health_monitor` | 112/43/100 | UART 计数/定时；`err_code` 仍驱动 LED4 |
| `u_board_key_sw_monitor` | 267/52/187 | 3 键+4SW；**KEY3 已停用后为 2 键+4SW=6 路，不能整块删** |
| `u_key_next_transition`+`u_key_thumb_left_confirm` | 169/26/110 | 两个母板短长按识别器 |
| `sd_card_bmp_m0/u_key_auto` | 36/6/24 | 100 MHz 下母板 KEY2 再消抖 |
| **`u_lrc_osd/u_font_rom`** | **424/0/0** | 组合字库，适合 BRAM 替换 |
| `u_osd_overlay_24`(含 `u_osd`) | 6/5/19 | **不可据此断言整层只省 6 LUT** |

**跨模块归属迁移警告**：`video_rgb_to_axis_640x480` 源码仅约 67 行却综合出 597 LUT，且 `final.constraints` 有多处 `u_video_rgb_to_axis_640x480/I_rgb[12]_syn_*`；旧 OSD 自身仅记 6 LUT。合理推断是 OSD 的部分组合逻辑被映射到下游 RGB 输出级。**不得据 597 直接提出「AXIS 能省 100–250 LUT」，也不得把 597 叠加到 OSD 删除收益上**；必须做关闭旧 OSD 的整机差分。

### 3.4 BRAM / DSP 构成

BRAM 40 顶层分配：HDMI 16、Logo 10、WAV 8、帧读写 4、缩略图 2。
DSP 17 分配：S6 视频 4、Logo 3、画质 3、转场 3、时基 2、缩略图 1、PCM 增益 1。
不动现有音频 FIFO 深度，不缩掉防欠载容量。

---

## 4. 逐项优化措施

### 4.1 确定可删除（功能取舍已定，无需再确认）

#### D1. UART 遥测全部逻辑 —— 首要入口

| 项 | 内容 |
|---|---|
| 代码落点 | `src/io/expansion_integration.v:320-346`（`exp_echo_reporter` 例化）、`:295-317`（`health_monitor` 例化）、`:264-265`（`report_valid` 专供串口）；`src/io/exp_echo_reporter.v`（565 行，860 LUT，18 个格式化 task）；`src/io/exp_uart_tx.v`（65 行）、`src/io/exp_baud_tick.v`（33 行）；`src/top_tf_hdmi_audio.v:18-20` 三处 include；`top_tf_hdmi_audio.v:126` 附近 `ECHO_TEST_ENABLE` |
| 删除闭包 | reporter 实例、报文缓冲与格式化队列、专用 baud/tx、`stat_req` 周期计时、4 路 16 位饱和计数、版本透出、专用遥测状态 CDC |
| 预估净 LUT 收益 | **750–1000**（reporter 860+ripple 23 全额，加 health 112+ripple 43 中可裁部分） |
| FF 影响 | 数百 FF 下降（4×16 位饱和计数 + `msg` 缓冲寄存器） |
| BRAM/DSP | 不增加 |
| 影响的功能范围 | **丢失** STAT/ERR/KEY/DIP/ENC/IR/BOOT/VER 全部串口观测。**不影响** LED/WS2812/蜂鸣、数码管错误码、媒体恢复、J2 命令流 |
| 风险等级 | **中低** |
| 关键约束 | ① 禁止只在输出端 mask 而让格式化状态机继续运行，最终以网表无 reporter/baud/tx 为准；② `health_monitor.err_code` 被 `expansion_integration.v:470` 用于 `led_business_driver.fault`，**必须保留当前错误寄存器与清零语义**（`health_monitor.v:103-107` 允许 `osd_err_code=0` 表示恢复）；③ `io_ready/exp_actions_ready/present_count` 服务 DIP1 在场声明与热插拔，**不随 reporter 一并删除**；④ 建议 `uart_tx` 保留物理端口并固定 `1'b1`（串口空闲高电平），保留 `pin.adc` D12 约束 |

#### D2. 母板 KEY1/KEY2 旧交互整链

| 项 | 内容 |
|---|---|
| 代码落点 | `top_tf_hdmi_audio.v:698-721`（`param_menu_controller` 例化）、`:1017-1046`（两个 `key_press_hold`）、`:230-238`（`key1_eff_n/key2_eff_n/cfg_menu_*`）、`:286-298`（`key2_thumb_press/hold/lock`）、`:1200`、`:1225-1226`、`:1275-1282`、`:1508-1524`（`menu_active_frame`）；`src/io/browse_fsm.v:46-49`（`mb_next/mb_mode/mb_left/mb_confirm` 端口）、`:104-116`、`:132-143`；`src/SD/sd_card_bmp.v:77-79`、`:111-112`、`:135-137`、`:157`、`:259-260`、`:421-463`（KEY2 长按/短按自动轮播）；`src/SD/sd_card_bmp.v:748-771`（内部 `key_press_debounce`）；`src/io/expansion_integration.v:358-373`（母板 3 键消抖） |
| 删除闭包 | 亮度/对比度菜单与 combo/hold/idle/debounce 全链、两个短长按识别器、`key2_thumb_lock_sd`、`browse_fsm` 的 4 个 `mb_*` 端口与内部 OR/分支、`sd_card_bmp` 的 `key_auto_stable/_d`、`long_press_cnt/_marked`、`auto_play_en/auto_cnt/auto_tick` 及仅由该键开启的轮播分支 |
| 预估净 LUT 收益 | **550–850**（menu 267、两个 hold 169、`key_auto` 36、母板两路消抖约 70，另有计数与 CDC） |
| FF 影响 | 约 300–500 FF 下降 |
| BRAM/DSP | 不计划增加。画质若被常量旁路，**可能附带裁掉 3 个 DSP，但这是暂时收益，不得计入永久预算** |
| 影响的功能范围 | **删除**：母板 KEY1/KEY2 的短按、长按 1 s、组合按压、Boot 跳过、按键提示音来源、BxxCyy 调参界面、KEY2 定时自动轮播、KEY2 长按上一张。**保留**：J2 KEY01–KEY12、KEY07/KEY11 语义、`prev_event`/`next_event`、缩略图业务本身、KEY3（现已停用）、SW1–SW4 |
| 风险等级 | **中** |
| 关键裁决 | ① **「合并母板 KEY 重复消抖」在本轮不应实现为把 KEY1/2 送回 SD 域** —— 最有效方式是删掉其全部消费者，`key_auto` 随 KEY2 功能一起消失，而非合并；② X2 `end_mode=E2` 的歌曲 EOF 自动下一曲**保留**，X8 自动演示走统一命令接口；③ `browse_fsm` 的 `thumb_right/left/confirm/mode` **业务输出全部保留**，只删 `mb_*` 输入；④ 删除 `key1/key2` 物理端口时同步删 `pin.adc` B2/C1，**保留 key3=B1 与 rst_n=A2**；⑤ O2 到 X5 之间画质固定 `brightness=255/contrast=128`，但 `brightness_contrast_adjust` 输出寄存一级**不得因常量旁路而手工跳过** |

#### D3. 屏幕左上角三行调试字符

| 项 | 内容 |
|---|---|
| 代码落点 | `src/display/status_osd_overlay.v:87-145`（第一行 `index+1`/`A或E`/`error`、第三行 `E+end_mode`/`F+effect_mode`、第二行 `BxxCyy`）；`src/display/osd_overlay_24.v`（整层，含 `line_y` 行计数）；`top_tf_hdmi_audio.v:1585-1609`（`u_osd_overlay_24` 例化）、`:372`（`ui_modes_v1/v2`）、`:548-556`（`auto_enabled_sync1/2`、`osd_error_code_frame`）、`:1808-1854`、`:1508-1524`（`menu_active_frame`） |
| 删除闭包 | 整层 `u_osd_overlay_24` 生产实例、`u_osd`（`status_osd_overlay`）、私有 `line_y` 计数器、仅供 OSD 的 `ui_modes_v1/v2`、`auto_enabled_sync1/2`、`menu_active_frame`、私有行计数/字模 |
| 预估净 LUT 收益 | **0–250**（层次行仅 6 LUT，但部分组合逻辑可能归属下游 RGB 输出级） |
| FF 影响 | 少量 FF 下降 |
| 影响的功能范围 | **删除**：屏幕左上角三行常驻调试字符。**保留**：`end_mode`/`effect_mode` 的实际业务行为（`play_ctrl` 与转场仍消费）、故障恢复、LED4、数码管错误提示 |
| 风险等级 | **中低** |
| 关键约束 | ① 这三行**不是字体资源名也不是错误码常量**，不能靠搜索字符串「1E00」定位；② 旁路时以原 `rgb_in` 表达式直送原 `rgb_out` 消费者，**保留**「首图未就绪且媒体错误时背景色」策略（`top:1595` 的 `(!display_valid_sync2 && osd_err_code_frame_eff != 0) ? 24'h201018 : adjusted_rgb`）；③ **不得改变 DE/VS/像素时刻**；④ `adjusted_pixel_x` 仍供 waveform/S6/歌词/Logo，**保留**；`osd_error_code` 名称含 OSD 但仍供挂载判断与 supervisor，**不按名字全删**；⑤ PnR 整机差分记录净收益并检查 AXIS 归属变化，**拒绝双重记账** |

#### D4. 字库数据转 BRAM/ROM 常驻

| 项 | 内容 |
|---|---|
| 代码落点 | `tools/gen_lrc_assets.py`（**源头，不能只手改生成结果**）、生成的 `src/display/lrc_font_rom.v`（974 行）、`src/display/lrc_osd.v`、必要的 `src/include/lrc_geom.vh` |
| 容量实算 | `lrc_geom.vh`：`LRC_CHARSET_SIZE=60`、`LRC_GLYPH_H=16`、`LRC_FONT_ADDR_W=10`。实测 `lrc_font_rom.v` 含 **960 条地址项**、其中 740 条非零。**960×16 = 15360 bit**；按 1024×16 组织 = 16384 bit |
| BRAM 增量 | **+2 BRAM9K**（不是 +1）。建议两个 512×16 bank 或 TD 验证可映射的等价同步 ROM |
| 预估净 LUT 收益 | **280–400**（层次实测 `u_font_rom` = 424 LUT / 0 ripple / 0 seq，**纯组合**，是全工程最干净的 LUT→BRAM 转换） |
| 影响的功能范围 | 歌词 OSD 像素时序。字宽 16 px、起始 x=96，足够在字边界前预取下一字形行 |
| 风险等级 | **中** |
| 关键约束 | ① **首选「提前取字形行」，不改整条 RGB/DE 流水** —— 按「ROM 读延迟 + 下游寄存采样」确定提前量（常见约 2 拍），实际拍数由仿真确定，**不能假定同步 ROM 输出在发地址同拍可用**；② 每行第一个字同样需在左边界前预取；③ **禁止只延迟 `font_row` 而不对齐 `in_box/col_pix/背景 RGB`**；④ 备选方案（整束延迟一级）须同时重算 BOOT/消隐/AXIS/音频数据岛坐标，本轮优先避免；⑤ `rom_style` 等 Vivado 属性**未经验证不得当作安路支持的控制手段**；⑥ 重新生成的 mem/init 外部文件必须进快照与 hash 清单 |

#### D5. 失效注释代码与不可达私有线

| 项 | 内容 |
|---|---|
| 代码落点 | 如 `cfg_menu_*`、`ui_modes_v1/v2`（仅供旧 OSD 显示的副本）、`media_id_v1/v2` 类私有同步副本 |
| 预估净 LUT 收益 | **0**（多为已综合掉的注释或不可达逻辑） |
| 风险等级 | **低** |
| 关键约束 | **逐条查所有消费者后清理**。`adjusted_pixel_x`、`media_id` 等仍供歌词/S6/音源的公共信号**保留** |

### 4.2 需确认后删除

| # | 项目 | 当前状态与证据 | 需要确认什么 |
|---|---|---|---|
| C1 | `src/SD/key_press_hold.v` 文件 | 顶层有两处生产例化（`:1017`、`:1032`），D2 删除后无生产消费者。`sim/` 中**无 TB 引用**该模块 | 可随 D2 一并移出生产清单。生产面积收益已计入 D2，**不得重复计算** |
| C2 | `pcm_media_tone`（非 WAV 测试琶音） | `top` 仍有例化，`gate.area` 有独立行 `u_pcm_media_tone` = 15 LUT / 0 ripple / 4 seq。**不是死码** | 是否还需要非 WAV 音源？删除可回收约 15 LUT + 4 FF，功能影响需确认 |
| C3 | Boot Logo 层 | `u_boot_layer` = 142 LUT / 10 BRAM / 3 DSP。属后续开发目标，非冗余 | 若 Slice 仍超预算，是否接受去掉开机 Logo |
| C4 | MV / Black Vinyl | `u_s6_video_layer` = 628 LUT / 4 DSP，另有 `mv_frame_scheduler` 303、`mv_stream_player` 101、`mv_sector_mux` 6 及 SDRAM 通道 | 属产品功能取舍，不在本次明确删除范围内 |
| C5 | LED / WS2812 / 蜂鸣 | `u_ws2812_effects` 142、`u_buzzer_feedback` 205、`u_led_business_driver` 77。X1 已把它们做成真实执行器，**不再是空挂逻辑** | 若 Slice 仍超预算，是否精简反馈通道 |
| C6 | 母板 SW2 / SW4 | 仍有消抖与 `board_sw_level` 反馈语义 | 是否有实际消费端；无消费端则可从 `DIP_COUNT` 移除 |
| C7 | `health_monitor` 整块 | 112 LUT。`err_code` 仍驱动 LED4 故障灯 | 若删则需替代故障观测；**不建议整块盲删** |
| C8 | `sync_fade_gain` 同域特化 | 165 LUT。`top` 的 `pix_clk` 与 `aud_clk` **均为 `video_clk`**，该模块的跨域外观与实际不符 | 是否值得同域特化；**不能直接删两级寄存器**，须保持增益逐拍与淡出结束行为 |
| C9 | `quadrature_decoder.stable_count` 位宽 | 32 位可参数化收窄 | 单独候选；**先不改 A/B 滤波算法**，原 1 ms 合法四相序列与方向计数必须保持 |
| C10 | 历史构建目录 / bit / 输入哈希 | `prj/resource_opt_verified_20261005` 约 3.30 GiB、14415 文件 | 归档范围另定任务；**不得以清磁盘声称节约 Slice** |

### 4.3 确定不删除（防误删清单）

| 项目 | 理由 |
|---|---|
| `fat32_media_loader` / `sd_card_top` / `spi_master` / `sdram` / HDMI 加密核 | 生产可靠性与协议栈本体，无删除依据 |
| CRC 校验 / 文件校验 / FIFO 保护 | 坏卡与损坏文件容错；历史删改收益未证明 |
| `media_supervisor` / `media_probe` / 超时 | 音频静音、恢复、SD 复位代次依赖 |
| 时钟同步器与复位链 | 功能使用者退出后**仅删该支路私有 CDC**；不得全局替换异步复位或缩短同步级数 |
| 现有音频 FIFO 深度 | 防欠载容量，不得缩 |
| `adjusted_pixel_x` / `media_id` / `play_end_mode` / `effect_mode` | 仍供歌词/S6/波形/Logo/转场消费 |
| `key3=B1` 与 `rst_n=A2` 约束 | 不得因「删两键」误删复位；KEY3 现已停用但引脚仍占用 |

---

## 5. 共享消抖时基（保留 KEY3/SW 后的独立优化）

### 5.1 通道口径重算

原 27 个通用 `debounce_filter` = J2 键/DIP 18 + 母板 3 键 4 SW 共 7 + 两编码器按压 2。
**D2 撤销 KEY1/KEY2 后，母板侧由 7 路降为 KEY3 + SW1–SW4 = 5 路；且 KEY3 已在未提交改动中停用。**
若同时移除 KEY3，则母板为 4 路，合计 18 + 4 + 2 = **24 路**。
**两个编码器 A/B 稳定状态机另算，不包含在通用消抖器内**；不得把 A/B 也改成低速采样。

> 注：25 路（保留 KEY3）或 24 路（KEY3 一并移除）的口径，取决于 KEY3 是否恢复。本轮按「KEY3 已停用」取 24，若恢复 KEY3 则按 25 重新核算。

### 5.2 推荐首版：共享 clock-enable + 每通道连续稳定状态

1. `clk = 50 MHz`，统一 5000 周期 tick（13 bit 分频）。**tick 是单拍使能，不能作为新时钟。**
2. 每个物理输入**保留独立两级同步器**；每通道保留 `level`、`candidate/armed` 及 7 bit 稳定计数（8 ms = 80 个 100 µs 完整区间）。
3. 同步值**每 50 MHz 周期检查**；任一不连续或返回已确认电平立即使本通道计数与 `armed` 失效。**不能仅 100 µs 采一次而看漏两个 tick 间毛刺。**
4. 候选变化后第一个 tick 只建立计时起点，**不计一个完整区间**；再累积 80 个完整区间才提交。稳定窗口 ≥ 8 ms，额外等待 < 100 µs（另加同步延迟）。计数饱和后产生**一次** fall/rise 脉冲。
5. `level` 初值沿用原 1；按键低有效、DIP 上拨=1 **不二次取反**。各通道状态独立，**不共享「任意键变化就归零」的计数器**。
6. **初始化抑制必须重算**：`key_dip_monitor.v:22` 的 `SETTLE_CYCLES = DEBOUNCE_CYCLES + 8`、`expansion_integration.v:231` 的 `PRESENT_SETTLE = DEBOUNCE_CYCLES + AB_STABLE_CYCLES + 16` 均按旧最坏窗口设计，**新窗口下可能过早，必须重算或改为显式「全部初始化完成」**。
7. 500 ms Boot 跳过保护（`expansion_integration.v:390` `SKIP_GUARD_CYCLES = CLK_FREQ_HZ/2`）**保留**；初值收敛不是用户操作。

**这不是逐周期完全等价修改**：允许事件增加约 100 µs 量化延迟，但**不提前于 8 ms**，不新增/丢失合格操作。该接口容差必须写进测试，而不是让旧逐拍比较一直失败或随意放宽。

### 5.3 估算与风险

| 项 | 内容 |
|---|---|
| 预估净 LUT 收益 | **250–500**（按 O2 后 24–25 路预算，**不可按 27 路满额**） |
| FF 影响 | 约 250–380 FF 净下降（20 bit 计数器 → 7 bit） |
| BRAM/DSP | 无目标增量 |
| 风险等级 | **中** |
| 验证要求 | 定向门限 1、参数缩放模型覆盖全 tick 相位、真实 8 ms、复位中按住、<8 ms 毛刺、tick 之间毛刺、两次短毛刺、按/松边界与全通道并发；热插拔 DIP1、DIP 上电配置、消隐首键吞掉、Boot 保护、EC1/EC2 快速正反转、IR 并发回归 |

---

## 6. 排序建议清单（按收益/风险）

> 以下为**规划区间，不是实测承诺**。各轮在上一已接受版本上测**净增量**，不能把重叠子模块收益相加。

| 优先级/轮次 | 优化 | 规模依据（`gate.area` 实测） | 暂估净 LUT | 风险 | 前置条件 |
|---|---|---|---:|---|---|
| **O0** | **重建冻结基线** | 112 项中 **12 项已变** | 0 | 低 | **必须先做**，否则所有差分无意义 |
| **O1** | 删除 UART 遥测（D1） | reporter 860+23；health 112+43 部分 | **750–1000** | 中低 | 保留 LED 故障与非 UART 观测 |
| **O2** | 撤销母板 KEY1/KEY2 整链（D2） | menu 267；两个 hold 169；`u_key_auto` 36；母板两路约 70 | **550–850** | 中 | 先写负例测试；KEY3 口径先定 |
| **O3** | 删除三行调试 OSD（D3） | 层次行 6 LUT（可能归属迁移） | **0–250** | 中低 | 差分测量，拒绝与 AXIS 双重记账 |
| **O4** | 24/25 路共享消抖时基 | 原 27 个通用消抖器 | **250–500** | 中 | 重算 SETTLE/PRESENT 窗口 |
| **O5** | 字库转 BRAM（D4） | `u_font_rom` 424 LUT 纯组合；960×16 bit | **280–400**（+2 BRAM9K） | 中 | 改生成器而非生成结果；逐像素比对 |
| **O6** | 工程卫生与约束清理（D5 + 排除文件） | AutoExcluded 11 项 | **0** | 低 | 不得弄坏回归 |
| **O7** | 集成验收与预算准入 | — | — | — | 至少 2 个 seed + 板验记录 |
| 条件项 | FAT 字段/算术共享、SD 接口只读精简 | 大模块存储/仲裁开销 | 未证明 | 高 | 会碰 100 MHz 与媒体可靠性，不计入本轮预算 |

### 6.1 阶段预算

| 阶段目标 | Slice 上限 | 从 9288 至少回收 | 含义 |
|---|---:|---:|---|
| 解除 90% 高占用区 | 8820（90%） | 468 | 仅应急线 |
| 本轮最低开发门禁 | 8624（88%） | 664 | 仅允许预算闭合的小步开发 |
| 本轮优先目标 | 8232（84%） | 1056 | 给后续核心功能留余量 |

**全部四轮的规划区间简单相加**约 1830–3000 LUT；保守工作目标取**净 LUT 1800–2800、Slice 800–1400**，**没有统计置信区间或保证**。最终以整机 PnR 为准，不能按 LUT/2 折算 Slice。若只省 800 Slice，则约 8488/9800 = 86.61%，**只满足小步开发，不能据此承诺后续 X4/X5 全装下**。

---

## 7. 执行前置任务（O0，最高优先级）

**由于基线已失效，以下必须先完成，否则后续任何差分都不可信：**

1. **裁定 12 项已改文件的去留**。这些改动包含真实产品行为变更（数码管 6→8 位、KEY3 停用、EC1/EC2 Seek 对调、数码管计时并入 `timebase_48k`），不能按「未提交噪声」处理，也不能直接丢弃。
2. 裁定后**重新生成输入哈希清单**，形成与当前源码一致的新冻结基线快照。
3. 用当前源码**重新综合 + 布线 + fix_hold**，得到与源码匹配的 `final.area/final.qor/final.timing`。
4. 记录当次 HEAD、工作树业务改动、逐项 PASS/FAIL 回归结果与已知警告。
5. 固定生产构建 `area_prior`、首选 seed 5 与对照 seed 7。
6. **先跑一次当前生产回归**冻结起点（旧母板/UART 正例此时仍应通过，作为 O1/O2 的对照）。

---

## 8. 验证与验收门禁

### 8.1 每轮构建命令（工作目录 `VinylFPGA`，快照名必须全新）

```powershell
$env:PATH = 'D:\iverilog\bin;' + $env:PATH
python tools/verify_s7_acceptance.py
python tools/verify_s0_s5_fixes.py
python tools/verify_s6.py
python tools/test_vinyl_packer.py
python tools/resource_opt_round.py O1_uart_removed_20261007_s5
python tools/build_verified_round.py O1_uart_removed_20261007_s5 --seed 5 --map-mode area_prior
python tools/resource_opt_round.py O1_uart_removed_20261007_s7
python tools/build_verified_round.py O1_uart_removed_20261007_s7 --seed 7 --map-mode area_prior
```

每条命令检查退出码，**失败不得顺序继续**。构建脚本明确执行 route 后 fix_hold；同时核查 TNS、违例端点、约束、资源，**不只看退出码**。

### 8.2 阶段差分表（实施时填实测，不填估计值冒充完成）

| 轮次 | 唯一变化 | 基准/候选 hash | Slice | LUT | REG | BRAM/DSP | Setup/Hold WNS | 回归/板验 |
|---|---|---|---:|---:|---:|---|---|---|
| 历史基线 | area_prior seed5 | 66da60f / X2_r15s5（**已失效**） | 9288 | 17415 | 10527 | 40/17 | +48/+24 ps | 不重开历史板验 |
| O0 新基线 | 待裁定 12 项后重建 | 待生成 | 待测 | 待测 | 待测 | 待测 | 待测 | 待执行 |
| O1–O7 | 按任务卡逐轮填写 | 实施时生成 | 待测 | 待测 | 待测 | 待测 | 待测 | 待执行 |

### 8.3 全局门禁

| 项目 | 门槛 |
|---|---|
| Slice | 实际 ≤ 该阶段预算，且至少回到 **88%（8624）** 以内 |
| LUT | 净下降，按 O1–O5 逐轮累加验证 |
| Setup / Hold WNS | ≥ 0，TNS = 0，违例端点 = 0 |
| BRAM9K / DSP | ≤ 64 / ≤ 29（O5 后目标 42/64） |
| 时钟 / IO | 无错误约束、无未解释的新增警告 |
| 工程努力目标 | setup ≥ 0.1 ns、hold ≥ 0.05 ns；**未达到时报告实际裕量，不放宽时钟掩盖问题** |
| 功能矩阵 | 已删除行为、输入（12 键各 100 次、EC 正反各 100 格、DIP 每项 20 次、IR）、保留母板、媒体控制、显示、音频、故障观测、物理实现（≥2 seed）、板验 |
| 板验 | 1 h 交叉操作 + 切换/Seek 各 100 次 + 冷启动；**不用仿真 PASS 代替** |

### 8.4 必须迁移的测试

| 删除对象 | 受影响 TB | 处理 |
|---|---|---|
| `param_menu_controller` | `sim/tb_param_menu_controller.v` | 改为 legacy 组或重写为「菜单不可进入」负例 |
| `exp_echo_reporter` | `sim/tb_echo_telemetry.v` | 改为「串口恒静默且其他业务正常」，历史格式测试归 legacy，**不伪造 PASS** |
| `health_monitor` | `sim/tb_health_monitor.v` | 改为「当前错误可清零 + 4 个 sticky 标志」 |
| `osd_overlay_24` | `sim/tb_osd_overlay.v` | 改为 `tb_opt_osd_bypass.v`：整帧逐像素旁路比对 |
| `key_dip_monitor` | `sim/tb_io_startup_dip.v`、`sim/tb_s2_boot_guard.v` | 按新消抖引擎重写门限测试 |

**注意**：`health_monitor.v` **不在** `prj/VinylFPGA.al`，仅经 `top_tf_hdmi_audio.v:21` 的 `include` 参与构建。删除时**不能只改 `.al`**。
全工程共 **28 个** `.v` 属「仅 include、未登记 `.al`」，O6 清理工程表时须一并处理，但**不得**为图整齐而改变当前可构建的编译单元结构。

---

## 9. 最终结论

1. **优化方向成立。** 以 Slice/LUT 下降为首要目标，通过删除用户明确不要的功能（UART 遥测、母板 KEY1/KEY2 旧交互、左上角调试字符）来回收 Slice，是当前**风险最低、边界最清晰、收益最可验证**的路径。

2. **最高收益入口是 O1 与 O2**（合计规划 1300–1850 LUT）。共享消抖（O4）与字库 BRAM（O5）是第二梯队（合计 530–900 LUT）。

3. **字库转 BRAM 是全工程最干净的一笔交易**：`u_font_rom` 424 LUT、ripple 0、seq 0，是纯组合逻辑，转换后 **+2 BRAM9K**（BRAM 余量 24 充足）。

4. **必须先做 O0。** 本次复核发现 `X2_r15s5_20261007` 基线的 112 项输入中已有 **12 项与当前工作区不一致**，且未提交改动包含真实产品行为变更（数码管 8 位化、KEY3 停用、EC1/EC2 Seek 对调）。在基线重建前，任何「优化收益」都缺乏可比对象。

5. **不能承诺的具体事项**：Slice 降幅无法按 LUT 线性折算；`u_osd_overlay_24` 层次行仅 6 LUT 但下游存在归属迁移，必须差分实测；画质若因常量旁路释放 3 个 DSP，属暂时收益，X5 恢复动态控制时会回来。

6. **本次交付的是分析与执行方案。** 未修改任何生产 RTL、未重新综合、未布线、未生成位流、未烧录。所有预计收益仍待 O0–O7 实施验证。

---

### 附录 A：本次核查证据清单

| 证据 | 路径 / 命令 | 用途 |
|---|---|---|
| SynthPilot 用法 | `curl -sL https://www.synthpilot.dev/llms.txt` | 已按要求先执行。**本会话未连接该 MCP，工具检索未返回任何 synthpilot 工具**，故未用于分析；不伪造调用、不用原始 Tcl 绕过 |
| Git 状态 | `git log --oneline`、`git status --short`、`git rev-parse HEAD` | HEAD `66da60f`；13 个生产文件 + `pin.adc` 已修改未提交 |
| 输入哈希复核 | `inputs.sha256.json` 逐项 SHA256 重算 | **100/112 一致，12 DIFF** |
| 最终资源 | `X2_r15s5_20261007/final.area:4-29`、`final.qor:6-24` | Slice 9288 / LUT 17415 / REG 10527 / BRAM 40 / DSP 17 |
| 最终时序 | `X2_r15s5_20261007/final.timing:8,27-28,32-51,79-80` | SWNS +0.048 ns / HWNS +0.024 ns / 9649 端点 / 六时钟 |
| 综合层次 | `X2_r15s5_20261007/gate.area`（解析 194 行） | 逐实例 LUT/ripple/seq/BRAM/DSP |
| 工程源表 | `prj/VinylFPGA.al`（76 个 src 条目，11 处 AutoExcluded） | 28 个 `.v` 仅 include 未登记 |
| 约束 | `constraints/pin.adc`、`timing.sdc` | `key1=B2`、`key2=C1`、`key3=B1`；`seg_sel` 已改 8 位 |
| 源码 | `exp_echo_reporter.v`(565行)、`param_menu_controller.v`(303)、`key_press_hold.v`(89)、`status_osd_overlay.v`(156)、`osd_overlay_24.v`(82)、`debounce_filter.v`(49)、`key_dip_monitor.v`(84)、`lrc_font_rom.v`(974) | 删除闭包与行号依据 |

### 附录 B：本次未能完成的核查

| 项 | 原因 |
|---|---|
| SynthPilot MCP 结构/复杂度分析 | 本会话无该 MCP 连接。已按要求先执行 `curl` 获取用法说明并核对工具清单，但运行时未返回 synthpilot 工具 |
| 当前源码的实测资源 | 本次未重新综合。12 项输入已变，现有无与当前源码匹配的实现后报告 |
| 12 项已改文件的意图与正确性 | 需用户确认（尤其数码管 8 位化与 EC1/EC2 Seek 对调属行为变更） |

---

*本文基于 `git HEAD=66da60f` 与工作区实际状态、`X2_r15s5_20261007` 报告文件、源码实测三方交叉核对生成。*
